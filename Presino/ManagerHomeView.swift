import SwiftUI

/// صفحه‌ی اول مدیر — دقیقاً به ترتیب داشبورد وب/اندروید:
/// هدر، نقشه‌ی زنده‌ی پرسنل (ساعت، سلام، پنج وضعیت)، هشدار اشتراک، برنامه‌ی امروز، آخرین ترددهای امروز، نیازمند اقدام
struct ManagerHomeView: View {
    @ObservedObject var state = AppState.shared
    @Environment(\.colorScheme) private var scheme
    let openWeb: (String) -> Void
    let openNotifications: () -> Void
    let openTarget: (String) -> Void
    let openSettings: () -> Void
    @State private var menuOpen = false
    @State private var avatar: UIImage?

    init(openWeb: @escaping (String) -> Void, openNotifications: @escaping () -> Void,
         openTarget: @escaping (String) -> Void = { _ in }, openSettings: @escaping () -> Void = {}) {
        self.openWeb = openWeb
        self.openNotifications = openNotifications
        self.openTarget = openTarget
        self.openSettings = openSettings
    }

    private var home: JSON { return state.home }
    private var dark: Bool { return scheme == .dark }
    private var nx: Nx { return Nx(dark: dark) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if let m = state.message { Banner(text: m, icon: "info.circle.fill", color: nx.blue) }
                if state.offline {
                    Banner(text: "اینترنت قطع است؛ آخرین اطلاعات ذخیره‌شده نمایش داده می‌شود.", icon: "wifi.slash", color: Brand.orange)
                }
                StaffMapCard(home: home)
                subscriptionBanner
                unreadBanner
                todayCard
                activityCard
                todosCard
                Spacer().frame(height: 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        .background(nx.bg.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .refreshable { await state.reload() }
        .sheet(isPresented: $menuOpen) { menuSheet }
        .task(id: home.s("photo_url")) {
            let u = home.s("photo_url")
            if !u.isEmpty { avatar = await PhotoLoader.first([u]) }
        }
    }

    // MARK: - هدر

    private var header: some View {
        HStack(spacing: 8) {
            iconButton("line.3.horizontal") { menuOpen = true }
            VStack(alignment: .leading, spacing: 2) {
                Text(home.s("company_name").isEmpty ? "Presino" : home.s("company_name"))
                    .font(.system(size: 17, weight: .bold)).foregroundColor(nx.text).lineLimit(1)
                Text(Fa.digits(subtitle)).font(.system(size: 12)).foregroundColor(nx.muted)
            }
            Spacer(minLength: 4)
            iconButton(dark ? "sun.max.fill" : "moon.fill") { ThemeStore.toggle(currentlyDark: dark) }
            ZStack(alignment: .topTrailing) {
                iconButton("bell.fill") { openNotifications() }
                if state.unread > 0 {
                    Text(Fa.n(state.unread)).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1).background(Brand.red).clipShape(Capsule())
                        .offset(x: 4, y: -2)
                }
            }
            Menu {
                Button("پروفایل شرکت") { openWeb("/manager/business_settings.php") }
                Button("اشتراک‌ها") { openWeb("/manager/subscriptions.php") }
                Button("تنظیمات برنامه") { openSettings() }
                Button("انتخاب زبان") { openWeb("/manager/appearance_settings.php") }
                Button("خروج") { openWeb("/auth/logout.php") }
            } label: {
                avatarView
            }
        }
    }

    private var avatarView: some View {
        let name = home.s("full_name")
        return ZStack {
            if let a = avatar {
                Image(uiImage: a).resizable().scaledToFill()
            } else {
                Circle().fill(Color(hue: nameHue(name) / 360, saturation: 0.55, brightness: 0.62))
                Text(String(name.prefix(1))).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .overlay(Circle().stroke(nx.border, lineWidth: 1))
    }

    private func iconButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundColor(nx.text)
                .frame(width: 38, height: 38)
                .background(nx.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(nx.border, lineWidth: 1))
        }
    }

    private var subtitle: String {
        let wd = home.s("weekday")
        let day = home.s("today_jalali")
        return wd.isEmpty ? day : wd + " " + day
    }

    // MARK: - هشدارها

    @ViewBuilder private var subscriptionBanner: some View {
        let sb = home.o("sub")
        if !sb.isEmpty {
            let ended = sb.b("ended")
            let text = ended ? "⛔ اشتراک شما به پایان رسیده است؛ برای ادامه تمدید کنید ‹"
                : "⏰ فقط " + Fa.n(sb.i("days")) + " روز تا پایان اشتراک مانده است؛ تمدید کنید ‹"
            Button(action: { openWeb("/manager/subscriptions.php") }) {
                Text(text).font(.system(size: 13, weight: .semibold)).foregroundColor(nx.text)
                    .multilineTextAlignment(.leading)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background((ended ? nx.red : nx.orange).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke((ended ? nx.red : nx.orange).opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    @ViewBuilder private var unreadBanner: some View {
        let n = home.i("unread_system")
        if n > 0 {
            Button(action: { openWeb("/manager/messages.php") }) {
                Text("📩 " + Fa.n(n) + " پیام خوانده‌نشده از مدیر سامانه").font(.system(size: 13, weight: .semibold)).foregroundColor(nx.text)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(nx.blue.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(nx.blue.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - کارت‌ها

    private func dbCard<Content: View>(_ title: String, _ sub: String, link: String?, _ action: @escaping () -> Void,
                                       @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(nx.text)
                    if !sub.isEmpty { Text(sub).font(.system(size: 11)).foregroundColor(nx.muted) }
                }
                Spacer()
                if let l = link {
                    Button(action: action) { Text(l).font(.system(size: 12, weight: .semibold)).foregroundColor(nx.sky) }
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(nx.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(nx.border, lineWidth: 1))
    }

    private func timelineRow(_ name: String, _ meta: String, time: String, dot: Color, tag: String? = nil, tagColor: Color = .gray,
                             action: (() -> Void)? = nil) -> some View {
        Button(action: { action?() }) {
            HStack(spacing: 12) {
                Circle().fill(dot).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 14, weight: .semibold)).foregroundColor(nx.text).lineLimit(1)
                    if !meta.isEmpty { Text(meta).font(.system(size: 11)).foregroundColor(nx.muted).lineLimit(1) }
                }
                Spacer(minLength: 6)
                if let t = tag, !t.isEmpty {
                    Text(Fa.digits(t)).font(.system(size: 11, weight: .bold)).foregroundColor(tagColor)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(tagColor.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                if !time.isEmpty { Text(Fa.digits(time)).font(.system(size: 12)).foregroundColor(nx.muted) }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func planMeta(_ p: JSON) -> String {
        var meta = "برنامه من · " + p.s("cat_label")
        if !p.s("remind_label").isEmpty { meta += " · 🔔 " + p.s("remind_label") }
        return meta
    }

    private var todayCard: some View {
        let plans = home.a("plans_today")
        let tasks = home["company_tasks_today"] != nil ? home.a("company_tasks_today") : home.a("tasks_today")
        return dbCard("برنامهٔ امروز", "یادیار و وظایف سررسیدشده", link: "برنامه من ‹", { openWeb("/tasks/personal.php") }) {
            VStack(spacing: 0) {
                ForEach(0..<plans.count, id: \.self) { i in
                    let p = plans[i]
                    let overdue = p.b("overdue")
                    let noTime = p.s("time").isEmpty
                    timelineRow(p.s("icon") + " " + p.s("title"), planMeta(p),
                                time: (overdue && noTime) ? "" : (noTime ? "امروز" : p.s("time")),
                                dot: overdue ? nx.red : nx.blue,
                                tag: (overdue && noTime) ? "عقب‌افتاده" : nil, tagColor: nx.red) { openWeb("/tasks/personal.php") }
                }
                ForEach(0..<tasks.count, id: \.self) { i in
                    let t = tasks[i]
                    let overdue = t.b("overdue")
                    let tag = !t.s("tag").isEmpty ? t.s("tag") : (!t.s("time").isEmpty ? t.s("time") : "امروز")
                    timelineRow(t.s("title"), t.s("meta"), time: "", dot: overdue ? nx.red : nx.orange,
                                tag: tag, tagColor: overdue ? nx.red : nx.orange) { openWeb("/manager/tasks.php") }
                }
                if plans.isEmpty && tasks.isEmpty {
                    HStack(spacing: 0) {
                        Text("برای امروز برنامه‌ای ثبت نشده — ").font(.system(size: 12)).foregroundColor(nx.muted)
                        Button(action: { openWeb("/tasks/personal.php") }) {
                            Text("＋ افزودن").font(.system(size: 12, weight: .bold)).foregroundColor(nx.sky)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var activityCard: some View {
        let act = home.a("activity")
        return dbCard("آخرین ترددهای امروز", "جریان زندهٔ ورود و خروج", link: "مشاهده همه ‹", { openWeb("/manager/reports.php") }) {
            VStack(spacing: 0) {
                if act.isEmpty {
                    Text("هنوز ترددی امروز ثبت نشده").font(.system(size: 12)).foregroundColor(nx.muted)
                        .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(0..<act.count, id: \.self) { i in
                    let a = act[i]
                    let isIn = a.b("in")
                    timelineRow(a.s("name"), a.s("meta"), time: a.s("time"), dot: isIn ? nx.green : nx.red,
                                tag: isIn ? "ورود" : "خروج", tagColor: isIn ? nx.green : nx.red) { openWeb("/manager/reports.php") }
                }
            }
        }
    }

    private func todoColor(_ k: String) -> Color {
        switch k {
        case "orange": return nx.orange
        case "green": return nx.green
        default: return Color(red: 0.055, green: 0.647, blue: 0.914)
        }
    }

    private func todoIcon(_ k: String) -> String {
        switch k {
        case "doc": return "📝"
        case "phone": return "📱"
        case "chat": return "💬"
        case "tool": return "🧰"
        default: return "•"
        }
    }

    private var todosCard: some View {
        let todos = home.a("todos")
        let total = todos.reduce(0) { $0 + $1.i("count") }
        return dbCard("نیازمند اقدام", "مواردی که منتظر شما هستند", link: nil, {}) {
            VStack(spacing: 0) {
                ForEach(0..<todos.count, id: \.self) { i in
                    let t = todos[i]
                    let n = t.i("count")
                    let col = todoColor(t.s("k"))
                    Button(action: { openTarget(t.s("go")) }) {
                        HStack(spacing: 10) {
                            Text(todoIcon(t.s("icon"))).font(.system(size: 18))
                                .frame(width: 38, height: 38)
                                .background(col.opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.s("title")).font(.system(size: 14, weight: .semibold)).foregroundColor(nx.text)
                                Text(t.s("sub")).font(.system(size: 11)).foregroundColor(nx.muted)
                            }
                            Spacer(minLength: 6)
                            Text(Fa.n(n)).font(.system(size: 12, weight: .bold))
                                .foregroundColor(n > 0 ? .white : nx.muted)
                                .padding(.horizontal, 12).padding(.vertical, 3)
                                .background(n > 0 ? col : nx.card2)
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 8)
                        .opacity(n == 0 ? 0.55 : 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                if total == 0 {
                    Text("✓ همه‌چیز مرتب است؛ کاری منتظر شما نیست").font(.system(size: 12)).foregroundColor(nx.green)
                        .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - منوی ≡ (بخش‌های سایت)

    private var menuSheet: some View {
        let items: [(String, String, String)] = [
            ("person.3.fill", "کارکنان", "/manager/employees.php"),
            ("building.2.fill", "پروژه‌ها", "/manager/projects.php"),
            ("checklist", "وظایف", "/manager/tasks.php"),
            ("banknote.fill", "حقوق و دستمزد", "/manager/payroll.php"),
            ("bubble.left.and.bubble.right.fill", "پیام‌ها", "/manager/messages.php"),
            ("lifepreserver", "پشتیبانی", "/manager/support.php"),
            ("creditcard.fill", "اشتراک‌ها", "/manager/subscriptions.php"),
            ("gearshape.fill", "تنظیمات کسب‌وکار", "/manager/business_settings.php"),
        ]
        return NavigationView {
            List {
                ForEach(0..<items.count, id: \.self) { i in
                    Button(action: {
                        menuOpen = false
                        let p = items[i].2
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openWeb(p) }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: items[i].0).foregroundColor(nx.blue).frame(width: 28)
                            Text(items[i].1).foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(home.s("company_name").isEmpty ? "منو" : home.s("company_name"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("بستن") { menuOpen = false } }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
