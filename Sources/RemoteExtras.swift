import SwiftUI

// Controls the V505-G9 remote has that the first build of the app lacked: the
// streaming-app row, the numeric keypad, and CC / Info / PIC / Home.
//
// These live in an extension that takes the model as a parameter, because RemoteView's
// @EnvironmentObject is private to its own file and an extension elsewhere cannot see it.
extension RemoteView {

    /// YouTube, Netflix, Prime Video, Hulu, Disney+ and Peacock, in that order.
    /// Only apps the set reports are shown: the list is GET /app_list on the TV itself,
    /// so no launch name is guessed here.
    func appsSection(_ model: RemoteModel) -> some View {
        VStack(spacing: 8) {
            if !model.featuredApps.isEmpty {
                SectionLabel("Apps")
                LazyVGrid(columns: threeColumns, spacing: 8) {
                    ForEach(model.featuredApps) { app in
                        RemoteButton(title: app.display, height: 48) {
                            Task { await model.launchApp(app.id) }
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
