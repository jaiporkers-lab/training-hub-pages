import Foundation
import TrainingHubCore

@main
struct HubCheck {
    static func main() async throws {
        let args = CommandLine.arguments.dropFirst()
        guard let rootPath = args.first else {
            print("Usage: hub-check <database-folder> [activity.fit ...]\nWith no FIT paths, imports two labelled synthetic demos.")
            return
        }
        let root = URL(fileURLWithPath: rootPath)
        let store = try ActivityStore(root: root)
        let paths = args.dropFirst()
        if paths.isEmpty {
            let temporary = root.appendingPathComponent("DemoFiles")
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            for variant in 0..<2 {
                let url = temporary.appendingPathComponent("DEMO Ride \(variant + 1).fit")
                try DemoFIT.make(variant: variant).write(to: url)
                let count = try await store.importFile(url, isDemo: true)
                print("Imported \(count) synthetic session(s)")
            }
        } else {
            for path in paths { print("Imported \(try await store.importFile(URL(fileURLWithPath: path))) session(s)") }
        }
        for activity in try await store.activities() {
            let samples = try await store.samples(for: activity.id)
            print("\(activity.isDemo ? "[DEMO] " : "")\(activity.title): \(activity.sport), \(samples.count) samples, \(activity.distance ?? 0) m")
        }
        print("Database: \(root.appendingPathComponent("training.sqlite").path)")
    }
}
