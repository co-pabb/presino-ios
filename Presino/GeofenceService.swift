import Foundation
import CoreLocation
import UserNotifications
import UIKit

private enum K {
    static let autoOut = "gf.autoOut"
    static let checkedIn = "gf.checkedIn"
    static let exitAt = "gf.exitAt"
    static let tries = "gf.tries"
    static let sig = "gf.sig"
    static let askedAlways = "gf.askedAlways"
    static let askedNotif = "gf.askedNotif"
    static let needReload = "gf.needReload"
}

/// خروج خودکار (همان منطق اپ اندروید):
///  ۱) محدوده‌ی پروژه‌ها (دایره) با ژئوفنس سیستم‌عامل پایش می‌شود؛ حتی وقتی برنامه بسته است iOS آن را بیدار می‌کند.
///  ۲) هنگام «خروج از محدوده» زمان خروج به سرور فرستاده می‌شود و ۳۰ دقیقه بعد یک موقعیت تأییدی؛ تصمیم نهایی با سرور است.
///  ۳) در این ۳۰ دقیقه یک ردیابی بسیار کم‌مصرف (دقت کیلومتر) برنامه را زنده نگه می‌دارد تا تایمر کار کند.
final class GeofenceService: NSObject, CLLocationManagerDelegate {
    static let shared = GeofenceService()

    private let mgr = CLLocationManager()        // ژئوفنس + تغییر قابل‌توجه + موقعیت یک‌باره
    private let keepAlive = CLLocationManager()  // فقط برای زنده ماندن برنامه تا زمان بررسی خروج
    private let ud = UserDefaults.standard

    private enum Purpose { case exit, enter, check }
    private var pending: [Purpose] = []
    private var exitTimer: Timer?
    private var bg: UIBackgroundTaskIdentifier = .invalid
    private var checkInFlight = false

    private struct Fence {
        let id: Int
        let lat: Double
        let lng: Double
        let radius: Double
    }

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        mgr.pausesLocationUpdatesAutomatically = false
        mgr.allowsBackgroundLocationUpdates = true
        mgr.showsBackgroundLocationIndicator = false

