import Foundation
import UIKit
import UserNotifications

enum NotificationHelper {
    /// اعلان فوری محلی (روی صفحه‌ی گوشی؛ در حالت باز بودن برنامه هم به‌صورت بنر نشان داده می‌شود)
    static func local(title: String, body: String, target: String, id: String? = nil) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.userInfo = ["target": target]
        let req = UNNotificationRequest(identifier: id ?? UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    /// درخواست مجوز اعلان (یک‌بار؛ بعدش iOS دوباره نمی‌پرسد)
    static func requestAuth() {
        if Demo.on { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            PermissionState.shared.refresh()
        }
    }
}

/// اعلان‌های برنامه (درخواست جدید، پیام، وظیفه، …).
/// بدون سرور پوش اپل، گوشی خودش از سرور می‌پرسد: هنگام باز شدن برنامه، هر ۹۰ ثانیه در حالت باز،
/// و در پس‌زمینه هر بار iOS برنامه را بیدار کند (کار دوره‌ای iOS، تغییر موقعیت، ثبت مسیر).
final class NotificationService {
    static let shared = NotificationService()

    private let ud = UserDefaults.standard
    private var polling = false

    func poll() async {
        guard Session.token != nil, !polling else { return }
        polling = true
        guard let r = await API.call("notifications.php"), r.status == 200 else {
            polling = false
            return
        }
        let items = r.json.a("items")
        let unread = r.json.i("unread")
        var maxId = 0
        for n in items { maxId = max(maxId, n.i("id")) }
        let last = ud.object(forKey: "ns.last") as? Int ?? -1
        DispatchQueue.main.async {
            AppState.shared.unread = unread
            AppState.shared.applyBadge()
        }
        // اولین بار: فقط وضعیت فعلی ثبت می‌شود تا اعلان‌های قدیمی یک‌جا نمایش داده نشوند
        if last < 0 {
            ud.set(maxId, forKey: "ns.last")
            polling = false
            return
        }
        var fresh = items.filter { $0.i("id") > last }
        fresh.sort { $0.i("id") < $1.i("id") }
        if fresh.count > 5 { fresh = Array(fresh.suffix(5)) }
        for n in fresh {
            let type = n.s("type")
            let isAlarm = type == "task_due" || type == "task_remaining" || type == "alarm"
            var title = n.s("title")
            if title.isEmpty { title = isAlarm ? "آلارم" : "اعلان جدید" }
            if isAlarm { title = "⏰ " + title }
            var body = n.s("body")
            if body.isEmpty { body = "برای مشاهده وارد برنامه شوید" }
            NotificationHelper.local(title: title, body: body, target: n.s("target"), id: "nt.\(n.i("id"))")
        }
        if maxId > last { ud.set(maxId, forKey: "ns.last") }
        polling = false
    }

    func list() async -> [JSON]? {
        if Demo.on { return Demo.notifications }
        guard let r = await API.call("notifications.php?all=1"), r.status == 200 else { return nil }
        return r.json.a("items")
    }

    func markRead(id: Int) async {
        _ = await API.call("notifications.php", method: "POST", body: ["id": id])
        await poll()
    }

    func markAllRead() async {
        _ = await API.call("notifications.php", method: "POST", body: ["all": true])
        await poll()
    }
}
