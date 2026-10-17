import Foundation
import Combine

@MainActor
final class RemoteModel: ObservableObject {

    @Published private(set) var configured: Bool
    @Published private(set) var status: TVStatus?
    @Published private(set) var message: String = ""
    @Published private(set) var apps: [TVApp] = []
    @Published var volumeDraft: Double = 50

    // bound to the settings form
    @Published var host: String
    @Published var port: String
    @Published var token: String

    /// text to type into whatever field the TV has focused (a YouTube search box, say)
    @Published var typed: String = ""

    private let client = TVClient()
    private var poller: Task<Void, Never>?

    init() {
        // Work from locals until every stored property has a value: touching self
        // (even just reading self.host) is illegal until initialization completes.
        let defaults = UserDefaults.standard
        let storedHost = defaults.string(forKey: "host") ?? ""
        let storedPort = defaults.string(forKey: "port") ?? "7345"
        let storedToken = defaults.string(forKey: "token") ?? ""

        host = storedHost
        port = storedPort
        token = storedToken
        configured = !storedHost.isEmpty && !storedToken.isEmpty

        client.host = storedHost
        client.port = Int(storedPort) ?? 7345
        client.token = storedToken

        // Everything above is initialised by now, so the row can be built from what
        // previous runs learned about this set's app ids.
        refreshAppRow()
    }

    var base: String { "https://\(host):\(port)" }

    private func normalize() {
        var cleaned = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = cleaned.range(of: "://") { cleaned = String(cleaned[scheme.upperBound...]) }
        if let slash = cleaned.firstIndex(of: "/") { cleaned = String(cleaned[..<slash]) }
        host = cleaned
        port = port.trimmingCharacters(in: .whitespacesAndNewlines)
        if port.isEmpty { port = "7345" }
        token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func save() {
        normalize()
        guard !host.isEmpty, !token.isEmpty else {
            message = "Both the TV address and the token are required."
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(host, forKey: "host")
        defaults.set(port, forKey: "port")
        defaults.set(token, forKey: "token")
        client.host = host
        client.port = Int(port) ?? 7345
        client.token = token
        configured = true
        message = "Connecting to \(base) ..."
        Task { await refresh() }
    }

    func forget() {
        configured = false
        status = nil
        message = ""
    }

    func refresh() async {
        guard configured else { return }
        if let fresh = await client.status() {
            status = fresh
            if let volume = fresh.volume { volumeDraft = Double(volume) }
            message = ""
            // Learn the id of whatever is running, so its button appears from now on.
            await learnRunningApp()
        } else {
            status = nil
            // The most common cause on a first run is the Local Network permission
            // (Settings -> Privacy & Security -> Local Network) rather than a wrong
            // address, so name it instead of leaving the user guessing.
            message = "The TV did not answer. Allow Local Network for Vizio Remote in Settings, check the TV is awake, and that this phone is on the same Wi-Fi."
        }
    }

    func press(_ name: String) async {
        guard configured else { return }
        do {
            let accepted = try await client.press(name)
            message = accepted ? "" : "The TV did not accept \(name)."
        } catch {
            message = "Cannot reach the TV at \(base)."
        }
        await refresh()
    }

    func applyVolume(_ value: Double) async {
        guard configured else { return }
        _ = try? await client.setVolume(Int(value.rounded()))
        try? await Task.sleep(nanoseconds: 700_000_000)
        await refresh()
    }

    func chooseInput(_ name: String) async {
        guard configured else { return }
        _ = try? await client.setInput(name)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await refresh()
    }

    /// The buttons to show, in catalogue order: YouTube, Netflix, Prime Video, Hulu,
    /// Disney+, Peacock. An app only appears once its numeric id is known - built in for
    /// the ones verified on this set, learned at runtime for the rest (open it once and
    /// its button shows up from then on).
    var featuredApps: [TVApp] { apps }

    private func refreshAppRow() {
        let defaults = UserDefaults.standard
        apps = TVApps.catalogue.compactMap { known in
            let learned = defaults.string(forKey: "appid." + known.key)
            guard let appId = learned ?? known.appId else { return nil }
            let ns = defaults.object(forKey: "ns." + known.key) as? Int ?? known.nameSpace
            return TVApp(id: known.key, display: known.display, appId: appId, nameSpace: ns)
        }
    }

    /// Watch what the set is running; if it is one of the catalogue apps, remember its id.
    /// This firmware has no app catalogue to query, so this is how unknown ids are found.
    private func learnRunningApp() async {
        guard let running = await client.currentApp(), !running.message.isEmpty else { return }
        for known in TVApps.catalogue where known.matches(running.message) {
            let defaults = UserDefaults.standard
            if defaults.string(forKey: "appid." + known.key) != running.appId {
                defaults.set(running.appId, forKey: "appid." + known.key)
                defaults.set(running.nameSpace, forKey: "ns." + known.key)
                refreshAppRow()
            }
            return
        }
    }

    func launch(_ app: TVApp) async {
        guard configured else { return }
        do {
            let accepted = try await client.launch(app)
            // The set answers SUCCESS even for an id that does nothing, so confirm the
            // launch by reading back what it is actually running (APP_ID 1 is the home
            // screen). Two looks, because a tile can take a moment to take over.
            var opened = false
            for attempt in 0..<2 {
                try? await Task.sleep(nanoseconds: attempt == 0 ? 1_800_000_000 : 1_500_000_000)
                if let running = await client.currentApp(), running.appId != "1" {
                    opened = true
                    break
                }
            }
            message = accepted && opened ? "" : "The TV did not open \(app.display)."
        } catch {
            message = "Cannot reach the TV at \(base)."
        }
        await refresh()
    }

    /// Type the phone's text into the TV, one ASCII keypress per character. The TV's own
    /// on-screen keyboard has to be focused first (open YouTube's search, for instance),
    /// because these are keystrokes, not a text field on the set.
    func typeText() async {
        guard configured else { return }
        let characters = Array(typed)
        guard !characters.isEmpty else {
            message = "Type something first."
            return
        }
        var sent = 0
        for character in characters {
            // A newline in the field means Enter, not linefeed (10).
            let code = character == "\n" ? 13 : Int(character.asciiValue ?? 0)
            guard code > 0 else { continue }
            if (try? await client.pressASCII(code)) == true { sent += 1 }
            // Small gap: the set drops keys that arrive faster than it can handle them.
            try? await Task.sleep(nanoseconds: 45_000_000)
        }
        message = sent == 0 ? "Nothing sent." : "Typed \(sent) of \(characters.count) characters."
    }

    func backspace() async {
        guard configured else { return }
        _ = try? await client.press("backspace")
    }

    func startPolling() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    func stopPolling() {
        poller?.cancel()
        poller = nil
    }
}
