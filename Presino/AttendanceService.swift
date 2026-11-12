import Foundation
import CoreLocation
import LocalAuthentication

/// گرفتن موقعیت دقیقِ یک‌باره (حداکثر ۱۵ ثانیه صبر)
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let mgr = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation?, Never>?

    func fetch() async -> CLLocation? {
        return await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
            DispatchQueue.main.async {
                self.cont = c
                self.mgr.delegate = self
                self.mgr.desiredAccuracy = kCLLocationAccuracyBest
                self.mgr.requestLocation()
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                    self?.finish(nil)
                }
            }
        }
    }

    private func finish(_ l: CLLocation?) {
        if let c = cont {
            cont = nil
            c.resume(returning: l)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}

/// تأیید هویت با Face ID / Touch ID / رمز گوشی
enum BiometricAuth {
    static func confirm(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                c.resume(returning: ok)
            }
        }
    }
}

enum AttendanceResult {
    case done(String)
    case queued(String)
    case failed(String)
    case needsWeb(String)
}

/// ثبت ورود/خروج دستی با پشتیبانیِ آفلاین (همان قواعد اپ اندروید)
enum AttendanceService {
    static func submit(type: String) async -> AttendanceResult {
        let home = AppState.shared.home
        if home.b("att_face") {
            return .needsWeb("ثبت تردد شما با تأیید چهره انجام می‌شود؛ صفحه‌ی ثبت در بخش‌ها باز می‌شود.")
        }
        DispatchQueue.main.async { AppState.shared.busy = true }

        var bio = false
        if home.b("att_biometric") {
            let reason = type == "check_in" ? "تأیید هویت برای ثبت ورود" : "تأیید هویت برای ثبت خروج"
            let ok = await BiometricAuth.confirm(reason: reason)
            if !ok {
                DispatchQueue.main.async { AppState.shared.busy = false }
                return .failed("تأیید هویت انجام نشد.")
            }
            bio = true
        }

        let bypass = home.o("employee").b("bypass_location")
        let fetcher = LocationFetcher()
        let loc = await fetcher.fetch()
        var projectId: Int? = nil
        if let l = loc { projectId = insideProject(l, home.a("projects")) }

        var body: JSON = ["type": type]
        if let l = loc {
            body["latitude"] = l.coordinate.latitude
            body["longitude"] = l.coordinate.longitude
            if l.horizontalAccuracy >= 0 { body["accuracy"] = l.horizontalAccuracy }
        }
        if let p = projectId { body["project_id"] = p }
        if bio { body["bio"] = true }

        let r = await API.call("employee_attendance.php", method: "POST", body: body)
        DispatchQueue.main.async { AppState.shared.busy = false }

        if let r = r {
            let msg = r.json.s("message")
            if r.status >= 200 && r.status < 300 && r.json.b("success") {
                afterRecorded(type: type)
                return .done(msg.isEmpty ? (type == "check_in" ? "ورود ثبت شد" : "خروج ثبت شد") : msg)
            }
            if r.json.b("face_required") { return .needsWeb(msg) }
            if r.status == 409 { await AppState.shared.reload() }
            if r.status == 401 { return .failed("نشست شما منقضی شده؛ دوباره وارد شوید.") }
            return .failed(msg.isEmpty ? "ثبت انجام نشد؛ دوباره تلاش کنید." : msg)
        }

        // بدون اینترنت: ثبت آفلاین هم باید مثل آنلاین GPS و محدوده‌ی پروژه را رعایت کند
        if !bypass {
            if loc == nil {
                return .failed("موقعیت مکانی دریافت نشد؛ ثبتِ آفلاین بدون GPS ممکن نیست. GPS را روشن کنید و دوباره امتحان کنید.")
            }
            if projectId == nil {
                return .failed("شما خارج از محدوده‌ی پروژه‌های خود هستید؛ ثبتِ آفلاین فقط داخل محدوده‌ی یک پروژه ممکن است.")
            }
        }
        let now = Date()
        var off = body
        off["is_offline"] = true
        off["occurred_at"] = Fmt.dt(now)
        let label = type == "check_in" ? "ثبت ورود" : "ثبت خروج"
        OfflineQueue.shared.enqueue(path: "employee_attendance.php", body: off, label: label)
        let name = projectName(projectId, home.a("projects"))
        let time = Fmt.hm(now)
        AppState.shared.applyLocal(type: type, project: name, time: time)
        ReminderService.cancelToday(after: type)
        return .queued("آفلاین ثبت شد: \(label) در ساعت \(time) داخل گوشی ذخیره شد و به‌محض اتصال به اینترنت به گزارش اضافه می‌شود.")
    }

    private static func afterRecorded(type: String) {
        ReminderService.cancelToday(after: type)
        Task {
            await AppState.shared.reload()
            await RouteTracker.shared.refresh()
            GeofenceService.shared.start()
        }
    }

    private static func insideProject(_ l: CLLocation, _ projects: [JSON]) -> Int? {
        var bestId: Int? = nil
        var bestDist = Double.greatestFiniteMagnitude
        for p in projects {
            guard p.s("geofence_type") == "circle", let lat = p.d("lat"), let lng = p.d("lng") else { continue }
            let rad = p.d("radius") ?? 0
            if rad <= 0 { continue }
            let dist = l.distance(from: CLLocation(latitude: lat, longitude: lng))
            if dist <= rad && dist < bestDist {
                bestDist = dist
                bestId = p.i("id")
            }
        }
        return bestId
    }

    private static func projectName(_ id: Int?, _ projects: [JSON]) -> String {
        guard let id = id else { return "پروژه سیار" }
        for p in projects where p.i("id") == id { return p.s("name") }
        return "-"
    }
}
