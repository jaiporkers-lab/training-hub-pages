import Foundation
import FITSwiftSDK
import XCTest
@testable import TrainingHubCore

final class RouteHeatmapTests: XCTestCase, @unchecked Sendable {
    func testOverlapIncreasesHeatButRepeatedPassesInOneActivityDoNot() throws {
        let line = [gps(0, lon: -0.002), gps(18, lon: 0.002)]
        let viewport = CGRect(x: 0.49999, y: 0.49999, width: 0.00002, height: 0.00002)
        var builder = RouteHeatmap.Builder()
        try builder.addSession(line)
        try builder.addSession(line)
        builder.finishActivity()
        let one = builder.makeHeatmap()
        XCTAssertEqual(one.activityCount, 1)
        let single = try XCTUnwrap(RouteHeatRaster.density(one, viewport: viewport, width: 128, height: 128, radius: 12))
        XCTAssertEqual(single.max(), 255)
        XCTAssertEqual(single[0], 0)
        XCTAssertGreaterThan(single[64 * 128 + 64], single[71 * 128 + 64])
        XCTAssertGreaterThan(single[71 * 128 + 64], 0)

        try builder.addSession(line)
        builder.finishActivity()
        let two = builder.makeHeatmap()
        let double = try XCTUnwrap(RouteHeatRaster.density(two, viewport: viewport, width: 128, height: 128, radius: 12))
        XCTAssertEqual(two.activityCount, 2)
        XCTAssertEqual(double.max(), 510)
        XCTAssertEqual(double[64 * 128 + 64], single[64 * 128 + 64] * 2)
    }

    func testGPSGapsAndJumpsDoNotDrawConnectingStrokes() throws {
        let viewport = CGRect(x: 0.49999, y: 0.49999, width: 0.00002, height: 0.00002)
        var builder = RouteHeatmap.Builder()
        try builder.addSession([gps(0, lon: -0.002), gps(7, lat: nil), gps(18, lon: 0.002)])
        builder.finishActivity()
        try builder.addSession([gps(0, lon: -0.002), gps(31, lon: 0.002)])
        builder.finishActivity()
        try builder.addSession([gps(0, lon: -0.002), gps(1, lon: 0.002)])
        builder.finishActivity()
        let map = builder.makeHeatmap()
        XCTAssertEqual(map.activities.map { $0.map { $0.points.count } }, [[1, 1], [1, 1], [1, 1]])
        let field = try XCTUnwrap(RouteHeatRaster.density(map, viewport: viewport, width: 128, height: 128, radius: 12))
        XCTAssertEqual(field[64 * 128 + 64], 0)
        XCTAssertGreaterThan(field.max() ?? 0, 0)
    }

    func testDatelineRoutesStayCompactAndInvalidCoordinatesAreOmitted() throws {
        var builder = RouteHeatmap.Builder()
        try builder.addSession([gps(0, lon: 179.999), gps(18, lon: -179.999), gps(19, lat: 91), gps(20, lon: .nan)])
        builder.finishActivity()
        let map = builder.makeHeatmap()
        let bounds = try XCTUnwrap(map.bounds)
        XCTAssertLessThan(bounds.width, 0.00001)
        XCTAssertGreaterThan(bounds.maxX, 1)
        XCTAssertEqual(map.activities.first?.first?.points.count, 2)
        let viewport = CGRect(x: 0.99999, y: 0.49999, width: 0.00002, height: 0.00002)
        let field = try XCTUnwrap(RouteHeatRaster.density(map, viewport: viewport, width: 128, height: 128, radius: 12))
        XCTAssertGreaterThan(field[64 * 128 + 64], 200)
    }

    func testTileEdgeRetainsHeatFromAStrokeOutsideTheTile() throws {
        var builder = RouteHeatmap.Builder()
        try builder.addSession([gps(0, lon: -0.002), gps(18, lon: 0.002)])
        builder.finishActivity()
        // The line is just to the north of this viewport. Its halo must still be painted.
        let viewport = CGRect(x: 0.49999, y: 0.5000005, width: 0.00002, height: 0.00002)
        let field = try XCTUnwrap(RouteHeatRaster.density(builder.makeHeatmap(), viewport: viewport,
                                                        width: 128, height: 128, radius: 12))
        XCTAssertGreaterThan(field[64], 0)
        XCTAssertEqual(field[127 * 128 + 64], 0)
    }

