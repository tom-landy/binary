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
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Focus").label()
                    Spacer()
                    if showsSettings {
                        CircleIconButton(systemImage: "gearshape", label: "Settings", action: openSettings)
                    }
                }
                .frame(height: 44)
                Text(session.habitTitle ?? "Focus session")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 2)

                phaseSwitch(session)
                    .padding(.top, 22)

                TimelineView(.periodic(from: .now, by: 0.25)) { tick in
                    readout(session, at: tick.date)
                }

                controls(session)
                    .padding(.top, 30)

                Text("Intervals").label()
                    .padding(.top, 30)
                intervals(session)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .sheet(isPresented: $custom) { customSheet }
    }

    // MARK: Phase

    /// Work is 1, Rest is 0. Tapping the inactive side skips to it.
    private func phaseSwitch(_ session: FocusSession) -> some View {
        HStack(spacing: 0) {
            phaseSegment("1 Work", active: session.phase == .work)
            phaseSegment("0 Rest", active: session.phase == .rest)
        }
        .padding(3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .frame(width: 184)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.phase.rawValue) interval")
        .accessibilityHint("Double tap to switch")
        .accessibilityAction { skip() }
    }

    private func phaseSegment(_ title: String, active: Bool) -> some View {
        Button { if !active { skip() } } label: {
            Text(title)
                .font(.system(size: 12, weight: active ? .bold : .semibold, design: .monospaced))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(active ? Theme.ink : Theme.tertiary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(active ? theme.color : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Readout

    private func readout(_ session: FocusSession, at date: Date) -> some View {
        let working = session.phase == .work
        let minutes = working ? session.work : session.rest
        let total = Double(minutes * 60)
        let remaining = session.remaining(at: date)
        let next = working ? "then \(session.rest) min rest" : "then \(session.work) min work"
        return VStack(alignment: .leading, spacing: 0) {
            Text(clock(remaining))
                .font(.system(size: 92, weight: .light, design: .monospaced))
                .tracking(-4)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(countsDown: true))
                .padding(.top, 26)
            Text("of \(minutes) min · \(next)")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 8)
            MinuteGrid(total: total, remaining: remaining,
                       color: working ? theme.color : theme.color.opacity(0.5))
                .padding(.top, 26)
        }
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
        let full = Double((session.phase == .work ? session.work : session.rest) * 60)
        let title = running ? "Pause" : (session.seconds < full ? "Resume" : "Start")
        return HStack(spacing: 10) {
            squareButton("Reset", systemImage: "arrow.counterclockwise", action: reset)
            PrimaryButton(title: title, systemImage: running ? "pause.fill" : "play.fill",
                          theme: theme, action: play)
            squareButton("Skip interval", systemImage: "forward.end.fill", action: skip)
        }
    }

    private func squareButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 56, height: 56)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
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
                intervalChip("\(preset.0)/\(preset.1)", mono: true,
                             selected: free && session.work == preset.0 && session.rest == preset.1) {
                    configure(preset.0, preset.1)
                }
                .accessibilityLabel("\(preset.0) minutes work, \(preset.1) minutes rest")
            }
            intervalChip("Custom", mono: false, selected: free && !isPreset) {
                work = session.work
                rest = session.rest
                custom = true
            }
        }
    }

    private func intervalChip(_ title: String, mono: Bool, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .bold : .regular, design: mono ? .monospaced : .default))
                .foregroundStyle(selected ? Theme.ink : Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(selected ? theme.color : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? .clear : Theme.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Custom intervals")
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 28)
            Text("Work").label().padding(.top, 24)
            Stepper("\(work) min", value: $work, in: 1...180).font(.system(size: 17, design: .monospaced))
                .padding(.top, 8)
            Text("Rest").label().padding(.top, 20)
            Stepper("\(rest) min", value: $rest, in: 1...60).font(.system(size: 17, design: .monospaced))
                .padding(.top, 8)
            Spacer()
            PrimaryButton(title: "Use \(work)/\(rest)", theme: theme) {
                configure(work, rest)
                custom = false
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .foregroundStyle(Theme.text)
        .tint(theme.color)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
    }
}

/// One cell per minute (or per five minutes for long intervals). Remaining time is lit;
/// elapsed cells go dark, and the current cell drains from the top.
struct MinuteGrid: View {
    let total: Double
    let remaining: Double
    let color: Color

    var body: some View {
        let unit: Double = total > 3600 ? 300 : 60
        let count = max(1, Int(ceil(total / unit)))
        let elapsed = total - remaining
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                let start = Double(index) * unit
                let left = min(1, max(0, (start + unit - elapsed) / unit))
                RoundedRectangle(cornerRadius: 6)
                    .fill(left >= 1 ? color : (left <= 0 ? Theme.surface : color.opacity(0.25)))
                    .overlay(alignment: .bottom) {
                        if left > 0 && left < 1 {
                            GeometryReader { proxy in
                                Rectangle().fill(color)
                                    .frame(height: proxy.size.height * left)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Settings

struct SettingsView: View {
    let syncAvailable: Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Theme.key, store: Theme.defaults) private var theme = Theme.violet
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
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 16) {
                        ForEach(Theme.allCases) { color in
                            Button { theme = color } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(color.color)
                                        .frame(width: 34, height: 34)
                                        .overlay {
                                            if theme == color {
                                                Text("1").font(.system(size: 16, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(Theme.ink)
                                            }
                                        }
                                    Text(color.title).font(.caption)
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
                } header: {
                    Text("Accent").label()
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Auto-start next interval", isOn: $autoTransition)
                    Toggle("Keep screen awake", isOn: $keepAwake)
                    Toggle("Notify when an interval ends", isOn: $reminders)
                    Picker("Chime", selection: $chime) {
                        ForEach(["Off", "Soft", "Bright"], id: \.self) { Text($0) }
                    }
                    Picker("Haptics", selection: $haptics) {
                        ForEach(["Off", "Soft", "Firm"], id: \.self) { Text($0) }
                    }
                } header: {
                    Text("Focus").label()
                }
                .listRowBackground(Theme.surface)

                Section {
                    Label(syncAvailable ? "Syncing with iCloud" : "Stored on this device. iCloud sync is unavailable.",
                          systemImage: syncAvailable ? "icloud" : "icloud.slash")
                        .foregroundStyle(syncAvailable ? Theme.text : Theme.secondary)
                } header: {
                    Text("Data").label()
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.fontWeight(.semibold) }
            .toolbarBackground(Theme.background, for: .navigationBar)
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