        keepAlive.delegate = self
        keepAlive.desiredAccuracy = kCLLocationAccuracyKilometer
        keepAlive.distanceFilter = 500
        keepAlive.pausesLocationUpdatesAutomatically = false
        keepAlive.allowsBackgroundLocationUpdates = true
        keepAlive.showsBackgroundLocationIndicator = false
    }

    // MARK: - چرخه‌ی برنامه

    /// هنگام اجرای برنامه (و بیدار شدن در پس‌زمینه با رویداد موقعیت) و بعد از گرفتن توکن صدا زده می‌شود.
    func start() {
        guard Session.token != nil else { return }
        requestNotifAuthOnce()
        requestAuthIfNeeded()
        Task { await self.refresh() }
        if ud.double(forKey: K.exitAt) > 0 { scheduleExitCheck() }
    }

    func onForeground() {
        guard Session.token != nil else { return }
        Task { await self.refresh() }
        let at = ud.double(forKey: K.exitAt)
        if at > 0 {
            if Date().timeIntervalSince1970 - at > 12 * 3600 { clearExit() } else { scheduleExitCheck() }
        }
        if ud.bool(forKey: K.needReload) {
            ud.set(false, forKey: K.needReload)
            NotificationCenter.default.post(name: .presinoReload, object: nil)
        }
    }

    /// خروج کاربر از حساب
    func stopAll() {
        DispatchQueue.main.async {
            for r in self.mgr.monitoredRegions { self.mgr.stopMonitoring(for: r) }
            self.mgr.stopMonitoringSignificantLocationChanges()
            self.clearExit()
            for k in [K.autoOut, K.checkedIn, K.sig] { self.ud.removeObject(forKey: k) }
        }
    }

    // MARK: - مجوزها

    func requestAuthIfNeeded() {
        DispatchQueue.main.async {
            switch self.mgr.authorizationStatus {
            case .notDetermined:
                self.mgr.requestWhenInUseAuthorization()
            case .authorizedWhenInUse:
                if !self.ud.bool(forKey: K.askedAlways) {
                    self.ud.set(true, forKey: K.askedAlways)
                    self.mgr.requestAlwaysAuthorization()
                }
            default:
                break
            }
        }
    }

    private func requestNotifAuthOnce() {
        if ud.bool(forKey: K.askedNotif) { return }
        ud.set(true, forKey: K.askedNotif)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === mgr else { return }
        if manager.authorizationStatus == .authorizedWhenInUse { requestAuthIfNeeded() }
        Task { await self.refresh() }
    }

    // MARK: - دریافت تنظیمات از سرور

    private func refresh() async {
        guard let r = await API.call("employee_home.php"), r.status == 200,
              (r.json["success"] as? Bool) == true else { return }
        let emp = r.json["employee"] as? [String: Any] ?? [:]
        let autoOut = (emp["auto_checkout"] as? Bool) ?? false
        let bypass = (emp["bypass_location"] as? Bool) ?? false
        let checkedIn = (r.json["next_action"] as? String) == "check_out"

        var fences: [Fence] = []
        for p in (r.json["projects"] as? [[String: Any]] ?? []) {
            guard (p["geofence_type"] as? String) == "circle",
                  let id = (p["id"] as? NSNumber)?.intValue,
                  let lat = (p["lat"] as? NSNumber)?.doubleValue,
                  let lng = (p["lng"] as? NSNumber)?.doubleValue,
                  let rad = (p["radius"] as? NSNumber)?.doubleValue else { continue }
            fences.append(Fence(id: id, lat: lat, lng: lng, radius: rad))
        }

        await MainActor.run {
            self.ud.set(autoOut && !bypass, forKey: K.autoOut)
            self.ud.set(checkedIn, forKey: K.checkedIn)
            if !checkedIn && self.ud.double(forKey: K.exitAt) > 0 { self.clearExit() }
            self.applyFences(fences)
        }
    }

    private func applyFences(_ fences: [Fence]) {
        let want = ud.bool(forKey: K.autoOut)
        let always = mgr.authorizationStatus == .authorizedAlways
        guard want, always, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            for r in mgr.monitoredRegions { mgr.stopMonitoring(for: r) }
            mgr.stopMonitoringSignificantLocationChanges()
            ud.removeObject(forKey: K.sig)
            return
        }
        // iOS بیشینه ۲۰ ناحیه را هم‌زمان پایش می‌کند
        let list = Array(fences.prefix(20))
        let sig = list.map { "\($0.id):\($0.lat):\($0.lng):\(Int($0.radius))" }.joined(separator: "|")
        // تغییر قابل‌توجه موقعیت: بعد از بسته شدن برنامه هم iOS آن را دوباره بیدار می‌کند
        mgr.startMonitoringSignificantLocationChanges()
        if sig == ud.string(forKey: K.sig), !mgr.monitoredRegions.isEmpty { return }
        for r in mgr.monitoredRegions { mgr.stopMonitoring(for: r) }
        for f in list {
            let radius = min(max(f.radius, 100), mgr.maximumRegionMonitoringDistance)
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: f.lat, longitude: f.lng),
                                          radius: radius, identifier: "p\(f.id)")
            region.notifyOnEntry = true
            region.notifyOnExit = true
            mgr.startMonitoring(for: region)
        }
        ud.set(sig, forKey: K.sig)
    }

    // MARK: - رویدادهای ژئوفنس

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier.hasPrefix("p"), ud.bool(forKey: K.autoOut) else { return }
        beginBG()
        Task {
            await self.refresh()   // اگر شبکه نبود، آخرین وضعیتِ ذخیره‌شده می‌ماند
            guard self.ud.bool(forKey: K.checkedIn) else { self.endBG(); return }
            await MainActor.run {
                if self.ud.double(forKey: K.exitAt) == 0 {
                    self.ud.set(Date().timeIntervalSince1970, forKey: K.exitAt)
                    self.ud.set(0, forKey: K.tries)
                }
                self.request(.exit)
                self.scheduleExitCheck()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("p"), ud.double(forKey: K.exitAt) > 0 else { return }
        clearExit()          // قبل از ۳۰ دقیقه برگشت: هیچ خروجی ثبت نمی‌شود
        beginBG()
        request(.enter)
    }

    // MARK: - موقعیت

    private func request(_ p: Purpose) {
        pending.append(p)
        mgr.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        if manager === keepAlive {
            dueCheckIfNeeded()
            return
        }
        let ps = pending
        pending.removeAll()
        for p in ps { send(p, loc) }
        if ps.isEmpty { dueCheckIfNeeded() }   // تغییر قابل‌توجه موقعیت
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === mgr else { return }
        let ps = pending
        pending.removeAll()
        for p in ps {
            if p == .check {
                checkInFlight = false
                if ud.integer(forKey: K.tries) == 0 {
                    notify("📍 موقعیت شما قابل تشخیص نیست",
                           "برای ثبت خروج خودکار موقعیت لازم است؛ دسترسی موقعیت را روشن کنید. تا آن موقع خروجی ثبت نمی‌شود.")
                }
                retry(after: 15 * 60)
            }
            endBG()
        }
    }

    private func send(_ p: Purpose, _ loc: CLLocation) {
        let event: String
        var at: TimeInterval = 0
        switch p {
        case .exit: event = "exit"; at = ud.double(forKey: K.exitAt)
        case .enter: event = "enter"
        case .check: event = "check"; at = ud.double(forKey: K.exitAt)
        }
        var body: [String: Any] = [
            "latitude": loc.coordinate.latitude,
            "longitude": loc.coordinate.longitude,
            "event": event,
        ]
        if loc.horizontalAccuracy >= 0 { body["accuracy"] = loc.horizontalAccuracy }
        if at > 0 { body["event_time"] = GeofenceService.format(at) }
        Task {
            let r = await API.call("location_ping.php", method: "POST", body: body)
            await MainActor.run { self.handle(p, r) }
        }
    }

    private func handle(_ p: Purpose, _ r: APIResult?) {
        guard p == .check else { endBG(); return }
        checkInFlight = false
        guard let r = r, r.status == 200 else { retry(after: 10 * 60); endBG(); return }
        let st = (r.json["status"] as? String) ?? ""
        switch st {
        case "auto_checked_out":
            let left = (r.json["left_at"] as? String) ?? ""
            notify("✅ خروج خودکار ثبت شد",
                   "ساعت \(left) از محدوده خارج شدید و بیش از ۳۰ دقیقه برنگشتید؛ خروج با همان ساعت ثبت شد.")
            ud.set(true, forKey: K.needReload)
            NotificationCenter.default.post(name: .presinoReload, object: nil)
            clearExit()
        case "inside", "not_checked_in", "auto_disabled", "unsupported_geofence", "bypass", "exit_time_unknown":
            clearExit()
        default:   // low_accuracy / outside_pending: بعداً دوباره بررسی می‌شود
            retry(after: 5 * 60)
        }
        endBG()
    }

    // MARK: - بررسی ۳۰ دقیقه بعد

    private func scheduleExitCheck() {
        let at = ud.double(forKey: K.exitAt)
        guard at > 0 else { return }
        keepAlive.startUpdatingLocation()
        let due = Date(timeIntervalSince1970: at + Config.autoSeconds + 20)
        scheduleTimer(at: max(due, Date().addingTimeInterval(3)))
    }

    private func scheduleTimer(at date: Date) {
        exitTimer?.invalidate()
        let t = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in self?.runCheck() }
        RunLoop.main.add(t, forMode: .common)
        exitTimer = t
    }

    private func dueCheckIfNeeded() {
        let at = ud.double(forKey: K.exitAt)
        guard at > 0, Date().timeIntervalSince1970 >= at + Config.autoSeconds else { return }
        runCheck()
    }

    private func runCheck() {
        guard ud.bool(forKey: K.autoOut), ud.double(forKey: K.exitAt) > 0 else { clearExit(); return }
        guard !checkInFlight else { return }
        checkInFlight = true
        beginBG()
        request(.check)
    }

    private func retry(after seconds: TimeInterval) {
        let n = ud.integer(forKey: K.tries) + 1
        ud.set(n, forKey: K.tries)
        if n >= 8 { clearExit(); return }   // حداکثر حدود ۲ ساعت تلاش
        scheduleTimer(at: Date().addingTimeInterval(seconds))
    }

    private func clearExit() {
        ud.removeObject(forKey: K.exitAt)
        ud.removeObject(forKey: K.tries)
        exitTimer?.invalidate()
        exitTimer = nil
        checkInFlight = false
        keepAlive.stopUpdatingLocation()
        endBG()
    }

    // MARK: - کمکی

    private func beginBG() {
        DispatchQueue.main.async {
            if self.bg != .invalid { return }
            self.bg = UIApplication.shared.beginBackgroundTask(withName: "presino.geofence") {
                self.endBG()
            }
        }
    }

    private func endBG() {
        DispatchQueue.main.async {
            if self.bg != .invalid {
                UIApplication.shared.endBackgroundTask(self.bg)
                self.bg = .invalid
            }
        }
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private static func format(_ t: TimeInterval) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}
