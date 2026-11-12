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
    private var managerLayout = false
    private var homeVC: UIViewController!
    private var notifVC: UIViewController!
    private var moreVC: UIViewController!
    private var modalWeb: UIViewController?

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
            openNotifications: { [weak self] in self?.showNotifications() },
            openTarget: { [weak self] t in self?.openTarget(t) },
            openSettings: { [weak self] in self?.showSettings() }))
        home.tabBarItem = UITabBarItem(title: "خانه", image: UIImage(systemName: "house.fill"), tag: 0)
        homeVC = home

        web.tabBarItem = UITabBarItem(title: "بخش‌ها", image: UIImage(systemName: "square.grid.2x2.fill"), tag: 1)

        let notif = UIHostingController(rootView: NotificationsView(openTarget: { [weak self] t in self?.openTarget(t) }))
        notif.tabBarItem = UITabBarItem(title: "اعلان‌ها", image: UIImage(systemName: "bell.fill"), tag: 2)
        notifVC = notif

        let more = UIHostingController(rootView: SettingsView(logout: { [weak self] in self?.logout() }))
        more.tabBarItem = UITabBarItem(title: "تنظیمات", image: UIImage(systemName: "gearshape.fill"), tag: 3)
        moreVC = more

        viewControllers = [home, web, notif, more]

        NotificationCenter.default.addObserver(self, selector: #selector(sessionChanged), name: .presinoSession, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openPathNote(_:)), name: .presinoOpenPath, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openTargetNote(_:)), name: .presinoOpenTarget, object: nil)

        // مجوز موقعیت کارمند اجباری است؛ با هر تغییر وضعیت، صفحه‌ی «مجوز لازم است» نشان داده یا برداشته می‌شود
        PermissionState.shared.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateGate() } }
            .store(in: &cancellables)
        AppState.shared.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateGate(); self?.configureTabs(); self?.updateBadges() } }
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
        configureTabs()
        if loggedIn {
            if !wasLoggedIn {
                selectedIndex = 0
                if !initial { AppState.shared.afterLogin() }
            }
        } else {
            selectedIndex = 1
            dismissGate()
            if modalWeb != nil { modalWeb?.dismiss(animated: false); modalWeb = nil }
            if !initial { web.resync() }
        }
        wasLoggedIn = loggedIn
        updateGate()
    }

    // MARK: - ناوبری

    func openWeb(_ path: String) {
        if managerLayout {
            presentWeb(path)
            return
        }
        selectedIndex = 1
        web.open(path: path)
    }

    private func openTarget(_ target: String) {
        dismissSheets()
        if managerLayout {
            switch target {
            case "tab:0": selectedIndex = 0; return
            case "tab:1", "more:mgrRequests": selectedIndex = 1; return
            case "more:ai": selectedIndex = 4; return
            case "more:notifications": showNotifications(); return
            default: break
            }
        }
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
        dismissSheets()
        if managerLayout {
            presentWeb("/auth/logout.php")
            return
        }
        selectedIndex = 1
        web.open(path: "/auth/logout.php")
    }

    // MARK: - چیدمان تب‌ها (کارمند: چهار تب؛ مدیر: داشبورد، درخواست‌ها، گزارش، حسابداری، AI مثل اپ اندروید)

    private func makeWeb(_ path: String, _ title: String, _ symbol: String, _ tag: Int) -> WebViewController {
        let w = WebViewController()
        w.startPath = path
        w.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), tag: tag)
        return w
    }

    private func configureTabs() {
        let mgr = Session.token != nil && AppState.shared.isManager
        if mgr == managerLayout && viewControllers != nil && !(viewControllers ?? []).isEmpty { return }
        managerLayout = mgr
        if mgr {
            homeVC.tabBarItem = UITabBarItem(title: "داشبورد", image: UIImage(systemName: "square.grid.2x2.fill"), tag: 0)
            let req = makeWeb("/manager/requests.php", "درخواست‌ها", "tray.full.fill", 1)
            let rep = makeWeb("/manager/reports.php", "گزارش", "chart.bar.fill", 2)
            let acc = makeWeb("/manager/acc_home.php", "حسابداری", "creditcard.fill", 3)
            let ai = makeWeb("/manager/ai.php", "AI", "sparkles", 4)
            viewControllers = [homeVC, req, rep, acc, ai]
        } else {
            homeVC.tabBarItem = UITabBarItem(title: "خانه", image: UIImage(systemName: "house.fill"), tag: 0)
            viewControllers = [homeVC, web, notifVC, moreVC]
            if Session.token == nil { web.open(path: "/?pwa=1") }
        }
        selectedIndex = mgr ? 0 : (Session.token == nil ? 1 : 0)
        updateBadges()
    }

    private func updateBadges() {
        guard managerLayout, let vcs = viewControllers, vcs.count > 1 else { return }
        let st = AppState.shared.home.o("stats")
        let n = st.i("pending_requests") + st.i("pending_device_requests")
        vcs[1].tabBarItem.badgeValue = n > 0 ? Fa.n(n) : nil
    }

    // MARK: - صفحه‌ها و برگه‌ها در حالت مدیر

    private func topPresenter() -> UIViewController {
        var v: UIViewController = self
        while true {
            if let p = v.presentedViewController {
                v = p
            } else if let s = (v as? UITabBarController)?.selectedViewController, let p = s.presentedViewController {
                v = p
            } else {
                break
            }
        }
        return v
    }

    private func dismissSheets() {
        if let m = modalWeb { m.dismiss(animated: false); modalWeb = nil }
        homeVC?.presentedViewController?.dismiss(animated: false)
        if presentedViewController != nil && presentedViewController !== gate { presentedViewController?.dismiss(animated: false) }
    }

    private func presentWeb(_ path: String) {
        dismissSheets()
        let w = WebViewController()
        w.startPath = path
        w.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "بستن", style: .done, target: self, action: #selector(closeModalWeb))
        let nav = UINavigationController(rootViewController: w)
        nav.modalPresentationStyle = .fullScreen
        nav.view.semanticContentAttribute = .forceRightToLeft
        modalWeb = nav
        topPresenter().present(nav, animated: true)
    }

    @objc private func closeModalWeb() {
        modalWeb?.dismiss(animated: true)
        modalWeb = nil
    }

    private func showNotifications() {
        if !managerLayout { selectedIndex = 2; return }
        let vc = UIHostingController(rootView: NotificationsView(openTarget: { [weak self] t in self?.openTarget(t) }))
        topPresenter().present(vc, animated: true)
    }

    private func showSettings() {
        if !managerLayout { selectedIndex = 3; return }
        let vc = UIHostingController(rootView: SettingsView(logout: { [weak self] in self?.logout() }))
        topPresenter().present(vc, animated: true)
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
