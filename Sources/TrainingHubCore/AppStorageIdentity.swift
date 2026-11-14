import Foundation

/// The optional preview has its own library, preferences (bundle ID) and Garmin credential service.
public enum AppStorageIdentity {
    public static let aiPreviewBundleID = "local.traininghub.ai.preview"
    public static func libraryDirectory(bundleID: String? = Bundle.main.bundleIdentifier) -> String {
        bundleID == aiPreviewBundleID ? "GarHubAIPreview" : "GarminTrainingHub"
    }
    public static func garminKeychainService(bundleID: String? = Bundle.main.bundleIdentifier) -> String {
        bundleID == aiPreviewBundleID ? "local.traininghub.ai.preview.garmin-personal-api" : "local.traininghub.mac.garmin-personal-api"
    }
}
