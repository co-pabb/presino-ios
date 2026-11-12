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
        func pt(_ id: Int, _ name: String, _ proj: String, _ time: String, _ inside: Bool, _ lat: Double, _ lng: Double) -> JSON {
            return ["id": id, "name": name, "proj": proj, "time": time, "in": inside, "lat": lat, "lng": lng, "photo": "", "pc": [], "g": "m", "approx": false, "h": 200] as JSON
        }
        let points: [JSON] = [
            pt(1, "علی رضایی", "برج مسکونی نگین", "08:02", true, 35.7001, 51.4012),
            pt(2, "مریم احمدی", "برج مسکونی نگین", "08:10", true, 35.7005, 51.4019),
            pt(3, "حسین کریمی", "کارگاه مرکزی", "08:25", true, 35.6712, 51.3705),
            pt(4, "رضا نوری", "کارگاه مرکزی", "12:30", false, 35.6709, 51.3711),
        ]
        return [
            "success": true,
            "company_name": "شرکت ساختمانی پارس",
            "full_name": "محمد مدیری",
            "today_jalali": "۱۴۰۵/۰۸/۲۱",
            "weekday": "پنجشنبه",
            "server_seconds": 9 * 3600 + 41 * 60 + 7,
            "stats": ["total_employees": 42, "present_now": 31, "absent_now": 11, "pending_requests": 4, "pending_device_requests": 1] as JSON,
            "map": [
                "points": points,
                "projects": [
                    ["id": 1, "name": "برج مسکونی نگین", "lat": 35.7003, "lng": 51.4015, "city": "تهران", "av": "", "ico": "office"] as JSON,
                    ["id": 2, "name": "کارگاه مرکزی", "lat": 35.6710, "lng": 51.3708, "city": "تهران", "av": "", "ico": "office"] as JSON,
                ],
                "no_loc": 0,
            ] as JSON,
            "lists": [
                "present": ["علی رضایی", "مریم احمدی", "حسین کریمی"],
                "out": ["رضا نوری"],
                "absent": ["سارا محمدی", "امیر حسینی"],
                "leave": ["نگار صادقی"],
                "mission": ["پیمان فرهادی"],
            ] as JSON,
            "people": [
                ["name": "علی رضایی", "proj": "برج مسکونی نگین", "time": "08:02", "in": true, "id": 1] as JSON,
                ["name": "مریم احمدی", "proj": "برج مسکونی نگین", "time": "08:10", "in": true, "id": 2] as JSON,
                ["name": "حسین کریمی", "proj": "کارگاه مرکزی", "time": "08:25", "in": true, "id": 3] as JSON,
                ["name": "رضا نوری", "proj": "کارگاه مرکزی", "time": "12:30", "in": false, "id": 4] as JSON,
            ],
            "sub": ["ended": false, "days": 5] as JSON,
            "unread_system": 1,
            "plans_today": [
                ["icon": "📞", "title": "تماس با تأمین‌کننده میلگرد", "cat_label": "تماس", "remind_label": "۱۰ دقیقه قبل", "time": "14:00", "overdue": false] as JSON,
            ],
            "company_tasks_today": [
                ["id": 5, "title": "بازدید قالب‌بندی طبقه سوم", "meta": "پروژه: برج نگین", "tag": "۱۰:۳۰", "overdue": false] as JSON,
                ["id": 6, "title": "ثبت گزارش روزانه", "meta": "پروژه: کارگاه مرکزی", "tag": "عقب‌افتاده", "overdue": true] as JSON,
            ],
            "activity": [
                ["name": "حسین کریمی", "meta": "ورود · کارگاه مرکزی", "time": "08:25", "in": true] as JSON,
                ["name": "رضا نوری", "meta": "خروج · کارگاه مرکزی", "time": "12:30", "in": false] as JSON,
                ["name": "مریم احمدی", "meta": "ورود خودکار · برج مسکونی نگین", "time": "08:10", "in": true] as JSON,
            ],
            "todos": [
                ["k": "orange", "icon": "doc", "title": "درخواست‌ها", "sub": "مرخصی، اضافه‌کاری، مساعده…", "count": 4, "go": "tab:1"] as JSON,
                ["k": "sky", "icon": "phone", "title": "تغییر دستگاه", "sub": "منتظر تأیید شما", "count": 1, "go": "tab:1"] as JSON,
                ["k": "green", "icon": "chat", "title": "پشتیبانی", "sub": "پاسخ جدید تیکت", "count": 0, "go": "more:support"] as JSON,
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
