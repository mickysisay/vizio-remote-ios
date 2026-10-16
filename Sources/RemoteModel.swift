import Foundation
import Combine

@MainActor
final class RemoteModel: ObservableObject {

    @Published private(set) var configured: Bool
    @Published private(set) var status: TVStatus?
    @Published private(set) var message: String = ""
    @Published private(set) var working = false
    @Published var volumeDraft: Double = 50

    // bound to the settings form
    @Published var host: String
    @Published var port: String
    @Published var token: String

    private let client = TVClient()
    private var poller: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        host = defaults.string(forKey: "host") ?? ""
        port = defaults.string(forKey: "port") ?? "7345"
        token = defaults.string(forKey: "token") ?? ""
        configured = !host.isEmpty && !token.isEmpty
        client.host = host
        client.port = Int(port) ?? 7345
        client.token = token
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

    func signOut() {
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
        } else {
            status = nil
            message = "The TV did not answer. Awake? On the same Wi-Fi?"
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
