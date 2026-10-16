import SwiftUI

@main
struct VizioRemoteApp: App {
    @StateObject private var model = RemoteModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}

enum Theme {
    static let background = Color(red: 0.043, green: 0.059, blue: 0.078)
    static let button     = Color(red: 0.133, green: 0.173, blue: 0.220)
    static let buttonAlt  = Color(red: 0.173, green: 0.227, blue: 0.290)
    static let danger     = Color(red: 0.863, green: 0.149, blue: 0.149)
    static let text       = Color(red: 0.910, green: 0.933, blue: 0.965)
    static let muted      = Color(red: 0.545, green: 0.608, blue: 0.690)
}

struct ContentView: View {
    @EnvironmentObject private var model: RemoteModel
    @State private var showingSettings = false

    var body: some View {
        Group {
            if model.configured {
                RemoteView(showingSettings: $showingSettings)
            } else {
                SettingsView(isFirstRun: true)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    var isFirstRun: Bool = false
    @EnvironmentObject private var model: RemoteModel
    @Environment(\\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect to your TV")
                    .font(.system(size: 19, weight: .semibold))
                    .padding(.bottom, 6)

                Text("TV address").font(.footnote).foregroundColor(Theme.muted)
                TextField("192.168.10.128", text: $model.host)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                Text("Port").font(.footnote).foregroundColor(Theme.muted).padding(.top, 6)
                TextField("7345", text: $model.port)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                Text("AUTH token").font(.footnote).foregroundColor(Theme.muted).padding(.top, 6)
                TextField("from the pairing step", text: $model.token)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button("Save & test") { model.save() }
                        .buttonStyle(PrimaryButtonStyle())
                    if !isFirstRun {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(Theme.muted)
                    }
                }
                .padding(.top, 14)

                if !model.message.isEmpty {
                    Text(model.message)
                        .font(.footnote)
                        .foregroundColor(Theme.muted)
                        .padding(.top, 10)
                }

                Text("This app accepts the TV's own certificate. Vizio's sets hand out a certificate iOS can't validate - no chain, no subjectAltName - which is exactly why the web version only works inside Safari and never from the Home Screen. Same Wi-Fi as the TV required.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
                    .padding(.top, 14)
            }
            .padding(18)
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundColor(Theme.text)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(Theme.buttonAlt.opacity(configuration.isPressed ? 0.6 : 1))
            .foregroundColor(Theme.text)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
