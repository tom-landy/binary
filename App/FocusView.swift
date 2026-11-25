import SwiftUI
import UIKit
import UserNotifications

struct FocusView: View {
    let engine: FocusEngine
    let theme: Theme
    let play: () -> Void
    let reset: () -> Void
    let skip: () -> Void
    let configure: (Int, Int) -> Void
    @State private var custom = false
    @State private var work = 25
    @State private var rest = 5

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Text("Focus").font(.title2.bold())
                    Spacer()
                    Button("Custom", systemImage: "slider.horizontal.3") {
                        work = engine.session.work
                        rest = engine.session.rest
                        custom = true
                    }.labelStyle(.iconOnly)
                    .accessibilityLabel("Custom intervals")
                }
                clock
                HStack(spacing: 15) {
                    Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                    Button(engine.session.end == nil ? "Start" : "Pause",
                           systemImage: engine.session.end == nil ? "play.fill" : "pause.fill",
                           action: play)
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(.black)
                    Button("Skip interval", systemImage: "forward.end", action: skip)
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                HStack(spacing: 8) {
                    preset(25, 5)
                    preset(50, 10)
                    preset(15, 3)
                }
            }
            .padding(22)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $custom) {
            NavigationStack {
                Form {
                    Stepper("Work · \(work) min", value: $work, in: 1...180)
                    Stepper("Rest · \(rest) min", value: $rest, in: 1...60)
                }
                .navigationTitle("Custom Intervals")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { custom = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            configure(work, rest)
                            custom = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { tick in
            let session = engine.session
            let working = session.phase == .work
            let seconds = session.remaining(at: tick.date)
            let total = Double((working ? session.work : session.rest) * 60)
            let accent = theme.color.opacity(working ? 1 : 0.48)
            ZStack {
                Circle().strokeBorder(accent.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: min(1, seconds / total))
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
                    .shadow(color: accent.opacity(working ? 0.55 : 0.15), radius: 8)
                VStack(spacing: 8) {
                    Label(session.phase.rawValue.uppercased(), systemImage: working ? "circle.fill" : "circle")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(accent)
                    Text(time(seconds))
                        .font(.system(size: 57, weight: .medium, design: .monospaced))
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                    if let title = session.habitTitle {
                        Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(25)
                .accessibilityElement(children: .combine)
            }
            .padding(9)
            .frame(maxWidth: 270)
            .aspectRatio(1, contentMode: .fit)
        }
    }

    private func time(_ seconds: Double) -> String {
        let rounded = Int(ceil(seconds))
        return String(format: "%02d:%02d", rounded / 60, rounded % 60)
    }

    private func preset(_ work: Int, _ rest: Int) -> some View {
        Button { configure(work, rest) } label: {
            Text("\(work) / \(rest)")
                .font(.system(.subheadline, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(work) minutes work, \(rest) minutes rest")
    }
}

struct SettingsView: View {
    let syncAvailable: Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var theme = Theme.violet
    @AppStorage("matchIcon") private var matchIcon = false
    @AppStorage("historyDays") private var historyDays = 14
    @AppStorage("autoTransition") private var autoTransition = false
    @AppStorage("keepAwake") private var keepAwake = false
    @AppStorage("chime", store: UserDefaults(suiteName: HabitStore.groupID)) private var chime = "Soft"
    @AppStorage("focusReminders", store: UserDefaults(suiteName: HabitStore.groupID)) private var reminders = false
    @AppStorage("haptics") private var haptics = "Soft"
    @State private var iconError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 16) {
                        ForEach(Theme.allCases) { color in
                            Button { theme = color } label: {
                                VStack(spacing: 4) {
                                    Circle().fill(color.color).frame(width: 32, height: 32)
                                        .overlay {
                                            if theme == color {
                                                Image(systemName: "checkmark").foregroundStyle(.black)
                                            }
                                        }
                                    Text(color.title).font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(theme == color ? .isSelected : [])
                        }
                    }.padding(.vertical, 8)
                    Toggle("Match Home Screen icon", isOn: $matchIcon)
                }
                Section("Habits") {
                    Picker("History", selection: $historyDays) {
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    if !syncAvailable {
                        Label("Stored on this device. iCloud sync is unavailable.",
                              systemImage: "icloud.slash")
                    }
                }
                Section("Focus") {
                    Toggle("Auto-start next interval", isOn: $autoTransition)
                    Toggle("Keep screen awake during focus", isOn: $keepAwake)
                    Toggle("Focus completion notifications", isOn: $reminders)
                    Picker("Chime", selection: $chime) {
                        ForEach(["Off", "Soft", "Bright"], id: \.self) { Text($0) }
                    }
                    Picker("Haptics", selection: $haptics) {
                        ForEach(["Off", "Soft", "Firm"], id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .onChange(of: reminders) {
                Task {
                    if reminders {
                        let center = UNUserNotificationCenter.current()
                        reminders = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
                    }
                    FocusEngine.shared.refreshReminder()
                }
            }
            .onChange(of: theme) { if matchIcon { updateIcon() } }
            .onChange(of: chime) { FocusEngine.shared.refreshReminder() }
            .onChange(of: matchIcon) { updateIcon() }
            .alert("Couldn’t update app icon",
                   isPresented: Binding(get: { iconError != nil }, set: { if !$0 { iconError = nil } })) {
                Button("OK") { iconError = nil }
            } message: { Text(iconError ?? "") }
        }
    }

    private func updateIcon() {
        let app = UIApplication.shared
        let desired = matchIcon ? theme.icon : nil
        guard app.supportsAlternateIcons, app.alternateIconName != desired else { return }
        Task {
            do { try await app.setAlternateIconName(desired) }
            catch { iconError = error.localizedDescription }
        }
    }
}
