import Foundation
import CZlib

/// Reads Garmin ZIP downloads in memory. Archive paths are never extracted to disk.
public enum FITZip {
    public struct Entry: Sendable { public let name: String; public let data: Data }
    public static func read(_ data: Data, maximumSize: Int = 100_000_000) throws -> [Entry] {
        guard data.count <= maximumSize, data.count >= 22 else { throw invalid() }
        let reader = Reader(data)
        let lower = max(0, data.count - 65_557)
        var footer: Int?
        for index in stride(from: data.count - 22, through: lower, by: -1) {
            if (try? reader.u32(index)) == 0x06054b50, let comment = try? reader.u16(index + 20), index + 22 + comment == data.count {
                footer = index; break
            }
        }
        guard let end = footer else { throw invalid() }
        // Multi-disk, ZIP64 and encrypted downloads are outside Garmin's original-file format.
        guard try reader.u16(end + 4) == 0, try reader.u16(end + 6) == 0,
              try reader.u16(end + 8) == reader.u16(end + 10), try end + 22 + reader.u16(end + 20) == data.count else { throw invalid() }
        let count = try reader.u16(end + 10)
        let directorySize = try reader.u32(end + 12)
        var offset = try reader.u32(end + 16)
        guard count <= 1_000, count != 65_535, offset + directorySize <= end else { throw invalid() }
        let directoryEnd = offset + directorySize
        var result: [Entry] = []
        var expanded = 0
        var names = Set<String>()
        for _ in 0..<count {
            guard try reader.u32(offset) == 0x02014b50 else { throw invalid() }
            let flags = try reader.u16(offset + 8)
            let method = try reader.u16(offset + 10)
            let checksum = try reader.u32(offset + 16)
            let compressedSize = try reader.u32(offset + 20)
            let size = try reader.u32(offset + 24)
            let nameSize = try reader.u16(offset + 28)
            let extraSize = try reader.u16(offset + 30)
            let commentSize = try reader.u16(offset + 32)
            let attributes = try reader.u32(offset + 38)
            let local = try reader.u32(offset + 42)
            let nameBytes = try reader.bytes(offset + 46, nameSize)
            guard let name = String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .isoLatin1),
                  !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"),
                  !name.split(separator: "/").contains(".."), names.insert(name.lowercased()).inserted,
                  flags & 1 == 0, [0, 8].contains(method), size <= maximumSize, compressedSize <= maximumSize,
                  [0, 0o100000, 0o040000].contains((attributes >> 16) & 0o170000) else { throw invalid() }
            offset += 46 + nameSize + extraSize + commentSize
            guard offset <= directoryEnd else { throw invalid() }
            expanded += size
            guard expanded <= maximumSize else { throw invalid() }
            guard name.lowercased().hasSuffix(".fit") else { continue }
            guard try reader.u32(local) == 0x04034b50, try reader.u16(local + 6) == flags,
                  try reader.u16(local + 8) == method else { throw invalid() }
            let localNameSize = try reader.u16(local + 26)
            let localExtraSize = try reader.u16(local + 28)
            guard try reader.bytes(local + 30, localNameSize) == nameBytes else { throw invalid() }
            let start = local + 30 + localNameSize + localExtraSize
            guard start + compressedSize <= directoryEnd - directorySize else { throw invalid() }
            let compressed = try reader.bytes(start, compressedSize)
            let decoded = try method == 0 ? compressed : inflate(compressed, size: size)
            guard decoded.count == size, decoded.withUnsafeBytes({ Int(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))) }) == checksum else { throw invalid() }
            result.append(Entry(name: URL(fileURLWithPath: name).lastPathComponent, data: decoded))
        }
        guard offset == directoryEnd, !result.isEmpty else { throw HubError.message("The Garmin download did not contain a supported FIT file.") }
        return result
    }

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        var output = Data(count: max(1, size))
        let actual = try output.withUnsafeMutableBytes { target -> Int in
            try data.withUnsafeBytes { source -> Int in
                var stream = z_stream()
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(source.count)
                stream.next_out = target.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(target.count)
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw invalid() }
                defer { inflateEnd(&stream) }
                let status = CZlib.inflate(&stream, Z_FINISH)
                guard status == Z_STREAM_END, Int(stream.total_out) == size, Int(stream.total_in) == data.count else { throw invalid() }
                return Int(stream.total_out)
            }
        }
        return Data(output.prefix(actual))
    }
    private static func invalid() -> HubError { .message("The ZIP download is damaged, unsupported, encrypted, or exceeds the import limit.") }
    private struct Reader {
        let data: Data
        init(_ data: Data) { self.data = data }
        func bytes(_ offset: Int, _ count: Int) throws -> Data {
            guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else { throw invalid() }
            return data.subdata(in: offset..<offset + count)
        }
        func u16(_ offset: Int) throws -> Int { try bytes(offset, 2).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) } }
        func u32(_ offset: Int) throws -> Int { try bytes(offset, 4).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) } }
    }
}