    func testInspectionCountsEachRecordingOnceAndLeavesGPSGapsOpen() throws {
        var builder = RouteHeatmap.Builder()
        let line = [gps(0, lon: -0.002), gps(18, lon: 0.002)]
        try builder.addSession(line)
        try builder.addSession(line)
        builder.finishActivity(id: "race")
        try builder.addSession([gps(0, lon: -0.002), gps(8, lat: nil), gps(18, lon: 0.002)])
        builder.finishActivity(id: "gap")
        try builder.addSession(line)
        builder.finishActivity(id: "ride")
        let heat = builder.makeHeatmap()
        let radius = 0.0000002
        XCTAssertEqual(heat.activityCount(near: CGPoint(x: 0.5, y: 0.5), radius: radius), 2)
        XCTAssertEqual(heat.activityIDs(near: CGPoint(x: 0.5, y: 0.5), radius: radius), ["race", "ride"])
        XCTAssertEqual(heat.activityIDs(near: CGPoint(x: 179.998 / 360, y: 0.5), radius: radius), ["race", "gap", "ride"])
        XCTAssertTrue(heat.activityIDs(near: CGPoint(x: 0.5, y: 0.500002), radius: radius).isEmpty)
    }

    func testInspectionFindsWrappedRoutesAcrossSpatialIndexBranches() throws {
        var builder = RouteHeatmap.Builder()
        for index in 0..<20 {
            try builder.addSession([gps(0, lon: Double(index) * 7)])
            builder.finishActivity(id: "other-\(index)")
        }
        try builder.addSession([gps(0, lon: 179.999), gps(18, lon: -179.999)])
        builder.finishActivity(id: "dateline")
        let heat = builder.makeHeatmap()
        for x in [0, 1, -1] {
            XCTAssertEqual(heat.activityIDs(near: CGPoint(x: Double(x), y: 0.5), radius: 0.0000002), ["dateline"])
        }
        XCTAssertEqual(heat.activityIDs(near: CGPoint(x: 0.5, y: 0.5), radius: 0.0000002), ["other-0"])
    }

    func testTrimRemovesEdgeDriftAndKeepsStopsAndGPSGapsInTheMiddle() throws {
        let route = [
            gps(0, lon: -0.003, speed: 0, distance: 0), // stray fix before GPS lock
            gps(50, lon: -0.00002, speed: 0, distance: 0),
            gps(55, lon: 0, speed: 0, distance: 0),
            gps(57, lon: 0.00004, speed: 2, distance: 4),
            gps(60, lon: 0.00010, speed: 2, distance: 11),
            gps(65, lon: 0.00012, speed: 0, distance: 11), // interior stationary drift
            gps(70, lat: nil),
            gps(75, lon: 0.00022, speed: 2, distance: 22),
            gps(80, lon: 0.00030, speed: 2, distance: 31),
            gps(85, lon: 0.00038, speed: 0, distance: 40),
            gps(90, lon: 0.00039, speed: 0, distance: 40),
            gps(130, lon: 0.003, speed: 0, distance: 40)
        ]
        let raw = try routes(route)
        let trimmed = try routes(route, trimStart: true, trimEnd: true)
        XCTAssertEqual(raw.map(\.count), [1, 5, 4, 1])
        XCTAssertEqual(trimmed, [Array(raw[1].dropFirst()), Array(raw[2].dropLast())])
        XCTAssertEqual(try routes(route, trimStart: true), [Array(raw[1].dropFirst()), raw[2], raw[3]])
        XCTAssertEqual(try routes(route, trimEnd: true), [raw[0], raw[1], Array(raw[2].dropLast())])
    }

    func testTrimUsesGPSWhenSensorsAreAbsentAndKeepsInconclusiveRoutes() throws {
        let route = [
            gps(0, lon: -0.00001), gps(5, lon: 0), gps(7, lon: 0.00005), gps(9, lon: 0.00010),
            gps(11, lon: 0.00015), gps(13, lon: 0.00020), gps(18, lon: 0.00021)
        ]
        let raw = try routes(route)
        XCTAssertEqual(try routes(route, trimStart: true, trimEnd: true), [Array(raw[0].dropFirst().dropLast())])
        let sparse = [gps(0), gps(60, lon: 0.001)]
        XCTAssertEqual(try routes(sparse, trimStart: true, trimEnd: true), try routes(sparse))
    }

