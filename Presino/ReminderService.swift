import Foundation
import UserNotifications

/// یادآورها و آلارم‌های محلی (بدون نیاز به اینترنت و سرور پوش):
///  • ۵ دقیقه قبل و بعد از شروع و پایان شیفت (فقط روزهای کاری؛ با ثبت ورود/خروج، یادآورِ همان روز لغو می‌شود)
///  • وضعیت وظایف ساعت ۱۲ (فقط روزی که وظیفه دارد)
///  • «یادیار»: برنامه‌های شخصی که ساعت و یادآوری دارند
/// iOS فقط ۶۴ اعلان زمان‌بندی‌شده را نگه می‌دارد؛ پس فقط نزدیک‌ترین‌ها زمان‌بندی می‌شوند و با هر بار باز شدن برنامه تازه می‌شوند.
enum ReminderService {
    private static let ud = UserDefaults.standard

    static var remindIn: Bool {
        get { return ud.object(forKey: "rm.in") as? Bool ?? true }
        set { ud.set(newValue, forKey: "rm.in") }
    }

    static var remindOut: Bool {
        get { return ud.object(forKey: "rm.out") as? Bool ?? true }
        set { ud.set(newValue, forKey: "rm.out") }
    }

    private struct Planned {
        let id: String
        let date: Date
        let title: String
        let body: String
        let target: String
    }

    static func clearAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map { $0.identifier }.filter { $0.hasPrefix("rm.") || $0.hasPrefix("pl.") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// بعد از ثبت ورود، یادآورهای «ورود» امروز؛ بعد از ثبت خروج، یادآورهای «خروج» امروز لغو می‌شوند
    static func cancelToday(after type: String) {
        let key = Fmt.ymd(Date())
        let suffixes = type == "check_in" ? [".ib", ".ia"] : [".ob", ".oa"]
        let ids = suffixes.map { "rm.\(key)\($0)" }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// یادآورهای شیفت و وظایف از روی دادهٔ صفحهٔ اصلی کارمند
    static func reschedule(home: JSON) {
        var list: [Planned] = []
        let now = Date()
        let todayKey = Fmt.ymd(now)
        let logs = home.a("today_logs")
        let hasIn = logs.contains { $0.s("type") == "check_in" }
        let lastType = logs.last?.s("type") ?? ""
        let days = home.o("shift_days")
        var worked = 0
        for k in days.keys.sorted() {
            if k < todayKey { continue }
            let d = days.o(k)
            if !d.b("w") || d.s("s").isEmpty { continue }
            worked += 1
            if worked > 5 { break }
            let isToday = (k == todayKey)
            if remindIn && !(isToday && hasIn), let t = Fmt.parse(k + " " + d.s("s")) {
                list.append(Planned(id: "rm.\(k).ib", date: t.addingTimeInterval(-300), title: "⏰ ۵ دقیقه تا شروع شیفت",
                                    body: "ثبت ورود را فراموش نکنید.", target: "tab:0"))
                list.append(Planned(id: "rm.\(k).ia", date: t.addingTimeInterval(300), title: "ساعت شروع شیفت گذشته",
                                    body: "ورود شما هنوز ثبت نشده است.", target: "tab:0"))
            }
            if remindOut && !(isToday && lastType == "check_out"), !d.s("e").isEmpty, let t = Fmt.parse(k + " " + d.s("e")) {
                list.append(Planned(id: "rm.\(k).ob", date: t.addingTimeInterval(-300), title: "⏰ ۵ دقیقه تا پایان شیفت",
                                    body: "برای ثبت خروج آماده شوید.", target: "tab:0"))
                list.append(Planned(id: "rm.\(k).oa", date: t.addingTimeInterval(300), title: "ساعت پایان شیفت گذشته",
                                    body: "خروج شما هنوز ثبت نشده است.", target: "tab:0"))
            }
        }
        // وضعیت وظایف: ساعت ۱۲ فقط روزی که وظیفه‌ای دارد (امروز و فردا از برنامه‌ی من)
        let tomorrowKey = Fmt.ymd(now.addingTimeInterval(86400))
        let todayHasTask = home.a("plan_today").contains { $0.s("kind") == "task" }
        let tomorrowHasTask = home.a("plan_tomorrow").contains { $0.s("kind") == "task" }
        for (key, has) in [(todayKey, todayHasTask), (tomorrowKey, tomorrowHasTask)] where has {
            if let t = Fmt.parse(key + " 12:00") {
                list.append(Planned(id: "rm.\(key).tc", date: t, title: "وضعیت وظایف امروز",
                                    body: "وضعیت وظایف خود را ثبت کنید.", target: "more:taskCheckin"))
            }
        }
        apply(prefix: "rm.", planned: list)
    }

    /// یادآورهای «یادیار» از سرور
    static func refreshPlans() async {
        guard let r = await API.call("personal_plans.php?alarms=1"), r.status == 200 else { return }
        var list: [Planned] = []
        for a in r.json.a("alarms") {
            let at = a.d("at") ?? 0
            if at <= 0 { continue }
            list.append(Planned(id: "pl.\(a.i("id"))", date: Date(timeIntervalSince1970: at), title: a.s("title"),
                                body: a.s("body"), target: "more:planner"))
        }
        apply(prefix: "pl.", planned: list)
    }

    private static func apply(prefix: String, planned: [Planned]) {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let limit = prefix == "rm." ? 30 : 25
        let upcoming = planned.filter { $0.date.timeIntervalSince(now) > 5 }.sorted { $0.date < $1.date }
        let chosen = Array(upcoming.prefix(limit))
        center.getPendingNotificationRequests { reqs in
            let old = reqs.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for p in chosen {
                let c = UNMutableNotificationContent()
                c.title = p.title
                c.body = p.body
                c.sound = .default
                c.userInfo = ["target": p.target]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(p.date.timeIntervalSince(Date()), 1), repeats: false)
                center.add(UNNotificationRequest(identifier: p.id, content: c, trigger: trigger), withCompletionHandler: nil)
            }
        }
    }
}
