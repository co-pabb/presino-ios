import UIKit
import SwiftUI
import Combine

/// قاب اصلی برنامه: چهار تب
///  ۱) خانه (نیتیو؛ کارمند یا مدیر)  ۲) بخش‌ها (همان سایت داخل برنامه)  ۳) اعلان‌ها (نیتیو)  ۴) تنظیمات (نیتیو)
/// تا وقتی کاربر وارد نشده، فقط صفحه‌ی ورودِ وب دیده می‌شود (نوار تب پنهان است).
final class MainTabController: UITabBarController {
    let web = WebViewController()
    private var cancellables = Set<AnyCancellable>()
    private var gate: UIViewController?
    private var wasLoggedIn = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.semanticContentAttribute = .forceRightToLeft
        tabBar.semanticContentAttribute = .forceRightToLeft
        let ap = UITabBarAppearance()
        ap.configureWithDefaultBackground()
        tabBar.standardAppearance = ap
        tabBar.scrollEdgeAppearance = ap

        let home = UIHostingController(rootView: HomeRoot(
            openWeb: { [weak self] p in self?.openWeb(p) },
            openNotifications: { [weak self] in self?.selectedIndex = 2 }))
        home.tabBarItem = UITabBarItem(title: "خانه", image: UIImage(systemName: "house.fill"), tag: 0)

        web.tabBarItem = UITabBarItem(title: "بخش‌ها", image: UIImage(systemName: "square.grid.2x2.fill"), tag: 1)

        let notif = UIHostingController(rootView: NotificationsView(openTarget: { [weak self] t in self?.openTarget(t) }))
        notif.tabBarItem = UITabBarItem(title: "اعلان‌ها", image: UIImage(systemName: "bell.fill"), tag: 2)

        let more = UIHostingController(rootView: SettingsView(logout: { [weak self] in self?.logout() }))
        more.tabBarItem = UITabBarItem(title: "تنظیمات", image: UIImage(systemName: "gearshape.fill"), tag: 3)

        viewControllers = [home, web, notif, more]

        NotificationCenter.default.addObserver(self, selector: #selector(sessionChanged), name: .presinoSession, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openPathNote(_:)), name: .presinoOpenPath, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openTargetNote(_:)), name: .presinoOpenTarget, object: nil)

        // مجوز موقعیت کارمند اجباری است؛ با هر تغییر وضعیت، صفحه‌ی «مجوز لازم است» نشان داده یا برداشته می‌شود
        PermissionState.shared.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateGate() } }
            .store(in: &cancellables)
        AppState.shared.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateGate() } }
            .store(in: &cancellables)

        applySession(initial: true)
        if Demo.on { selectedIndex = Demo.tab }
    }

    // MARK: - وضعیت ورود

    @objc private func sessionChanged() {
        DispatchQueue.main.async {
            AppState.shared.sessionChanged()
            self.applySession(initial: false)
        }
    }

    private func applySession(initial: Bool) {
        let loggedIn = Session.token != nil
        tabBar.isHidden = !loggedIn
        if loggedIn {
            if !wasLoggedIn {
                selectedIndex = 0
                if !initial { AppState.shared.afterLogin() }
            }
        } else {
            selectedIndex = 1
            dismissGate()
            if !initial { web.resync() }
        }
        wasLoggedIn = loggedIn
        updateGate()
    }

    // MARK: - ناوبری

    func openWeb(_ path: String) {
        selectedIndex = 1
        web.open(path: path)
    }

    private func openTarget(_ target: String) {
        if let p = WebRoutes.path(forTarget: target) {
            openWeb(p)
        } else {
            selectedIndex = target == "more:notifications" ? 2 : 0
        }
    }

    @objc private func openPathNote(_ n: Notification) {
        if let p = n.userInfo?["path"] as? String {
            DispatchQueue.main.async { self.openWeb(p) }
        }
    }

    @objc private func openTargetNote(_ n: Notification) {
        let t = n.userInfo?["target"] as? String ?? ""
        DispatchQueue.main.async { self.openTarget(t) }
    }

    private func logout() {
        // خروج از سایت؛ پوسته‌ی وب پس از دیدن آدرس خروج، توکن و داده‌های برنامه را پاک می‌کند
        selectedIndex = 1
        web.open(path: "/auth/logout.php")
    }

    // MARK: - صفحه‌ی مجوز موقعیت

    private func updateGate() {
        if PermissionState.shared.blocking {
            presentGate()
        } else {
            dismissGate()
        }
    }

    private func presentGate() {
        if gate != nil || presentedViewController != nil { return }
        let vc = UIHostingController(rootView: PermissionGateView())
        vc.modalPresentationStyle = .fullScreen
        vc.isModalInPresentation = true
        gate = vc
        present(vc, animated: true)
    }

    private func dismissGate() {
        guard let g = gate else { return }
        gate = nil
        g.dismiss(animated: true)
    }
}
