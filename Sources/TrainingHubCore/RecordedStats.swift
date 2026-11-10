import Foundation
import FITSwiftSDK

public struct RecordedStat: Identifiable, Sendable {
    public let id: String
    public let field: String
    public let value: String
    public let unit: String
}
public struct RecordedSessionStats: Identifiable, Sendable {
    public let id: Int
    public let stats: [RecordedStat]
}
extension FITImporter {
    public static func sessionStats(_ data: Data) throws -> [RecordedSessionStats] {
        guard data.count >= 14, data.count <= maximumFileSize else { throw HubError.message("The original FIT file has an unsupported size.") }
        let decoder = FITSwiftSDK.Decoder(stream: FITSwiftSDK.InputStream(data: data))
        guard try decoder.isFIT(), try decoder.checkIntegrity() else { throw HubError.message("The original FIT file failed its integrity check.") }
        let listener = FitListener(); decoder.addMesgListener(listener); try decoder.read()
        let sessions = orderedSessions(listener.fitMessages.sessionMesgs)
        return sessions.enumerated().map { index, session in
            var stats: [RecordedStat] = []
            func append(_ field: FieldBase, prefix: String, name: String, unit: String, subfield: UInt16? = nil) {
                var values: [String] = []
                for position in 0..<256 {
                    guard field.getRawValue(index: position) != nil else { break }
                    let value = subfield.flatMap { try? field.getValue(index: position, subFieldIndex: $0) } ?? field.getValue(index: position)
                    if let number = value as? NSNumber {
                        values.append(number.doubleValue.isFinite ? number.stringValue : "Not recorded")
                    } else if let value { values.append(String(describing: value)) }
                    else { values.append("Not recorded") }
                }
                guard !values.isEmpty, values.contains(where: { $0 != "Not recorded" }) else { return }
                stats.append(RecordedStat(id: prefix + String(field.getNum()), field: name, value: values.joined(separator: ", "), unit: unit))
            }
            for field in session.getFields() {
                let active = try? session.getActiveSubFieldIndex(fieldNum: field.getNum())
                append(field, prefix: "fit:", name: field.getName(subFieldIndex: Int(active ?? FIT.SUBFIELD_INDEX.MAIN_FIELD)),
                       unit: field.getUnits(subFieldIndex: Int(active ?? FIT.SUBFIELD_INDEX.MAIN_FIELD)), subfield: active)
            }
            for (offset, field) in session.developerFields.enumerated() {
                append(field, prefix: "developer:\(offset):", name: "Developer · " + field.getName(), unit: field.getUnits())
            }
            return RecordedSessionStats(id: index, stats: stats.sorted { $0.field < $1.field })
        }
    }
}
extension ActivityStore {
    func originalRecording(fileHash: String) throws -> Data {
        guard fileHash.count == 64, fileHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw HubError.message("The original activity identifier is invalid.") }
        let file = root.appendingPathComponent("Originals/\(fileHash).fit")
        let data = try FITImporter.readFile(file)
        guard FITImporter.hash(data) == fileHash else { throw HubError.message("The original recording checksum does not match.") }
        return data
    }

    public func recordedStats(fileHash: String) throws -> [RecordedSessionStats] {
        try FITImporter.sessionStats(originalRecording(fileHash: fileHash))
    }
}