    func testHeatmapExcludesVirtualAndIndoorGPSFromImportedFITs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OutdoorMap-\(UUID().uuidString)")
        let store = try ActivityStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures: [(Manufacturer, GarminProduct?, [(Sport, SubSport)])] = [
            (.garmin, nil, [(.cycling, .virtualActivity)]),
            (.garmin, nil, [(.running, .treadmill)]),
            (.garmin, nil, [(.running, .indoorRunning)]),
            (.tacx, nil, [(.cycling, .generic)]),
            (.garmin, .tacxTrainingAppMac, [(.cycling, .generic)]),
            (.zwift, nil, [(.running, .generic)]),
            (.wahooFitness, nil, [(.cycling, .road)]),
            (.garmin, nil, [(.cycling, .indoorCycling), (.running, .trail)])
        ]
        for (index, fixture) in fixtures.enumerated() {
            let file = root.appendingPathComponent("Recording \(index).fit")
            try routeFIT(manufacturer: fixture.0, product: fixture.1, sessions: fixture.2).write(to: file)
            let imported = try await store.importFile(file)
            XCTAssertEqual(imported, fixture.2.count)
        }
        let groups = try await ActivityGroup.grouping(store.activities())
        XCTAssertEqual(groups.count, fixtures.count)
        let map = try await store.routeHeatmap(groups: groups, sport: nil, trimIdle: false)
        XCTAssertEqual(map.activityCount, 2)
        XCTAssertEqual(map.activities.map(\.count).sorted(), [2, 2])
        let road = try XCTUnwrap(groups.first { $0.summary.title == "Recording 6" })
        XCTAssertEqual(map.activityIDs(near: CGPoint(x: 0.5, y: 0.5), radius: 0.0000002), [road.id])

        let cycling = try await store.routeHeatmap(groups: groups, sport: "cycling")
        XCTAssertEqual(cycling.activityCount, 1)
        let running = try await store.routeHeatmap(groups: groups, sport: "running")
        XCTAssertEqual(running.activityCount, 1)
        let mixed = try XCTUnwrap(groups.first { $0.isMultisport })
        XCTAssertEqual(mixed.outdoorRouteSessions().map(\.sport), ["running"])
        let focused = try XCTUnwrap(groups.first { $0.summary.title == "Recording 4" })
        let tacx = try await store.routeHeatmap(groups: [focused], sport: nil)
        XCTAssertNil(tacx.bounds)
    }

    private func routeFIT(manufacturer: Manufacturer, product: GarminProduct?, sessions: [(Sport, SubSport)]) throws -> Data {
        let encoder = Encoder()
        let file = FileIdMesg()
        try file.setType(.activity)
        try file.setManufacturer(manufacturer)
        if let product { try file.setGarminProduct(product) }
        encoder.write(mesg: file)
        for (index, (sport, subtype)) in sessions.enumerated() {
            let start = UInt32(1_162_551_600 + index * 200)
            for second in 0..<110 {
                let record = RecordMesg()
                try record.setTimestamp(DateTime(timestamp: start + UInt32(second)))
                try record.setPositionLat(Int32(index * 500_000 + second * 300))
                try record.setPositionLong(Int32(second * 400))
                try record.setSpeed(3)
                try record.setDistance(Double(second) * 3)
                encoder.write(mesg: record)
            }
            let session = SessionMesg()
            try session.setStartTime(DateTime(timestamp: start))
            try session.setSport(sport)
            try session.setSubSport(subtype)
            try session.setTotalElapsedTime(109)
            encoder.write(mesg: session)
        }
        return encoder.close()
    }

    private func routes(_ samples: [Sample], trimStart: Bool = false, trimEnd: Bool = false) throws -> [[CGPoint]] {
        var builder = RouteHeatmap.Builder()
        try builder.addSession(samples, trimStart: trimStart, trimEnd: trimEnd)
        builder.finishActivity()
        return builder.makeHeatmap().activities.flatMap { $0.map(\.points) }
    }

    private func gps(_ seconds: Double, lat: Double? = 0, lon: Double? = 0,
                     speed: Double? = nil, distance: Double? = nil) -> Sample {
        Sample(id: Int(seconds), timestamp: Date(timeIntervalSinceReferenceDate: seconds), elapsed: seconds,
               distance: distance, heartRate: nil, speed: speed, power: nil, cadence: nil, altitude: nil,
               temperature: nil, latitude: lat, longitude: lon)
    }
}
