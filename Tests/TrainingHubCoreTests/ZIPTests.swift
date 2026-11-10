import XCTest
import Foundation
import CZlib
@testable import TrainingHubCore

enum ZIPFixture {
    static func make(_ payload: Data, name: String = "activity.fit", deflated: Bool = false, mode: UInt32 = 0o100600) -> Data {
        let name = Data(name.utf8)
        let checksum = payload.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))) }
        var compressed = payload
        if deflated {
            var count = compressBound(uLong(payload.count))
            var buffer = Data(count: Int(count))
            let status = buffer.withUnsafeMutableBytes { output in payload.withUnsafeBytes { input in
                compress2(output.bindMemory(to: Bytef.self).baseAddress, &count, input.bindMemory(to: Bytef.self).baseAddress, uLong(payload.count), Z_DEFAULT_COMPRESSION)
            } }
            precondition(status == Z_OK)
            compressed = buffer.subdata(in: 2..<Int(count) - 4) // Standard zlib wrapper removed for ZIP raw DEFLATE.
        }
        var local = Data()
        local.u32(0x04034b50); local.u16(20); local.u16(0); local.u16(deflated ? 8 : 0); local.u16(0); local.u16(0)
        local.u32(checksum); local.u32(UInt32(compressed.count)); local.u32(UInt32(payload.count)); local.u16(UInt16(name.count)); local.u16(0)
        local += name; local += compressed
        var central = Data()
        central.u32(0x02014b50); central.u16(0x0314); central.u16(20); central.u16(0); central.u16(deflated ? 8 : 0); central.u16(0); central.u16(0)
        central.u32(checksum); central.u32(UInt32(compressed.count)); central.u32(UInt32(payload.count)); central.u16(UInt16(name.count))
        central.u16(0); central.u16(0); central.u16(0); central.u16(0); central.u32(mode << 16); central.u32(0); central += name
        var end = Data(); end.u32(0x06054b50); end.u16(0); end.u16(0); end.u16(1); end.u16(1)
        end.u32(UInt32(central.count)); end.u32(UInt32(local.count)); end.u16(0)
        return local + central + end
    }
}
private extension Data {
    mutating func u16(_ value: UInt16) { append(UInt8(value & 255)); append(UInt8(value >> 8)) }
    mutating func u32(_ value: UInt32) { u16(UInt16(value & 65_535)); u16(UInt16(value >> 16)) }
}

final class ZIPTests: XCTestCase {
    func testStoredAndDeflatedFITDownloadsDecodeIdentically() throws {
        let data = try DemoFIT.make(multisport: true)
        for deflated in [false, true] {
            let archive = ZIPFixture.make(data, name: "original/ACTIVITY.FIT", deflated: deflated)
            let entries = try FITZip.read(archive)
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries[0].name, "ACTIVITY.FIT")
            XCTAssertEqual(entries[0].data, data)
            XCTAssertEqual(try FITImporter.decode(entries[0].data, name: "Race").count, 2)
        }
    }
    func testUnsafePathsAndSymlinksAreRejected() {
        for name in ["../outside.fit", "/outside.fit", "folder/../outside.fit", "C:\\outside.fit"] {
            XCTAssertThrowsError(try FITZip.read(ZIPFixture.make(Data("data".utf8), name: name)))
        }
        XCTAssertThrowsError(try FITZip.read(ZIPFixture.make(Data("target".utf8), mode: 0o120777)))
    }
    func testCRCTruncationAndResourceLimitsAreEnforced() {
        var data = ZIPFixture.make(Data("example FIT bytes".utf8))
        data[30 + Data("activity.fit".utf8).count] ^= 1
        XCTAssertThrowsError(try FITZip.read(data))
        let valid = ZIPFixture.make(Data("example FIT bytes".utf8))
        for length in stride(from: 0, to: valid.count, by: 9) { XCTAssertThrowsError(try FITZip.read(Data(valid.prefix(length)))) }
        XCTAssertThrowsError(try FITZip.read(valid, maximumSize: 10))
        XCTAssertThrowsError(try FITZip.read(ZIPFixture.make(Data("not FIT".utf8), name: "recording.tcx")))
    }
}
