import Foundation

struct KeyDef {
    let codeset: Int
    let code: Int
}

/// Key codes from the Vizio SmartCast API docs, all verified on this V505-G9.
enum TVKeys {
    static let all: [String: KeyDef] = [
        "vol_up":       KeyDef(codeset: 5,  code: 1),
        "vol_down":     KeyDef(codeset: 5,  code: 0),
        "mute_toggle":  KeyDef(codeset: 5,  code: 4),
        "input_cycle":  KeyDef(codeset: 7,  code: 1),
        "ch_up":        KeyDef(codeset: 8,  code: 1),
        "ch_down":      KeyDef(codeset: 8,  code: 0),
        "power_off":    KeyDef(codeset: 11, code: 0),
        "power_on":     KeyDef(codeset: 11, code: 1),
        "power_toggle": KeyDef(codeset: 11, code: 2),
        "nav_up":       KeyDef(codeset: 3,  code: 8),
        "nav_down":     KeyDef(codeset: 3,  code: 0),
        "nav_left":     KeyDef(codeset: 3,  code: 1),
        "nav_right":    KeyDef(codeset: 3,  code: 7),
        "nav_ok":       KeyDef(codeset: 3,  code: 2),
        "nav_back":     KeyDef(codeset: 4,  code: 0),
        "nav_exit":     KeyDef(codeset: 9,  code: 0),
        "menu":         KeyDef(codeset: 4,  code: 8),
        "info":         KeyDef(codeset: 4,  code: 6),
        "smartcast":    KeyDef(codeset: 4,  code: 3),
        "seek_fwd":     KeyDef(codeset: 2,  code: 0),
        "seek_back":    KeyDef(codeset: 2,  code: 1),
        "play":         KeyDef(codeset: 2,  code: 3),
        "pause":        KeyDef(codeset: 2,  code: 2),
        "cc":           KeyDef(codeset: 4,  code: 4)
    ]
}

struct TVInput: Identifiable, Hashable {
    let id: String        // the NAME the API expects, e.g. "HDMI-2"
    let display: String   // the label the TV reports, e.g. "Fire TV Stick"
}

struct TVStatus {
    var volume: Int?
    var mute: String?
    var currentInput: String?
    var inputs: [TVInput] = []
}

/// Talks to the Vizio SmartCast API on port 7345.
///
/// The TV presents a certificate issued by Vizio's internal CA: the chain is never sent,
/// the leaf is not a CA, it has no subjectAltName, and iOS cannot be told to trust it.
/// A web page added to the Home Screen therefore cannot reach the TV at all. This client
/// accepts the TV's own certificate for that connection - the same thing Vizio's own app
/// does - which is why a native app works where a web app cannot.
final class TVClient: NSObject, URLSessionDelegate {

    var host: String = ""
    var port: Int = 7345
    var token: String = ""

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Only ever accept a certificate for the exact TV address the user configured -
        // never for anything else, even though we can't validate Vizio's chain at all.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust,
           challenge.protectionSpace.host == host {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private func call(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let url = URL(string: "https://\(host):\(port)\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "AUTH")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await session.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func entries(_ reply: [String: Any]) -> [[String: Any]] {
        (reply["ITEMS"] as? [[String: Any]]) ?? []
    }

    private func succeeded(_ reply: [String: Any]) -> Bool {
        guard let status = reply["STATUS"] as? [String: Any],
              let result = status["RESULT"] as? String else { return false }
        return result.uppercased() == "SUCCESS"
    }

    @discardableResult
    func press(_ name: String) async throws -> Bool {
        guard let key = TVKeys.all[name] else { return false }
        let reply = try await call("PUT", "/key_command/", [
            "KEYLIST": [["CODESET": key.codeset, "CODE": key.code, "ACTION": "KEYPRESS"]]
        ])
        return succeeded(reply)
    }

    /// nil means "the TV did not answer" (asleep, wrong address, or a different Wi-Fi).
    func status() async -> TVStatus? {
        var result = TVStatus()
        do {
            let power = try await call("GET", "/state/device/power_mode")
            guard succeeded(power) else { return nil }

            let audio = try await call("GET", "/menu_native/dynamic/tv_settings/audio")
            for item in entries(audio) {
                switch item["CNAME"] as? String {
                case "volume": result.volume = item["VALUE"] as? Int
                case "mute":   result.mute = item["VALUE"] as? String
                default:       break
                }
            }

            let current = try await call("GET", "/menu_native/dynamic/tv_settings/devices/current_input")
            result.currentInput = entries(current).first?["VALUE"] as? String

            let names = try await call("GET", "/menu_native/dynamic/tv_settings/devices/name_input")
            result.inputs = entries(names).compactMap { item in
                guard let name = item["NAME"] as? String else { return nil }
                let label = (item["VALUE"] as? [String: Any])?["NAME"] as? String ?? name
                return TVInput(id: name, display: label)
            }
            return result
        } catch {
            return nil
        }
    }

    @discardableResult
    func setVolume(_ value: Int) async throws -> Bool {
        let audio = try await call("GET", "/menu_native/dynamic/tv_settings/audio")
        guard let entry = entries(audio).first(where: { ($0["CNAME"] as? String) == "volume" }) else { return false }
        let hashval: Any = entry["HASHVAL"] ?? 0
        let reply = try await call("PUT", "/menu_native/dynamic/tv_settings/audio/volume", [
            "REQUEST": "MODIFY", "HASHVAL": hashval, "VALUE": value
        ])
        return succeeded(reply)
    }

    @discardableResult
    func setInput(_ name: String) async throws -> Bool {
        let current = try await call("GET", "/menu_native/dynamic/tv_settings/devices/current_input")
        let hashval: Any = entries(current).first?["HASHVAL"] ?? 0
        let reply = try await call("PUT", "/menu_native/dynamic/tv_settings/devices/current_input", [
            "REQUEST": "MODIFY", "VALUE": name, "HASHVAL": hashval
        ])
        return succeeded(reply)
    }
}
