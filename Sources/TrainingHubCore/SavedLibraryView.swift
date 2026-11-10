import Foundation

public struct SavedLibraryView: Codable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let search: String
    public let sport: String
    public let days: Int
    public let sort: String
    public init(title: String, search: String, sport: String, days: Int, sort: String) {
        id = UUID(); self.title = title; self.search = search; self.sport = sport; self.days = days; self.sort = sort
    }
}
