import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if Demo.on { Demo.install() }      // فقط شبیه‌ساز (اسکرین‌شات خودکار)
        BackgroundJobs.register()      // باید قبل از پایان راه‌اندازی ثبت شود
        NetWatcher.shared.start()
        // اگر iOS برنامه را به‌خاطر رویداد ژئوفنس در پس‌زمینه بیدار کرده باشد، همین‌جا سرویس‌ها دوباره راه می‌افتند
        GeofenceService.shared.start()
        if Session.token != nil {
            Task { await RouteTracker.shared.refresh() }
        }

        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = MainTabController()
        w.makeKeyAndVisible()
        window = w
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        GeofenceService.shared.onForeground()
        AppState.shared.foreground()
        AppLock.shared.didBecomeActive()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AppState.shared.background()
        AppLock.shared.didEnterBackground()
        BackgroundJobs.schedule()
    }

    // اعلان وقتی برنامه باز است هم روی صفحه (بنر + صدا) نشان داده می‌شود
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // لمس اعلان ← رفتن به بخش مربوطه
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let target = response.notification.request.content.userInfo["target"] as? String ?? ""
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .presinoOpenTarget, object: nil, userInfo: ["target": target])
        }
        completionHandler()
    }
}
