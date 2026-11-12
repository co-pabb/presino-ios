import Foundation
import Combine
import CoreLocation
import UserNotifications
import UIKit

/// وضعیت مجوزها. برای کارمند، دسترسی به موقعیت و روشن بودن GPS اجباری است
/// (بدون آن صفحه‌ی «مجوز لازم است» با دکمه‌ی رفتن به تنظیمات نشان داده می‌شود). مدیر هرگز برای موقعیت مزاحم نمی‌شود.
final class PermissionState: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = PermissionState()

    @Published var location: CLAuthorizationStatus = .notDetermined
    @Published var servicesOn = true
    @Published var notif: UNAuthorizationStatus = .notDetermined

    private let mgr = CLLocationManager()

    override init() {
        super.init()
        mgr.delegate = self
        location = mgr.authorizationStatus
    }

    func refresh() {
        let st = mgr.authorizationStatus
        DispatchQueue.global().async {
            let on = CLLocationManager.locationServicesEnabled()
            UNUserNotificationCenter.current().getNotificationSettings { s in
                DispatchQueue.main.async {
                    self.location = st
                    self.servicesOn = on
                    self.notif = s.authorizationStatus
                }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
    }

    /// کارمندی که موقعیتش رد شده یا GPS گوشی خاموش است
    var blocking: Bool {
        guard Session.token != nil, Session.isEmployee else { return false }
        return !servicesOn || location == .denied || location == .restricted
    }

    /// فقط «هنگام استفاده» داده شده؛ برای خروج/ورود خودکار و ثبت مسیر در پس‌زمینه «همیشه» لازم است
    var wantsAlways: Bool {
        guard Session.token != nil, Session.isEmployee else { return false }
        return location == .authorizedWhenInUse
    }

    var notifDenied: Bool { return notif == .denied }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}
