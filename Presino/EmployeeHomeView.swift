import SwiftUI

/// صفحه‌ی اول کارمند: وضعیت امروز، دکمه‌ی بزرگ ثبت ورود/خروج، تردد امروز، آمار، برنامه‌ی من و میان‌برها
struct EmployeeHomeView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var perm = PermissionState.shared
    let openWeb: (String) -> Void
    let openNotifications: () -> Void

    init(openWeb: @escaping (String) -> Void, openNotifications: @escaping () -> Void) {
        self.openWeb = openWeb
        self.openNotifications = openNotifications
    }

    private var home: JSON { return state.home }
    private var isIn: Bool { return home.s("next_action") == "check_out" }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                banners
                statusCard
                statsGrid
                planCard
                linksGrid
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .refreshable { await state.reload() }
    }

    // MARK: - سربرگ

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(home.s("company_name").isEmpty ? "Presino" : home.s("company_name")).font(.headline)
                Text(subtitle).font(.footnote).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: openNotifications) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill").font(.title3).foregroundColor(Brand.blue).frame(width: 40, height: 40)
                    if state.unread > 0 {
                        Text("\(state.unread)").font(.caption2.bold()).foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(Brand.red).clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let name = home.o("employee").s("full_name")
        let day = home.s("today_jalali")
        if name.isEmpty { return day }
        if day.isEmpty { return name }
        return name + " · " + day
    }

    // MARK: - هشدارها

    @ViewBuilder private var banners: some View {
        if let m = state.message {
            Banner(text: m, icon: "info.circle.fill", color: Brand.blue)
        }
        if state.offline {
            Banner(text: "اینترنت قطع است؛ آخرین اطلاعات ذخیره‌شده نمایش داده می‌شود. ثبت ورود و خروج در این حالت هم کار می‌کند و بعداً ارسال می‌شود.",
                   icon: "wifi.slash", color: Brand.orange)
        }
        if state.queued > 0 {
            Banner(text: "\(state.queued) ثبت آفلاین در انتظار ارسال به سرور است.", icon: "arrow.triangle.2.circlepath",
                   color: Brand.orange, actionTitle: "ارسال اکنون", action: { Task { _ = await OfflineQueue.shared.flush() } })
        }
        if perm.wantsAlways {
            Banner(text: "برای ثبت خودکار ورود و خروج و ثبت مسیر در پس‌زمینه، دسترسی موقعیت را روی «همیشه» بگذارید.",
                   icon: "location.fill", color: Brand.orange, actionTitle: "باز کردن تنظیمات", action: { PermissionState.openSettings() })
        }
        if perm.notifDenied {
            Banner(text: "اعلان‌ها خاموش است؛ یادآور ورود و خروج و اعلان‌های مدیر را دریافت نمی‌کنید.",
                   icon: "bell.slash.fill", color: Brand.red, actionTitle: "باز کردن تنظیمات", action: { PermissionState.openSettings() })
        }
    }

    // MARK: - ثبت تردد

    private var shiftText: String {
        let shift = home.o("shift")
        if shift.isEmpty { return "" }
        if !shift.b("is_working") { return "امروز روز کاری شما نیست" }
        let s = String(shift.s("start_time").prefix(5))
        let e = String(shift.s("end_time").prefix(5))
        if s.isEmpty { return "" }
        return "شیفت امروز: \(s) تا \(e)"
    }

    private var statusCard: some View {
        Card {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(isIn ? Brand.green : Color.gray).frame(width: 10, height: 10)
                    Text(isIn ? "الان در محل کار هستید" : "ورود امروز ثبت نشده").font(.subheadline.bold())
                    Spacer()
                }
                if !shiftText.isEmpty {
                    Text(shiftText).font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if state.busy { ProgressView() }
                        Text(isIn ? "ثبت خروج" : "ثبت ورود").font(.title3.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isIn ? Brand.red : Brand.green)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(state.busy || perm.blocking)
                logsList
            }
        }
    }

    @ViewBuilder private var logsList: some View {
        let logs = home.a("today_logs")
        if !logs.isEmpty {
            Divider()
            ForEach(Array(logs.enumerated()), id: \.offset) { _, l in
                logRow(l)
            }
        }
    }

    private func logRow(_ l: JSON) -> some View {
        let inLog = l.s("type") == "check_in"
        return HStack(spacing: 8) {
            Image(systemName: inLog ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundColor(inLog ? Brand.green : Brand.red)
            Text(inLog ? "ورود" : "خروج").font(.subheadline)
            Text(l.s("time")).font(.subheadline.bold())
            Text(l.s("project_name")).font(.footnote).foregroundColor(.secondary).lineLimit(1)
            Spacer()
            if l.b("offline") {
                Text("آفلاین").font(.caption2.bold()).foregroundColor(Brand.orange)
            }
            if !l.b("in_range") {
                Text("خارج از محدوده").font(.caption2.bold()).foregroundColor(Brand.red)
            }
        }
    }

    private func submit() {
        let type = isIn ? "check_out" : "check_in"
        Task {
            let res = await AttendanceService.submit(type: type)
            switch res {
            case .done(let m):
                state.toast("✅ " + m)
            case .queued(let m):
                state.toast("📴 " + m)
            case .failed(let m):
                state.toast("⚠️ " + m)
            case .needsWeb(let m):
                state.toast(m)
                openWeb("/employee/index.php")
            }
        }
    }

    // MARK: - آمار

    private var statsGrid: some View {
        let st = home.o("stats")
        let net = st.s("last_net")
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(title: "روز کارکرد این ماه", value: "\(st.i("worked_days"))", icon: "calendar", tint: Brand.blue)
            StatTile(title: "ساعت کارکرد", value: "\(st.i("worked_hours"))", icon: "clock.fill", tint: Brand.green)
            StatTile(title: "درخواست در انتظار", value: "\(st.i("requests_pending"))", icon: "tray.full.fill", tint: Brand.orange)
            StatTile(title: net.isEmpty ? "آخرین فیش" : st.s("last_net_label"), value: net.isEmpty ? "-" : net,
                     icon: "banknote.fill", tint: Brand.blue)
        }
    }

    // MARK: - برنامه‌ی من

    @ViewBuilder private var planCard: some View {
        let plans = home.a("plan_today")
        if !plans.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("برنامه‌ی امروز من").font(.subheadline.bold())
                    ForEach(Array(plans.prefix(6).enumerated()), id: \.offset) { _, p in
                        RowItem(icon: p.s("icon").isEmpty ? "•" : p.s("icon"), title: p.s("title"), sub: p.s("sub"),
                                badge: p.s("badge"), tint: p.b("overdue") ? Brand.red : Brand.blue)
                    }
                }
            }
        }
    }

    // MARK: - میان‌برها

    private var linksGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            LinkTile(title: "درخواست‌ها", icon: "tray.full.fill") { openWeb("/employee/requests.php") }
            LinkTile(title: "وظایف", icon: "checklist") { openWeb("/employee/my_tasks.php") }
            LinkTile(title: "پیام‌ها", icon: "bubble.left.and.bubble.right.fill", badge: home.i("unread_internal")) { openWeb("/employee/messages.php") }
            LinkTile(title: "گزارش‌ها", icon: "chart.bar.fill") { openWeb("/employee/reports.php") }
            LinkTile(title: "فیش حقوقی", icon: "doc.text.fill") { openWeb("/employee/payslip.php") }
            LinkTile(title: "پروفایل", icon: "person.fill") { openWeb("/employee/profile.php") }
        }
    }
}
