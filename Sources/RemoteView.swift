import SwiftUI

struct RemoteView: View {
    @EnvironmentObject private var model: RemoteModel
    @Binding var showingSettings: Bool

    // Explicit: the private @EnvironmentObject would otherwise make the memberwise
    // initializer private, and ContentView (another file) could not call it.
    init(showingSettings: Binding<Bool>) {
        self._showingSettings = showingSettings
    }

    private let dpadColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                statusLine
                appsSection(model)

                HStack(spacing: 10) {
                    RemoteButton(title: "Power", subtitle: "toggle", tint: Theme.danger, height: 78) {
                        Task { await model.press("power_toggle") }
                    }
                    RemoteButton(title: "On", subtitle: "only if awake", height: 78) {
                        Task { await model.press("power_on") }
                    }
                }

                HStack(spacing: 10) {
                    RemoteButton(title: "Vol −", height: 70) { Task { await model.press("vol_down") } }
                    RemoteButton(title: "Vol +", height: 70) { Task { await model.press("vol_up") } }
                }

                HStack(spacing: 10) {
                    RemoteButton(title: "Mute", subtitle: "toggle", height: 64) { Task { await model.press("mute_toggle") } }
                    RemoteButton(title: "Input", subtitle: "cycle", height: 64) { Task { await model.press("input_cycle") } }
                }

                volumeSection

                SectionLabel("Navigate")
                dpad

                HStack(spacing: 10) {
                    RemoteButton(title: "Back") { Task { await model.press("nav_back") } }
                    RemoteButton(title: "Menu") { Task { await model.press("menu") } }
                    RemoteButton(title: "Exit") { Task { await model.press("nav_exit") } }
                }

                HStack(spacing: 10) {
                    RemoteButton(title: "⏮") { Task { await model.press("seek_back") } }
                    RemoteButton(title: "Play") { Task { await model.press("play") } }
                    RemoteButton(title: "Pause") { Task { await model.press("pause") } }
                    RemoteButton(title: "⏭") { Task { await model.press("seek_fwd") } }
                }

                extraKeys(model)

                keypad(model)

                SectionLabel("Channel")
                HStack(spacing: 10) {
                    RemoteButton(title: "CH −") { Task { await model.press("ch_down") } }
                    RemoteButton(title: "CH +") { Task { await model.press("ch_up") } }
                }

                if let inputs = model.status?.inputs, !inputs.isEmpty {
                    SectionLabel("Inputs")
                    inputList(inputs)
                }

                SectionLabel("Power")
                RemoteButton(title: "Power Off") { Task { await model.press("power_off") } }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 34)
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Vizio Remote")
                .font(.system(size: 19, weight: .semibold))
            Spacer()
            Button("Settings") { showingSettings = true }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.buttonAlt)
                .foregroundColor(Theme.text)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var statusLine: some View {
        Text(statusText)
            .font(.system(size: 13))
            .foregroundColor(model.status == nil ? Theme.muted : Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        if let status = model.status {
            let volume = status.volume.map(String.init) ?? "?"
            return "Input \(status.currentInput ?? "?") · Vol \(volume) · Mute \(status.mute ?? "?")"
        }
        return model.message.isEmpty ? "Connecting ..." : model.message
    }

    private var volumeSection: some View {
        VStack(spacing: 2) {
            SectionLabel("Volume \(model.status?.volume.map { "= \($0)" } ?? "")")
            Slider(value: $model.volumeDraft, in: 0...100, step: 1) { editing in
                if !editing {
                    Task { await model.applyVolume(model.volumeDraft) }
                }
            }
        }
    }

    private var dpad: some View {
        LazyVGrid(columns: dpadColumns, spacing: 8) {
            Color.clear.frame(height: 54)
            RemoteButton(title: "▲", height: 54) { Task { await model.press("nav_up") } }
            Color.clear.frame(height: 54)
            RemoteButton(title: "◀", height: 54) { Task { await model.press("nav_left") } }
            RemoteButton(title: "OK", tint: Theme.buttonAlt, height: 54) { Task { await model.press("nav_ok") } }
            RemoteButton(title: "▶", height: 54) { Task { await model.press("nav_right") } }
            Color.clear.frame(height: 54)
            RemoteButton(title: "▼", height: 54) { Task { await model.press("nav_down") } }
            Color.clear.frame(height: 54)
        }
    }

    private func inputList(_ inputs: [TVInput]) -> some View {
        VStack(spacing: 10) {
            ForEach(inputs) { input in
                Button {
                    Task { await model.chooseInput(input.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(input.id).font(.system(size: 16, weight: .semibold))
                        Text(input.display).font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.buttonAlt)
                    .foregroundColor(Theme.text)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RemoteButton: View {
    let title: String
    var subtitle: String? = nil
    var tint: Color? = nil
    var height: CGFloat = 58
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold))
                if let subtitle = subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundColor(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.vertical, 6)
            .background(tint ?? Theme.button)
            .foregroundColor(Theme.text)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SectionLabel: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(1.1)
            .foregroundColor(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
    }
}
