import SwiftUI
import AppKit
import TrainingHubCore

struct CoachView: View {
    let activities: [Activity]
    let health: [HealthDay]
    @AppStorage("coach.goal") private var goal = ""
    @State private var includeHealth = false
    @State private var brief = ""
    @State private var copied = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    HubEyebrow("Coaching brief", color: HubTheme.accent)
                    Text("Prompt builder").hubHeading()
                }
                Text("Prepare and review a compact summary, then copy it into your preferred ChatGPT conversation. Nothing is sent automatically, and this app makes no AI API calls.").foregroundStyle(.secondary)
                TextField("Your goal, target race, and available training time", text: $goal, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4)
                Toggle("Include selected health averages and recorded coverage", isOn: $includeHealth)
                HStack {
                    Button("Prepare coaching brief") {
                        brief = CoachBrief.make(activities: activities, health: health, goal: goal, includeHealth: includeHealth)
                        copied = false
                    }
                    Button(copied ? "Copied" : "Copy reviewed brief") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(brief, forType: .string); copied = true
                    }.disabled(brief.isEmpty)
                }
                if !brief.isEmpty {
                    Text("Preview · copy uses exactly this text").font(.headline)
                    Text(brief).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hubPanel()
                }
                Text("GPS, routes, activity names, free-text activity notes, raw recordings and credentials are excluded. Your goal text is included. After changing options, prepare the brief again to refresh its preview.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }
    }
}
