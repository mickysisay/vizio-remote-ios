import Foundation

struct KeyDef {
    let codeset: Int
    let code: Int
}

/// Key codes from the Vizio SmartCast API docs, verified on this V505-G9 where noted.
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
        "cc":           KeyDef(codeset: 4,  code: 4),

        // Keypad. Digits and punctuation are plain ASCII in codeset 0, per the SmartCast
        // API table: "0".."9" are 48..57, "-" is 45, "." is 46 and Return is 13.
        "digit_0":      KeyDef(codeset: 0,  code: 48),
        "digit_1":      KeyDef(codeset: 0,  code: 49),
        "digit_2":      KeyDef(codeset: 0,  code: 50),
        "digit_3":      KeyDef(codeset: 0,  code: 51),
        "digit_4":      KeyDef(codeset: 0,  code: 52),
        "digit_5":      KeyDef(codeset: 0,  code: 53),
        "digit_6":      KeyDef(codeset: 0,  code: 54),
        "digit_7":      KeyDef(codeset: 0,  code: 55),
        "digit_8":      KeyDef(codeset: 0,  code: 56),
        "digit_9":      KeyDef(codeset: 0,  code: 57),
        "dash":         KeyDef(codeset: 0,  code: 45),
        "dot":          KeyDef(codeset: 0,  code: 46),
        "enter":        KeyDef(codeset: 0,  code: 13),

        // Video (codeset 6): the remote's PIC key cycles the picture mode; wide cycles aspect.
        "pic":          KeyDef(codeset: 6,  code: 0),
        "wide":         KeyDef(codeset: 6,  code: 2)
    ]
}

struct TVInput: Identifiable, Hashable {
    let id: String        // the NAME the API expects, e.g. "HDMI-2"
    let display: String   // the label the TV reports, e.g. "Fire TV Stick"
}

struct TVApp: Identifiable, Hashable {
    let id: String        // stable key, e.g. "netflix"
    let display: String   // button label
    let appId: String     // the numeric APP_ID this set uses (learned, see TVApps)
    let nameSpace: Int
}

/// How this firmware addresses apps, established empirically on a V505-G9 (firmware 4.x):
///
///  - `GET /app_list` does not exist (404), so there is no catalogue to enumerate.
///  - `PUT /app/launch` wants an object: {"REQUEST":"LAUNCH","VALUE":{"APP_ID":..,"NAME_SPACE":..}}.
///    A string VALUE crashes its handler (500), and an unknown APP_ID returns SUCCESS while
///    doing nothing - so the status code alone is not proof of a launch.
///  - `GET /app/current` returns the running app, and its MESSAGE url identifies it, e.g.
///    Hulu -> hulu.com, Prime -> atv-ext.amazon.com, Disney+ -> bamgrid.com, Peacock ->
///    peacocktv.com. That is what makes it possible to learn an id instead of guessing one.
enum TVApps {

    struct Known {
        let key: String
        let display: String
        let needles: [String]     // substrings of the running app's MESSAGE url
        let appId: String?        // verified here; nil means "learn it, then this button appears"
        let nameSpace: Int

        func matches(_ message: String) -> Bool {
            needles.contains { message.range(of: $0, options: .caseInsensitive) != nil }
        }
    }

    static let catalogue: [Known] = [
        Known(key: "youtube", display: "YouTube",
              needles: ["youtube"], appId: nil, nameSpace: 4),
        Known(key: "netflix", display: "Netflix",
              needles: ["netflix"], appId: nil, nameSpace: 4),
        Known(key: "prime", display: "Prime Video",
              needles: ["atv-ext.amazon", "amazon.com/blast"], appId: "4", nameSpace: 4),
        Known(key: "hulu", display: "Hulu",
              needles: ["hulu.com"], appId: "3", nameSpace: 4),
        Known(key: "disney", display: "Disney+",
              needles: ["bamgrid", "disney"], appId: "75", nameSpace: 4),
        Known(key: "peacock", display: "Peacock",
              needles: ["peacocktv"], appId: "88", nameSpace: 4)
    ]
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

    /// The app the set is running right now (nil when it does not answer).
    /// The MESSAGE url is the only identity this firmware exposes for an app.
    func currentApp() async -> (appId: String, nameSpace: Int, message: String)? {
        do {
            let reply = try await call("GET", "/app/current")
            guard let item = reply["ITEM"] as? [String: Any],
                  let value = item["VALUE"] as? [String: Any],
                  let appId = value["APP_ID"] as? String ?? (value["APP_ID"] as? Int).map(String.init)
            else { return nil }
            let nameSpace = (value["NAME_SPACE"] as? Int) ?? 4
            return (appId, nameSpace, (value["MESSAGE"] as? String) ?? "")
        } catch {
            return nil
        }
    }

    /// Launch by numeric id. The TV answers SUCCESS even for an id that does not exist,
    /// so callers must confirm with currentApp() rather than trust this return value.
    @discardableResult
    func launch(_ app: TVApp) async throws -> Bool {
        let reply = try await call("PUT", "/app/launch", [
            "REQUEST": "LAUNCH",
            "VALUE": ["APP_ID": app.appId, "NAME_SPACE": app.nameSpace]
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
