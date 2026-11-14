import SwiftUI
import TrainingHubCore
import TrainingHubIntelligence

struct LocalAISettingsView: View {
    @EnvironmentObject private var intelligence: LocalIntelligence
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("On-device AI", systemImage: "sparkles").font(.title2.bold())
                Toggle("Enable on-device AI features", isOn: $intelligence.enabled)
                    .toggleStyle(.switch)
                Text("Optional highlights use Apple's on-device model. Your training data stays on this Mac. There are no AI API charges or cloud fallbacks.")
                    .foregroundStyle(.secondary)
                Text(intelligence.availability.message).font(.callout)
                if intelligence.enabled {
                    Button("Check availability again") { intelligence.refreshAvailability() }
                    Text("Open Compare, choose two activities and select Choose on-device highlights. GarHub calculates and verifies the facts; AI only selects which facts to highlight.")
                        .font(.callout)
                }
                Divider()
                Text("Turning this off cancels the current request and clears its result. AI is off by default and does not run in the background. Existing charts, analysis and filters work with AI off.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Requires macOS 26 or later, an eligible Mac, a supported language, and Apple's model ready on the device. macOS manages model downloads and Apple Intelligence settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("This first feature explains recorded comparisons. It does not assess health, recovery or readiness, and does not prescribe training.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.onAppear { intelligence.refreshAvailability() }
    }
}

struct ComparisonInsightPanel: View {
    let evidence: InsightEvidence
    @EnvironmentObject private var intelligence: LocalIntelligence
    private var selected: [InsightFact] {
        guard intelligence.enabled, intelligence.evidence == evidence else { return [] }
        return (try? evidence.selectedFacts(ids: intelligence.selectedIDs)) ?? []
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("On-device highlights", systemImage: "sparkles").font(.headline)
            HStack {
                Button("Choose on-device highlights") { intelligence.highlight(evidence) }
                    .disabled(intelligence.isRunning)
                if intelligence.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { intelligence.cancel() }
                }
            }
            if intelligence.evidence == evidence, !intelligence.message.isEmpty {
                Text(intelligence.message).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(selected) { fact in Text(fact.text).font(.callout).textSelection(.enabled) }
            DisclosureGroup("Verified comparison facts") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(evidence.facts) { fact in Text(fact.text).font(.caption).textSelection(.enabled) }
                }.padding(.top, 6)
            }
            ForEach(evidence.limitations, id: \.self) { limitation in
                Text(limitation).font(.caption).foregroundStyle(.secondary)
            }
        }
        .hubPanel(padding: 18)
        .onChange(of: evidence) { intelligence.cancel() }
        .onDisappear { intelligence.cancel() }
    }
}
