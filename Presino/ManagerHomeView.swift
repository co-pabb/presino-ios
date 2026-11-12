import SwiftUI

/// صفحه‌ی اول مدیر: وضعیت امروز شرکت، حاضرین، درخواست‌های در انتظار و میان‌برها
struct ManagerHomeView: View {
    @ObservedObject var state = AppState.shared
    let openWeb: (String) -> Void
    let openNotifications: () -> Void

    init(openWeb: @escaping (String) -> Void, openNotifications: @escaping () -> Void) {
        self.openWeb = openWeb
        self.openNotifications = openNotifications
    }

    private var home: JSON { return state.home }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                banners
                statsGrid
                pendingCard
                presentCard
                linksGrid
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .refreshable { await state.reload() }
    }

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
        let wd = home.s("weekday")
        let day = home.s("today_jalali")
        if wd.isEmpty { return day }
        return wd + " " + day
    }

    @ViewBuilder private var banners: some View {
        if let m = state.message {
            Banner(text: m, icon: "info.circle.fill", color: Brand.blue)
        }
        if state.offline {
            Banner(text: "اینترنت قطع است؛ آخرین اطلاعات ذخیره‌شده نمایش داده می‌شود.", icon: "wifi.slash", color: Brand.orange)
        }
    }

    private var statsGrid: some View {
        let st = home.o("stats")
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(title: "حاضر الان", value: "\(st.i("present_now"))", icon: "person.fill.checkmark", tint: Brand.green)
            StatTile(title: "غایب / خارج", value: "\(st.i("absent_now"))", icon: "person.fill.xmark", tint: Brand.red)
            StatTile(title: "درخواست در انتظار", value: "\(st.i("pending_requests"))", icon: "tray.full.fill", tint: Brand.orange)
            StatTile(title: "کل کارکنان", value: "\(st.i("total_employees"))", icon: "person.3.fill", tint: Brand.blue)
        }
    }

    @ViewBuilder private var pendingCard: some View {
        let list = home.a("pending_list")
        if !list.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("درخواست‌های در انتظار").font(.subheadline.bold())
                        Spacer()
                        Button("همه") { openWeb("/manager/requests.php") }.font(.footnote)
                    }
                    ForEach(Array(list.prefix(5).enumerated()), id: \.offset) { _, p in
                        RowItem(icon: "📝", title: p.s("name"), sub: p.s("type"), badge: p.s("ago"), tint: Brand.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder private var presentCard: some View {
        let list = home.a("present")
        if !list.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("حاضرین الان").font(.subheadline.bold())
                    ForEach(Array(list.prefix(8).enumerated()), id: \.offset) { _, p in
                        RowItem(icon: "🟢", title: p.s("name"), sub: p.s("place"), badge: "از " + p.s("since"), tint: Brand.green)
                    }
                    if list.count > 8 {
                        Text("و \(list.count - 8) نفر دیگر").font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var linksGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            LinkTile(title: "کارکنان", icon: "person.3.fill") { openWeb("/manager/employees.php") }
            LinkTile(title: "درخواست‌ها", icon: "tray.full.fill", badge: home.o("stats").i("pending_requests")) { openWeb("/manager/requests.php") }
            LinkTile(title: "گزارش‌ها", icon: "chart.bar.fill") { openWeb("/manager/reports.php") }
            LinkTile(title: "پروژه‌ها", icon: "building.2.fill") { openWeb("/manager/projects.php") }
            LinkTile(title: "حقوق و دستمزد", icon: "banknote.fill") { openWeb("/manager/payroll.php") }
            LinkTile(title: "پیام‌ها", icon: "bubble.left.and.bubble.right.fill", badge: home.i("pending_msg_replies")) { openWeb("/manager/messages.php") }
        }
    }
}
