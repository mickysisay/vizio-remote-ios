import SwiftUI

// Controls the V505-G9 remote has that the first build of the app lacked: the
// streaming-app row, the numeric keypad, typing, and CC / Info / PIC / Home.
//
// These live in an extension that takes the model as a parameter, because RemoteView's
// @EnvironmentObject is private to its own file and an extension elsewhere cannot see it.
extension RemoteView {

    /// YouTube, Netflix, Prime Video, Hulu, Disney+ and Peacock, in that order. An app
    /// appears once its numeric id is known: four were verified by reading /app/current
    /// while they ran, and the rest are learned the first time the set is seen running
    /// them (this firmware has no app catalogue to query).
    func appsSection(_ model: RemoteModel) -> some View {
        VStack(spacing: 8) {
            if !model.featuredApps.isEmpty {
                SectionLabel("Apps")
                LazyVGrid(columns: threeColumns, spacing: 8) {
                    ForEach(model.featuredApps) { app in
                        RemoteButton(title: app.display, height: 48) {
                            Task { await model.launch(app) }
                        }
                    }
                }
            }
        }
    }

    /// 1-9, then dash / 0 / enter - the same keypad the physical remote carries.
    /// Digits are ASCII in codeset 0 ("0" is 48 ... "9" is 57).
    func keypad(_ model: RemoteModel) -> some View {
        VStack(spacing: 8) {
            SectionLabel("Keypad")
            LazyVGrid(columns: threeColumns, spacing: 8) {
                ForEach(1...9, id: \.self) { n in
                    RemoteButton(title: String(n), height: 46) {
                        Task { await model.press("digit_\(n)") }
                    }
                }
                RemoteButton(title: "−", height: 46) { Task { await model.press("dash") } }
                RemoteButton(title: "0", height: 46) { Task { await model.press("digit_0") } }
                RemoteButton(title: "⏎", height: 46) { Task { await model.press("enter") } }
            }
        }
    }

    /// Type on the phone into the TV's focused text box.
    ///
    /// This is keystrokes, not a text API: the set has no text endpoint at all (every one
    /// tried answers 404), so each character goes out as an ASCII keypress in codeset 0.
    /// That only lands where the set has focus, so the TV's own on-screen keyboard has to
    /// be showing when you hit Send - which is what the hint says, and what Test checks.
    func typingSection(_ model: RemoteModel) -> some View {
        VStack(spacing: 8) {
            SectionLabel("Keyboard")
            Text("On the TV: open a search box so its keyboard is showing, then Send here.")
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("type here", text: Binding(
                get: { model.typed },
                set: { model.typed = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            LazyVGrid(columns: threeColumns, spacing: 8) {
                RemoteButton(title: "Send", tint: Theme.buttonAlt, height: 46) {
                    Task { await model.typeText() }
                }
                RemoteButton(title: "Test abc", height: 46) {
                    Task { await model.typeText("abc") }
                }
                RemoteButton(title: "⌫", height: 46) { Task { await model.backspace() } }
                RemoteButton(title: "⏎", height: 46) { Task { await model.press("enter") } }
                RemoteButton(title: "Paste-safe", height: 46) {
                    Task { await model.typeText("test") }
                }
                RemoteButton(title: "Clear box", height: 46) { model.typed = "" }
            }
        }
    }

    /// CC, Info, PIC (picture mode) and Home (the SmartCast launcher).
    func extraKeys(_ model: RemoteModel) -> some View {
        LazyVGrid(columns: fourColumns, spacing: 8) {
            RemoteButton(title: "CC", height: 52) { Task { await model.press("cc") } }
            RemoteButton(title: "Info", height: 52) { Task { await model.press("info") } }
            RemoteButton(title: "PIC", height: 52) { Task { await model.press("pic") } }
            RemoteButton(title: "Home", height: 52) { Task { await model.press("smartcast") } }
        }
    }

    private var threeColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
    }

    private var fourColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
    }
}
