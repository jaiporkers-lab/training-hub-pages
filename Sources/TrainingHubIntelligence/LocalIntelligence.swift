import Foundation
import Combine
import TrainingHubCore
#if canImport(FoundationModels) && !GARHUB_NO_ON_DEVICE_AI
import FoundationModels
#endif

public enum LocalAIAvailability: Equatable, Sendable {
    case off
    case ready
    case unavailable(String)

    public var message: String {
        switch self {
        case .off: "AI features are off. No model requests run."
        case .ready: "Apple's on-device model is available."
        case .unavailable(let message): message
        }
    }
}

@MainActor
protocol LocalHighlightGenerating {
    func availability() -> LocalAIAvailability
    func select(from evidence: InsightEvidence) async throws -> [String]
}

/// The only production model adapter. No provider abstraction, remote tools or cloud fallback.
@MainActor
private struct AppleOnDeviceHighlights: LocalHighlightGenerating {
    func availability() -> LocalAIAvailability {
        #if canImport(FoundationModels) && !GARHUB_NO_ON_DEVICE_AI
        if #available(macOS 26, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                guard model.supportsLocale(Locale.current) else {
                    return .unavailable("Your current language isn't supported by the on-device model. The ordinary comparison remains available.")
                }
                return .ready
            case .unavailable(.deviceNotEligible):
                return .unavailable("This Mac isn't eligible for Apple's on-device model. The ordinary comparison remains available.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Apple Intelligence is off in System Settings. GarHub won't change that setting.")
            case .unavailable(.modelNotReady):
                return .unavailable("The on-device model isn't ready. macOS may still be preparing its download. Try checking again later.")
            case .unavailable:
                return .unavailable("The on-device model is currently unavailable. The ordinary comparison remains available.")
            }
        }
        return .unavailable("On-device AI requires macOS 26 or later and an eligible Mac. All ordinary GarHub features remain available.")
        #else
        return .unavailable("This build doesn't include the on-device AI adapter. All ordinary GarHub features remain available.")
        #endif
    }

    func select(from evidence: InsightEvidence) async throws -> [String] {
        guard availability() == .ready, evidence.facts.count <= 8, evidence.modelInput.utf8.count <= 4_000 else {
            throw LocalHighlightError.unavailable
        }
        #if canImport(FoundationModels) && !GARHUB_NO_ON_DEVICE_AI
        if #available(macOS 26, *) {
            try Task.checkCancellation()
            let key = DynamicGenerationSchema(name: "EvidenceKey", anyOf: evidence.facts.map(\.id))
            let root = DynamicGenerationSchema(name: "Highlights", properties: [
                .init(name: "keys", description: "One to three distinct evidence keys, most useful first.",
                      schema: .init(arrayOf: key, minimumElements: 1, maximumElements: 3))
            ])
            let schema = try GenerationSchema(root: root, dependencies: [])
            let session = LanguageModelSession(model: SystemLanguageModel.default, tools: [], instructions: """
                Select useful evidence keys for a recorded activity comparison. Use ONLY supplied facts.
                Do not calculate or infer fitness, fatigue, recovery, illness, or causes. Give no advice.
                Return one to three distinct keys, most useful first. Prefer overall facts, then leg differences.
                """
            )
            #if compiler(>=6.4)
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 128)
            #else
            let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 128)
            #endif
            let response = try await session.respond(to: evidence.modelInput, schema: schema, options: options)
            try Task.checkCancellation()
            return try response.content.value([String].self, forProperty: "keys")
        }
        #endif
        throw LocalHighlightError.unavailable
    }
}

private enum LocalHighlightError: Error { case unavailable }

/// One cancellable request across the app. Opt-in is per Mac and isn't restored from a library backup.
@MainActor
public final class LocalIntelligence: ObservableObject {
    public static let enabledKey = "intelligence.onDeviceEnabled"
    @Published public var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            cancel()
            refreshAvailability()
        }
    }
    @Published public private(set) var availability: LocalAIAvailability = .off
    @Published public private(set) var evidence: InsightEvidence?
    @Published public private(set) var selectedIDs: [String] = []
    @Published public private(set) var message = ""
    @Published public private(set) var isRunning = false
    private let defaults: UserDefaults
    private let generator: any LocalHighlightGenerating
    private let timeout: Duration
    private var requestID: UUID?
    private var operation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, generator: AppleOnDeviceHighlights(), timeout: .seconds(20))
    }

    init(defaults: UserDefaults, generator: any LocalHighlightGenerating, timeout: Duration) {
        self.defaults = defaults; self.generator = generator; self.timeout = timeout
        enabled = defaults.bool(forKey: Self.enabledKey)
        refreshAvailability()
    }

    public func refreshAvailability() {
        availability = enabled ? generator.availability() : .off
    }

    public func cancel() {
        requestID = nil
        operation?.cancel(); deadline?.cancel(); deadline = nil
        evidence = nil; selectedIDs = []; message = ""; isRunning = false
        // Keep the operation slot until the backend actually stops, preventing overlapping calls.
    }

    public func highlight(_ packet: InsightEvidence) {
        guard enabled else { return }
        refreshAvailability()
        guard operation == nil else {
            message = "The previous local request is stopping. Try again shortly."
            return
        }
        evidence = packet; selectedIDs = []
        guard availability == .ready else { message = availability.message; return }
        let id = UUID()
        requestID = id; isRunning = true; message = "Choosing highlights on this Mac…"
        operation = Task { [weak self, generator] in
            defer { self?.finishOperation(id: id) }
            do {
                let ids = try await generator.select(from: packet)
                try Task.checkCancellation()
                _ = try packet.selectedFacts(ids: ids)
                guard let self, self.enabled, self.requestID == id, self.evidence == packet else { return }
                self.selectedIDs = ids
                self.message = "Selected on this Mac from the verified comparison facts below."
            } catch {
                guard let self, self.requestID == id else { return }
                self.selectedIDs = []
                self.message = "On-device highlights couldn't be completed. The recorded facts below remain available."
            }
        }
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.requestID == id else { return }
            self.requestID = nil; self.operation?.cancel(); self.isRunning = false
            self.selectedIDs = []
            self.message = "On-device highlights took too long. The recorded facts below remain available."
        }
    }

    private func finishOperation(id: UUID) {
        // There can be only one occupied slot, even after cancel clears the visible request ID.
        operation = nil
        deadline?.cancel(); deadline = nil
        if requestID == id { isRunning = false }
    }
}
