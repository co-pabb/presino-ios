import Foundation
import CoreLocation
import UIKit

/// ماژول «مسیر و موقعیت کارمندان» — سمت اپ iPhone (همان منطق اپ اندروید):
///  • فقط بین «ثبت ورود» و «ثبت خروج» و فقط وقتی مدیر فعال کرده کار می‌کند (سرور تصمیم می‌گیرد: active).
///  • نقطه‌ها در گوشی جمع می‌شوند و دسته‌ای ارسال می‌شوند؛ اگر اینترنت نبود برای دور بعد می‌مانند.
///  • iOS در حین ثبت مسیر نوار آبی «برنامه از موقعیت شما استفاده می‌کند» را نشان می‌دهد (شفافیت با کارمند).
final class RouteTracker: NSObject, CLLocationManagerDelegate {
    static let shared = RouteTracker()

    private let mgr = CLLocationManager()
    private let ud = UserDefaults.standard
    private var buffer: [JSON] = []
    private var lastUpload = Date.distantPast
    private var lastAccepted = Date.distantPast
    private var uploadEvery: TimeInterval = 900
    private var minGap: TimeInterval = 150
    private var running = false
    private var uploading = false

    override init() {
        super.init()
        mgr.delegate = self
        mgr.pausesLocationUpdatesAutomatically = false
        mgr.allowsBackgroundLocationUpdates = true
        mgr.showsBackgroundLocationIndicator = true
        mgr.activityType = .otherNavigation
        if let s = ud.string(forKey: "rt.buf"),
           let arr = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [JSON] {
            buffer = arr
        }
    }

    /// وضعیت را از سرور می‌گیرد؛ اگر ثبت مسیر فعال بود شروع و در غیر این صورت متوقف می‌کند
    func refresh() async {
        guard Session.token != nil, !Session.isManager else {
            DispatchQueue.main.async { self.stop() }
            return
        }
        guard let r = await API.call("route_tracking.php"), r.status == 200 else { return }
        let active = r.json.b("active")
        let p = r.json.o("params")
        DispatchQueue.main.async {
            if active {
                let iv = p.i("interval_sec")
                let dist = p.i("min_distance_m")
                let up = p.i("upload_every_sec")
                self.start(interval: iv > 0 ? iv : 300, dist: dist > 0 ? dist : 150,
                           high: p.s("accuracy") == "high", upload: up > 0 ? up : 900)
            } else {
                self.stop()
            }
        }
    }

    private func start(interval: Int, dist: Int, high: Bool, upload: Int) {
        let st = mgr.authorizationStatus
        guard st == .authorizedAlways || st == .authorizedWhenInUse else { return }
        minGap = TimeInterval(max(interval, 10)) / 2
        uploadEvery = TimeInterval(max(upload, 30))
        mgr.distanceFilter = CLLocationDistance(max(dist, 5))
        mgr.desiredAccuracy = high ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        if !running {
            running = true
            lastUpload = Date()
        }
        mgr.startUpdatingLocation()
    }

    func stop() {
        if running { uploadNow() }
        running = false
        mgr.stopUpdatingLocation()
    }

    func reset() {
        DispatchQueue.main.async {
            self.running = false
            self.mgr.stopUpdatingLocation()
            self.buffer.removeAll()
            self.ud.removeObject(forKey: "rt.buf")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for l in locations {
            if l.horizontalAccuracy < 0 || l.horizontalAccuracy > 200 { continue }
            if Date().timeIntervalSince(lastAccepted) < minGap { continue }
            lastAccepted = Date()
            let speed = l.speed >= 0 ? l.speed : 0
            let t = Int(l.timestamp.timeIntervalSince1970 * 1000)
            buffer.append(["lat": l.coordinate.latitude, "lng": l.coordinate.longitude,
                           "acc": l.horizontalAccuracy, "spd": speed, "t": t])
        }
        persist()
        if Date().timeIntervalSince(lastUpload) >= uploadEvery || buffer.count >= 200 { uploadNow() }
        BackgroundJobs.wake()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // خطاهای لحظه‌ای (مثلاً سیگنال ضعیف) نادیده گرفته می‌شود؛ ادامه‌ی ثبت با نقطه‌ی بعدی
    }

    private func persist() {
        if buffer.count > 1500 { buffer.removeFirst(buffer.count - 1500) }
        if let d = try? JSONSerialization.data(withJSONObject: buffer), let s = String(data: d, encoding: .utf8) {
            ud.set(s, forKey: "rt.buf")
        }
    }

    private func uploadNow() {
        if uploading || buffer.isEmpty { return }
        uploading = true
        let batch = Array(buffer.prefix(300))
        buffer.removeFirst(batch.count)
        lastUpload = Date()
        persist()
        Task {
            let r = await API.call("route_tracking.php", method: "POST", body: ["action": "points", "points": batch])
            DispatchQueue.main.async {
                self.uploading = false
                if let r = r {
                    if r.status == 409 {
                        // سرور گفت ثبت مسیر فعال نیست (خروج ثبت شده یا غیرفعال شده)
                        self.running = false
                        self.mgr.stopUpdatingLocation()
                    } else if r.status != 200 {
                        self.buffer.insert(contentsOf: batch, at: 0)
                    }
                } else {
                    self.buffer.insert(contentsOf: batch, at: 0)
                }
                self.persist()
            }
        }
    }
}
