import Foundation

/// حالت نمایشی فقط برای شبیه‌ساز (تست خودکار GitHub): بدون ورود و اینترنت، صفحه‌های داخلی با داده‌ی نمونه باز می‌شوند
/// تا بتوان از آن‌ها اسکرین‌شات گرفت. در نسخه‌ی واقعی گوشی (و ipa) هیچ اثری ندارد: on همیشه false است.
#if targetEnvironment(simulator)
enum Demo {
    static var mode: String { return UserDefaults.standard.string(forKey: "PresinoDemo") ?? "" }
    static var tab: Int { return UserDefaults.standard.integer(forKey: "PresinoTab") }
    static var on: Bool { return !mode.isEmpty }

    static func install() {
        let manager = mode == "manager"
        Session.role = manager ? "main_admin" : "employee"
        Session.userId = 1
        Session.token = "demo"
        AppState.shared.role = Session.role
        AppState.shared.home = manager ? managerHome() : employeeHome()
        AppState.shared.loaded = true
        AppState.shared.offline = false
        AppState.shared.unread = 3
    }

    static func employeeHome() -> JSON {
        return [
            "success": true,
            "company_name": "شرکت ساختمانی پارس",
            "today_jalali": "۱۴۰۵/۰۸/۲۱",
            "employee": ["full_name": "علی رضایی", "bypass_location": false, "auto_checkin": true, "auto_checkout": true] as JSON,
            "next_action": "check_out",
            "today_logs": [
                ["type": "check_in", "time": "08:02", "project_name": "برج مسکونی نگین", "in_range": true, "offline": false] as JSON,
                ["type": "check_out", "time": "12:30", "project_name": "برج مسکونی نگین", "in_range": true, "offline": true] as JSON,
                ["type": "check_in", "time": "13:15", "project_name": "برج مسکونی نگین", "in_range": false, "offline": false] as JSON,
            ],
            "shift": ["is_working": true, "start_time": "08:00:00", "end_time": "17:00:00"] as JSON,
            "stats": ["worked_days": 14, "worked_hours": 112, "requests_pending": 1,
                      "last_net": "۱۸,۵۰۰,۰۰۰", "last_net_label": "مهر ۱۴۰۵"] as JSON,
            "plan_today": [
                ["kind": "task", "title": "بازدید از قالب‌بندی طبقه ۳", "sub": "پروژه: برج نگین", "badge": "10:30", "icon": "✅", "overdue": false] as JSON,
                ["kind": "plan", "title": "تماس با تأمین‌کننده میلگرد", "sub": "تماس · 🔔 ۱۰ دقیقه قبل", "badge": "14:00", "icon": "📞", "overdue": false] as JSON,
                ["kind": "task", "title": "ثبت گزارش روزانه", "sub": "پروژه: برج نگین · سررسید ۱۴۰۵/۰۸/۲۰", "badge": "عقب‌افتاده", "icon": "⏰", "overdue": true] as JSON,
            ],
            "unread_internal": 2,
            "notifications_unread": 3,
        ]
    }

    static func managerHome() -> JSON {
        return [
            "success": true,
            "company_name": "شرکت ساختمانی پارس",
            "today_jalali": "۱۴۰۵/۰۸/۲۱",
            "weekday": "پنجشنبه",
            "stats": ["total_employees": 42, "present_now": 31, "absent_now": 11, "pending_requests": 4, "pending_device_requests": 1] as JSON,
            "present": [
                ["name": "علی رضایی", "since": "08:02", "place": "برج مسکونی نگین"] as JSON,
                ["name": "مریم احمدی", "since": "08:10", "place": "پروژه سیار"] as JSON,
                ["name": "حسین کریمی", "since": "08:25", "place": "کارگاه مرکزی"] as JSON,
            ],
            "pending_list": [
                ["name": "سارا محمدی", "type": "مرخصی", "ago": "۲ ساعت پیش"] as JSON,
                ["name": "رضا نوری", "type": "اضافه‌کاری", "ago": "دیروز"] as JSON,
            ],
            "pending_msg_replies": 1,
            "notifications_unread": 3,
        ]
    }

    static var notifications: [JSON] {
        return [
            ["id": 3, "type": "request_approved", "title": "درخواست مرخصی شما تأیید شد", "body": "مرخصی روز ۲۵ آبان تأیید شد.", "read": false, "target": "tab:1", "when": "۱۴۰۵/۰۸/۲۱ 09:12"] as JSON,
            ["id": 2, "type": "task_due", "title": "موعد وظیفه: بازدید قالب‌بندی", "body": "ساعت ۱۰:۳۰ امروز", "read": false, "target": "more:tasks", "when": "۱۴۰۵/۰۸/۲۱ 08:30"] as JSON,
            ["id": 1, "type": "payroll", "title": "فیش حقوقی مهر منتشر شد", "body": "", "read": true, "target": "more:payslips", "when": "۱۴۰۵/۰۸/۰۱ 10:00"] as JSON,
        ]
    }
}
#else
enum Demo {
    static var on: Bool { return false }
    static var tab: Int { return 0 }
    static func install() {}
    static var notifications: [JSON] { return [] }
}
#endif
