// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GarminTrainingHub",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GarminTrainingHub", targets: ["TrainingHubApp"]),
        .executable(name: "hub-check", targets: ["HubCheck"])
    ],
    dependencies: [
        .package(url: "https://github.com/garmin/fit-swift-sdk.git", exact: "21.221.0")
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .systemLibrary(name: "CZlib"),
        .target(name: "TrainingHubCore", dependencies: ["CSQLite", "CZlib", .product(name: "FITSwiftSDK", package: "fit-swift-sdk")]),
        .target(name: "TrainingHubIntelligence", dependencies: ["TrainingHubCore"]),
        .executableTarget(name: "TrainingHubApp", dependencies: ["TrainingHubCore", "TrainingHubIntelligence"]),
        .executableTarget(name: "HubCheck", dependencies: ["TrainingHubCore"]),
        .testTarget(name: "TrainingHubCoreTests", dependencies: ["TrainingHubCore", "CSQLite", "CZlib", .product(name: "FITSwiftSDK", package: "fit-swift-sdk")]),
        .testTarget(name: "TrainingHubIntelligenceTests", dependencies: ["TrainingHubIntelligence", "TrainingHubCore"])
    ],
    swiftLanguageModes: [.v6]
)
