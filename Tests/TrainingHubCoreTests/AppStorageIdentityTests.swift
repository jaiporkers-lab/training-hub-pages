import XCTest
import TrainingHubCore

final class AppStorageIdentityTests: XCTestCase {
    func testPreviewCannotUseStableLibraryOrGarminCredentialService() {
        XCTAssertEqual(AppStorageIdentity.libraryDirectory(bundleID: AppStorageIdentity.aiPreviewBundleID), "GarHubAIPreview")
        XCTAssertEqual(AppStorageIdentity.garminKeychainService(bundleID: AppStorageIdentity.aiPreviewBundleID), "local.traininghub.ai.preview.garmin-personal-api")
        for id in [nil, "local.traininghub.mac", "other.bundle"] {
            XCTAssertEqual(AppStorageIdentity.libraryDirectory(bundleID: id), "GarminTrainingHub")
            XCTAssertEqual(AppStorageIdentity.garminKeychainService(bundleID: id), "local.traininghub.mac.garmin-personal-api")
        }
    }
}
