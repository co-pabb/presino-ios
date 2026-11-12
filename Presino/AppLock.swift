import UIKit
import LocalAuthentication

/// قفل برنامه (اختیاری) با Face ID / Touch ID / رمز گوشی: بعد از ۳۰ ثانیه در پس‌زمینه یا هنگام باز شدن برنامه
final class AppLock {
    static let shared = AppLock()

    static var enabled: Bool {
        get { return UserDefaults.standard.bool(forKey: "lock.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "lock.enabled") }
    }

    private var window: UIWindow?
    private var backgroundAt: Date?
    private var firstActivation = true
    private var authenticating = false

    func didEnterBackground() {
        backgroundAt = Date()
    }

    func didBecomeActive() {
        let first = firstActivation
        firstActivation = false
        guard AppLock.enabled, Session.token != nil else { return }
        if window != nil {
            authenticate()
            return
        }
        var need = first
        if let t = backgroundAt, Date().timeIntervalSince(t) > 30 { need = true }
        if need { show() }
    }

    private func show() {
        let vc = UIViewController()
        vc.view.backgroundColor = UIColor.systemBackground
        let label = UILabel()
        label.text = "Presino\nبرنامه قفل است"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = UIFont.boldSystemFont(ofSize: 22)
        label.translatesAutoresizingMaskIntoConstraints = false
        let button = UIButton(type: .system)
        button.setTitle("باز کردن قفل", for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        vc.view.addSubview(label)
        vc.view.addSubview(button)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor, constant: -40),
            button.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 28),
        ])
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.windowLevel = UIWindow.Level.alert + 1
        w.rootViewController = vc
        w.makeKeyAndVisible()
        window = w
        authenticate()
    }

    @objc private func retryTapped() {
        authenticate()
    }

    private func authenticate() {
        if authenticating { return }
        authenticating = true
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // گوشی رمز/Face ID ندارد؛ قفل بی‌معنی است
            authenticating = false
            AppLock.enabled = false
            hide()
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "باز کردن قفل Presino") { ok, _ in
            DispatchQueue.main.async {
                self.authenticating = false
                if ok { self.hide() }
            }
        }
    }

    private func hide() {
        window?.isHidden = true
        window = nil
    }
}
