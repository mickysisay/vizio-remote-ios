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
            // The app row is whatever the set reports, fetched once the TV answers.
            if apps.isEmpty { apps = await client.apps() }
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

    /// The six apps worth a dedicated button, in this order. Only apps the TV actually
    /// lists are returned, so a set without Peacock simply shows a shorter row.
    var featuredApps: [TVApp] {
        let wanted = ["YouTube", "Netflix", "Prime", "Hulu", "Disney", "Peacock"]
        var out: [TVApp] = []
        for want in wanted {
            if let hit = apps.first(where: { $0.display.range(of: want, options: .caseInsensitive) != nil }),
               !out.contains(hit) {
                out.append(hit)
            }
        }
        return out
    }

    func launchApp(_ name: String) async {
        guard configured else { return }
        do {
            let accepted = try await client.launchApp(name)
            message = accepted ? "" : "The TV did not launch \(name)."
        } catch {
            message = "Cannot reach the TV at \(base)."
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await refresh()
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
