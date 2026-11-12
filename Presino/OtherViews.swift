import SwiftUI
import CoreLocation

/// انتخاب صفحه‌ی اول بر اساس نقش
struct HomeRoot: View {
    @ObservedObject var state = AppState.shared
    let openWeb: (String) -> Void
    let openNotifications: () -> Void

    init(openWeb: @escaping (String) -> Void, openNotifications: @escaping () -> Void) {
        self.openWeb = openWeb
        self.openNotifications = openNotifications
    }

    var body: some View {
        if state.isManager {
            ManagerHomeView(openWeb: openWeb, openNotifications: openNotifications)
        } else {
            EmployeeHomeView(openWeb: openWeb, openNotifications: openNotifications)
        }
    }
}

/// فهرست اعلان‌ها
struct NotificationsView: View {
    @ObservedObject var state = AppState.shared
    let openTarget: (String) -> Void
    @State private var items: [JSON] = []
    @State private var loading = false
    @State private var failed = false

    init(openTarget: @escaping (String) -> Void) {
        self.openTarget = openTarget
    }

    var body: some View {
        NavigationView {
            content
                .navigationTitle("اعلان‌ها")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("خواندن همه") {
                            Task {
                                await NotificationService.shared.markAllRead()
                                await load()
                            }
                        }
                        .font(.footnote)
                    }
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environment(\.layoutDirection, .rightToLeft)
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: failed ? "wifi.slash" : "bell.slash").font(.largeTitle).foregroundColor(.secondary)
                Text(failed ? "اتصال برقرار نیست" : (loading ? "در حال دریافت…" : "اعلانی وجود ندارد")).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(items.enumerated()), id: \.offset) { _, n in
                    row(n)
                }
            }
            .listStyle(PlainListStyle())
            .refreshable { await load() }
        }
    }

    private func row(_ n: JSON) -> some View {
        let unread = !n.b("read")
        return Button(action: { tap(n) }) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(unread ? Brand.blue : Color.clear).frame(width: 9, height: 9).padding(.top, 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(n.s("title")).font(unread ? Font.subheadline.bold() : Font.subheadline).foregroundColor(.primary)
                    if !n.s("body").isEmpty {
                        Text(n.s("body")).font(.footnote).foregroundColor(.secondary).lineLimit(3)
                    }
                    Text(n.s("when")).font(.caption2).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private func tap(_ n: JSON) {
        let id = n.i("id")
        let target = n.s("target")
        Task {
            await NotificationService.shared.markRead(id: id)
            await load()
        }
        if !target.isEmpty { openTarget(target) }
    }

    private func load() async {
        loading = true
        if let list = await NotificationService.shared.list() {
            items = list
            failed = false
        } else {
            failed = true
        }
        loading = false
    }
}

/// تنظیمات: وضعیت مجوزها، یادآورها، قفل برنامه، صف آفلاین و خروج
struct SettingsView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var perm = PermissionState.shared
    let logout: () -> Void
    @State private var remindIn = ReminderService.remindIn
    @State private var remindOut = ReminderService.remindOut
    @State private var lockOn = AppLock.enabled

    init(logout: @escaping () -> Void) {
        self.logout = logout
    }

    var body: some View {
        NavigationView {
            Form {
                accessSection
                if !state.isManager { reminderSection }
                securitySection
                offlineSection
                Section {
                    Button(action: logout) {
                        Text("خروج از حساب").foregroundColor(Brand.red)
                    }
                }
                Section {
                    Text("Presino نسخه \(version)").font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("تنظیمات")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { perm.refresh() }
    }

    private var version: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var locationText: String {
        if !perm.servicesOn { return "GPS گوشی خاموش است" }
        switch perm.location {
        case .authorizedAlways: return "همیشه ✓"
        case .authorizedWhenInUse: return "فقط هنگام استفاده"
        case .denied, .restricted: return "رد شده"
        default: return "پرسیده نشده"
        }
    }

    private var accessSection: some View {
        Section(header: Text("دسترسی‌ها")) {
            if !state.isManager {
                HStack {
                    Text("موقعیت مکانی")
                    Spacer()
                    Text(locationText).foregroundColor(.secondary)
                }
            }
            HStack {
                Text("اعلان‌ها")
                Spacer()
                Text(perm.notifDenied ? "خاموش" : "روشن ✓").foregroundColor(.secondary)
            }
            Button("باز کردن تنظیمات گوشی") { PermissionState.openSettings() }
        }
    }

    private var reminderSection: some View {
        Section(header: Text("یادآورها"), footer: Text("۵ دقیقه قبل و بعد از شروع و پایان شیفت (فقط روزهای کاری).")) {
            Toggle("یادآور ثبت ورود", isOn: $remindIn)
                .onChange(of: remindIn) { v in
                    ReminderService.remindIn = v
                    Task { await state.reload() }
                }
            Toggle("یادآور ثبت خروج", isOn: $remindOut)
                .onChange(of: remindOut) { v in
                    ReminderService.remindOut = v
                    Task { await state.reload() }
                }
        }
    }

    private var securitySection: some View {
        Section(header: Text("امنیت")) {
            Toggle("قفل برنامه با Face ID / رمز گوشی", isOn: $lockOn)
                .onChange(of: lockOn) { v in
                    if v {
                        Task {
                            let ok = await BiometricAuth.confirm(reason: "فعال‌سازی قفل Presino")
                            AppLock.enabled = ok
                            lockOn = ok
                        }
                    } else {
                        AppLock.enabled = false
                    }
                }
        }
    }

    private var offlineSection: some View {
        Section(header: Text("حالت آفلاین")) {
            HStack {
                Text("ثبت‌های در انتظار ارسال")
                Spacer()
                Text("\(state.queued)").foregroundColor(.secondary)
            }
            if state.queued > 0 {
                Button("ارسال اکنون") { Task { _ = await OfflineQueue.shared.flush() } }
            }
        }
    }
}

/// صفحه‌ی «مجوز لازم است» برای کارمندی که موقعیت را رد کرده یا GPS را خاموش کرده
struct PermissionGateView: View {
    @ObservedObject var perm = PermissionState.shared

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "location.slash.fill").font(.system(size: 54)).foregroundColor(Brand.red)
            Text("دسترسی موقعیت لازم است").font(.title3.bold())
            Text(perm.servicesOn
                 ? "ثبت ورود و خروج به موقعیت شما نیاز دارد. دسترسی «موقعیت مکانی» Presino را در تنظیمات گوشی روی «همیشه» (یا حداقل «هنگام استفاده») بگذارید و موقعیت دقیق را روشن کنید."
                 : "GPS (سرویس‌های موقعیت) گوشی خاموش است. آن را از تنظیمات گوشی روشن کنید.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 28)
            Button(action: { PermissionState.openSettings() }) {
                Text("باز کردن تنظیمات")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
    }
}
