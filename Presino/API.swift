import Foundation

struct APIResult {
    let status: Int
    let json: [String: Any]
}

enum API {
    /// فراخوانی api_mobile با توکن؛ در قطعی شبکه nil برمی‌گرداند.
    static func call(_ path: String, method: String = "GET", body: [String: Any]? = nil) async -> APIResult? {
        if Demo.on { return nil }
        guard let token = Session.token, let url = URL(string: Config.apiBase + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            // توکن باطل شده (مثلاً خروج یا ورود دوباره)؛ بار بعد که صفحه‌ی وب باز شود، توکن تازه گرفته می‌شود
            if code == 401 { Session.token = nil }
            return APIResult(status: code, json: obj)
        } catch {
            return nil
        }
    }
}
