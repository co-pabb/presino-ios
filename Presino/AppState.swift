import Foundation
import Combine
import UIKit

/// وضعیت مشترکِ صفحه‌های نیتیو: داده‌ی صفحه‌ی اصلی (کارمند: employee_home — مدیر: manager_dashboard)،
/// آخرین نسخه‌ی ذخیره‌شده برای حالت آفلاین، تعداد اعلان‌های خوانده‌نشده و صف آفلاین.
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var home: JSON = [:]
    @Published var role: String = Session.role
    @Published var loaded = false
    @Published var offline = false
    @Published var busy = false
    @Published var message: String? = nil
    @Published var queued = OfflineQueue.shared.count
    @Published var unread = 0

    private let cacheKey = "cache.home"
    private var timer: Timer?

    var isManager: Bool { return role != "" && role != "employee" }

    init() {
        loadCache()
    }

    // MARK: - ذخیره‌ی آخرین داده (حالت آفلاین)

    func loadCache() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let o = (try? JSONSerialization.jsonObject(with: data)) as? JSON {
            home = o
            loaded = true
        }
    }

    // MARK: - بارگذاری

    /// نقش کاربر: اگر هنوز ثبت نشده باشد، با صدا زدن میز مدیریت تشخیص داده می‌شود (مدیر موفق می‌شود، کارمند رد می‌شود)
    private func ensureRole() async {
        if !Session.role.isEmpty {
            let r = Session.role
            DispatchQueue.main.async { self.role = r }
            return
        }
        guard let r = await API.call("manager_dashboard.php") else { return }
        if r.status == 200 && r.json.b("success") {
            Session.role = "manager"
        } else if r.status == 403 || r.status == 401 || r.status == 404 {
            if r.status != 401 { Session.role = "employee" }
        }
        let nr = Session.role
        DispatchQueue.main.async { self.role = nr }
    }

    func reload() async {
        guard Session.token != nil, !Demo.on else { return }
        await ensureRole()
        let path = Session.isManager ? "manager_dashboard.php" : "employee_home.php"
        let r = await API.call(path)
        guard let res = r else {
            DispatchQueue.main.async { self.offline = true }
            return
        }
        if res.status == 200 && res.json.b("success") {
            let j = res.json
            if let data = try? JSONSerialization.data(withJSONObject: j) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
            let n = j.i("notifications_unread")
            DispatchQueue.main.async {
                self.home = j
                self.loaded = true
                self.offline = false
                self.unread = n
                self.queued = OfflineQueue.shared.count
                self.applyBadge()
            }
            if !Session.isManager {
                ReminderService.reschedule(home: j)
                await ReminderService.refreshPlans()
            }
        } else {
            DispatchQueue.main.async { self.offline = false }
        }
    }

    // MARK: - چرخه‌ی برنامه

    func afterLogin() {
        DispatchQueue.main.async { self.role = Session.role }
        NotificationHelper.requestAuth()
        PermissionState.shared.refresh()
        Task {
            await self.reload()
            _ = await OfflineQueue.shared.flush()
            await NotificationService.shared.poll()
            await RouteTracker.shared.refresh()
        }
    }

    func foreground() {
        PermissionState.shared.refresh()
        guard Session.token != nil else { return }
        Task {
            await self.reload()
            _ = await OfflineQueue.shared.flush()
            await NotificationService.shared.poll()
            await RouteTracker.shared.refresh()
        }
        startTimer()
    }

    func background() {
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 90, repeats: true) { _ in
            Task {
                await NotificationService.shared.poll()
                _ = await OfflineQueue.shared.flush()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - کمکی

    func toast(_ text: String) {
        DispatchQueue.main.async {
            self.message = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                if self.message == text { self.message = nil }
            }
        }
    }

    func applyBadge() {
        let n = unread
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = n
        }
    }

    /// ثبتِ آفلاین: وضعیت و فهرست تردد امروز همین الان در گوشی عوض می‌شود (تا ارسال به سرور)
    func applyLocal(type: String, project: String, time: String) {
        DispatchQueue.main.async {
            var h = self.home
            var logs = h.a("today_logs")
            logs.append(["id": 0, "type": type, "time": time, "project_name": project, "in_range": true, "offline": true])
            h["today_logs"] = logs
            h["next_action"] = type == "check_in" ? "check_out" : "check_in"
            self.home = h
            self.queued = OfflineQueue.shared.count
            if let data = try? JSONSerialization.data(withJSONObject: h) {
                UserDefaults.standard.set(data, forKey: self.cacheKey)
            }
        }
    }

    /// تغییر نقش بعد از ورود/خروج
    func sessionChanged() {
        DispatchQueue.main.async {
            self.role = Session.role
            if Session.token == nil {
                self.home = [:]
                self.loaded = false
                self.unread = 0
                self.applyBadge()
            }
        }
    }
}
