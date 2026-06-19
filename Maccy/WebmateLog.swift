import Foundation

/// Dependency-free WebmateLog helper for Swift/iOS.
///
/// Endpoint notes:
/// - iOS simulator -> Mac collector: http://127.0.0.1:8765/api/logs usually works.
/// - Physical device -> Mac collector: use the Mac's LAN IP, e.g. http://192.168.x.x:8765/api/logs.
/// - Tailscale -> use the Tailscale IP/hostname, e.g. http://100.x.y.z:8765/api/logs.
public enum WebmateLog {
    public static var endpoint = URL(string: "http://127.0.0.1:8765/api/logs")!

    @discardableResult
    public static func send(
        namespace: String,
        scenario: String,
        level: String = "info",
        message: String,
        context: [String: Any]? = nil,
        requestId: String? = nil,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        endpoint endpointOverride: URL? = nil,
        timeout: TimeInterval = 1.2,
        session: URLSession = .shared
    ) -> Bool {
        let namespace = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        let scenario = scenario.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = endpointOverride ?? endpoint

        guard !namespace.isEmpty, !scenario.isEmpty, !message.isEmpty else { return false }

        var payload: [String: Any] = [
            "namespace": namespace,
            "scenario": scenario,
            "level": level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "message": message,
            "context": context ?? [:],
            "timestamp": timestamp
        ]
        payload["request_id"] = requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? NSNull()

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return false
        }

        var request = URLRequest(url: target, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data

        session.dataTask(with: request) { _, _, _ in
            // Logging must never break the host app.
        }.resume()

        return true
    }
}
