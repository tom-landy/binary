import SwiftUI
import UIKit
import UserNotifications

struct FocusView: View {
    let engine: FocusEngine
    let theme: Theme
    let showsSettings: Bool
    let openSettings: () -> Void
    let play: () -> Void
    let reset: () -> Void
    let skip: () -> Void
    let configure: (Int, Int) -> Void
    @State private var custom = false
    @State private var work = 25
    @State private var rest = 5

    static let presets = [(25, 5), (50, 10), (15, 3)]

    var body: some View {
        let session = engine.session
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Color.clear.frame(width: 44, height: 44)
                    Spacer()
                    Text(session.habitTitle == nil ? "Focus" : "Focusing on")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    if showsSettings {
                        CircleIconButton(systemImage: "gearshape", label: "Settings", action: openSettings)
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
                Text(session.habitTitle ?? "Free session")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)

                phaseControl(session)
                    .padding(.top, 16)

                TimelineView(.periodic(from: .now, by: 0.25)) { tick in
                    dial(session, at: tick.date)
                }
                .padding(.top, 28)

                controls(session)
                    .padding(.top, 32)

                intervals(session)
                    .padding(.top, 30)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .sheet(isPresented: $custom) { customSheet }
    }

    // MARK: Phase

    /// Work / Rest segmented control. Tapping the other side skips to it.
    private func phaseControl(_ session: FocusSession) -> some View {
        HStack(spacing: 0) {
            phaseSegment("Work", active: session.phase == .work)
            phaseSegment("Rest", active: session.phase == .rest)
        }
        .padding(4)
        .background(Theme.track, in: RoundedRectangle(cornerRadius: 14))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.phase.rawValue) interval")
        .accessibilityHint("Double tap to switch")
        .accessibilityAction { skip() }
    }

    private func phaseSegment(_ title: String, active: Bool) -> some View {
        Button { if !active { skip() } } label: {
            Text(title)
                .font(.system(size: 14, weight: active ? .heavy : .bold))
                .foregroundStyle(active ? Theme.text : Theme.secondary)
                .padding(.horizontal, 20)
                .frame(height: 32)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 11).fill(Theme.surface).paperShadow()
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Dial

    private func dial(_ session: FocusSession, at date: Date) -> some View {
        let working = session.phase == .work
        let minutes = working ? session.work : session.rest
        let total = Double(minutes * 60)
        let remaining = session.remaining(at: date)
        let next = working ? "then \(session.rest) rest" : "then \(session.work) work"
        return ZStack {
            Circle().fill(Theme.surface).paperShadow()
            ProgressRing(value: remaining / max(total, 1),
                         color: working ? theme.color : theme.color.opacity(0.45),
                         lineWidth: 12) {
                VStack(spacing: 4) {
                    Text(clock(remaining))
                        .font(.system(size: 66, weight: .black))
                        .monospacedDigit()
                        .tracking(-1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(Theme.text)
                    Text("of \(minutes) min · \(next)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(30)
            }
        }
        .frame(maxWidth: 290)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.phase.rawValue), \(clock(remaining)) remaining of \(minutes) minutes")
    }

    private func clock(_ seconds: Double) -> String {
        let rounded = Int(ceil(seconds))
        return String(format: "%02d:%02d", rounded / 60, rounded % 60)
    }

    // MARK: Controls

    private func controls(_ session: FocusSession) -> some View {
        let running = session.end != nil
        let full = Double(session.total)
        let label = running ? "Pause" : (session.seconds < full ? "Resume" : "Start")
        return HStack(spacing: 22) {
            roundButton("Reset", systemImage: "arrow.counterclockwise", action: reset)
            Button(action: play) {
                Image(systemName: running ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.onInk)
                    .frame(width: 84, height: 84)
                    .background(Theme.ink, in: Circle())
                    .shadow(color: Theme.shadow, radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            roundButton("Skip interval", systemImage: "forward.end.fill", action: skip)
        }
    }

    private func roundButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 58, height: 58)
                .background(Theme.surface, in: Circle())
                .paperShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: Intervals

    private func intervals(_ session: FocusSession) -> some View {
        let free = session.habitID == nil
        let isPreset = Self.presets.contains { $0 == (session.work, session.rest) }
        return HStack(spacing: 8) {
            ForEach(Self.presets.indices, id: \.self) { index in
                let preset = Self.presets[index]
                intervalChip("\(preset.0) / \(preset.1)",
                             selected: free && session.work == preset.0 && session.rest == preset.1) {
                    configure(preset.0, preset.1)
                }
                .accessibilityLabel("\(preset.0) minutes work, \(preset.1) minutes rest")
            }
            intervalChip("Custom", selected: free && !isPreset) {
                work = session.work
                rest = session.rest
                custom = true
            }
        }
    }

    private func intervalChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(selected ? Theme.onInk : Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(selected ? Theme.ink : Theme.surface, in: Capsule())
                .paperShadow()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Custom intervals")
                .font(.system(size: 22, weight: .black))
                .padding(.top, 28)
            Text("Work").label().padding(.top, 22)
            Stepper("\(work) min", value: $work, in: 1...180)
                .font(.system(size: 17, weight: .bold))
                .padding(.top, 8)
            Text("Rest").label().padding(.top, 18)
            Stepper("\(rest) min", value: $rest, in: 1...60)
                .font(.system(size: 17, weight: .bold))
                .padding(.top, 8)
            Spacer()
            PrimaryButton(title: "Use \(work) / \(rest)") {
                configure(work, rest)
                custom = false
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .foregroundStyle(Theme.text)
        .fontDesign(.rounded)
        .tint(theme.color)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }
}

// MARK: - Settings

struct SettingsView: View {
    let syncAvailable: Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Theme.key, store: Theme.defaults) private var theme = Theme.violet
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("matchIcon") private var matchIcon = false
    @AppStorage("autoTransition") private var autoTransition = false
    @AppStorage("keepAwake") private var keepAwake = false
    @AppStorage("chime", store: UserDefaults(suiteName: HabitStore.groupID)) private var chime = "Soft"
    @AppStorage("focusReminders", store: UserDefaults(suiteName: HabitStore.groupID)) private var reminders = false
    @AppStorage("haptics") private var haptics = "Soft"
    @State private var iconError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Look") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 16) {
                        ForEach(Theme.allCases) { color in
                            Button { theme = color } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 34, height: 34)
                                        .overlay {
                                            if theme == color {
                                                Text("1").font(.system(size: 15, weight: .heavy))
                                                    .foregroundStyle(color.onColor)
                                            }
                                        }
                                    Text(color.title).font(.caption.weight(.semibold))
                                        .foregroundStyle(theme == color ? Theme.text : Theme.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.title)
                            .accessibilityAddTraits(theme == color ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                    Toggle("Match Home Screen icon", isOn: $matchIcon)
                }
                .listRowBackground(Theme.surface)

                Section("Focus") {
                    Toggle("Auto-start next interval", isOn: $autoTransition)
                    Toggle("Keep screen awake", isOn: $keepAwake)
                    Toggle("Notify when an interval ends", isOn: $reminders)
                    Picker("Chime", selection: $chime) {
                        ForEach(["Off", "Soft", "Bright"], id: \.self) { Text($0) }
                    }
                    Picker("Haptics", selection: $haptics) {
                        ForEach(["Off", "Soft", "Firm"], id: \.self) { Text($0) }
                    }
                }
                .listRowBackground(Theme.surface)

                Section("Data") {
                    Label(syncAvailable ? "Syncing with iCloud" : "Stored on this device. iCloud sync is unavailable.",
                          systemImage: syncAvailable ? "icloud" : "icloud.slash")
                        .foregroundStyle(syncAvailable ? Theme.text : Theme.secondary)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.fontWeight(.bold) }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .fontDesign(.rounded)
            .tint(theme.color)
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
        .presentationBackground(Theme.background)
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
