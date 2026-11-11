import Foundation
import CoreLocation
import WebKit

/// navigator.geolocation را با موقعیت خودِ برنامه جایگزین می‌کند:
/// دسترسی موقعیت یک‌بار برای کل برنامه پرسیده می‌شود (نه برای هر باز شدنِ سایت) و دقت دقیق درخواست می‌شود.
final class GeoBridge: NSObject, WKScriptMessageHandler, CLLocationManagerDelegate {
    static let shared = GeoBridge()

    weak var webView: WKWebView?
    private let mgr = CLLocationManager()
    private var pending = Set<Int>()
    private var watchers = Set<Int>()
    private var waiting: [(Int, Bool)] = []
    private var askedFull = false

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
    }

    static let shimJS = #"""
    (function () {
      if (window.__presinoGeoInstalled) { return; }
      window.__presinoGeoInstalled = true;
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.presinoGeo;
      if (!h) { return; }
      var seq = 0, cbs = {};
      function post(op, id) { try { h.postMessage({ op: op, id: id }); } catch (e) {} }
      window.__presinoGeoResult = function (id, ok, lat, lng, acc, code, msg) {
        var c = cbs[id];
        if (!c) { return; }
        if (!c.watch) { delete cbs[id]; }
        if (ok) {
          if (c.s) { try { c.s({ coords: { latitude: lat, longitude: lng, accuracy: acc, altitude: null, altitudeAccuracy: null, heading: null, speed: null }, timestamp: Date.now() }); } catch (e) {} }
        } else {
          if (c.e) { try { c.e({ code: code, message: msg, PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 }); } catch (e) {} }
        }
      };
      var geo = {
        getCurrentPosition: function (s, e, o) { var id = ++seq; cbs[id] = { s: s, e: e, watch: false }; post('get', id); },
        watchPosition: function (s, e, o) { var id = ++seq; cbs[id] = { s: s, e: e, watch: true }; post('watch', id); return id; },
        clearWatch: function (id) { delete cbs[id]; post('clear', id); }
      };
      try {
        Object.defineProperty(navigator, 'geolocation', { value: geo, configurable: true });
      } catch (err) {
        try {
          navigator.geolocation.getCurrentPosition = geo.getCurrentPosition;
          navigator.geolocation.watchPosition = geo.watchPosition;
          navigator.geolocation.clearWatch = geo.clearWatch;
        } catch (err2) {}
      }
    })();
    """#

    // MARK: - پیام از صفحه

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any],
              let op = d["op"] as? String,
              let id = (d["id"] as? NSNumber)?.intValue else { return }
        switch op {
        case "get": handle(id, watch: false)
        case "watch": handle(id, watch: true)
        case "clear":
            watchers.remove(id)
            pending.remove(id)
            if watchers.isEmpty { mgr.stopUpdatingLocation() }
        default: break
        }
    }

    private func handle(_ id: Int, watch: Bool) {
        guard CLLocationManager.locationServicesEnabled() else {
            reply(id, code: 2, "Location services are off")
            return
        }
        switch mgr.authorizationStatus {
        case .denied, .restricted:
            reply(id, code: 1, "Location permission denied")
        case .notDetermined:
            waiting.append((id, watch))
            GeofenceService.shared.requestAuthIfNeeded()
        default:
            begin(id, watch: watch)
        }
    }

    private func begin(_ id: Int, watch: Bool) {
        if mgr.accuracyAuthorization == .reducedAccuracy && !askedFull {
            askedFull = true
            mgr.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "Attendance")
        }
        if let l = mgr.location, l.horizontalAccuracy >= 0, abs(l.timestamp.timeIntervalSinceNow) < 8 {
            reply(id, l)
            if watch { watchers.insert(id); mgr.startUpdatingLocation() }
            return
        }
        if watch {
            watchers.insert(id)
            mgr.startUpdatingLocation()
        } else {
            pending.insert(id)
            mgr.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
                guard let self = self, self.pending.contains(id) else { return }
                self.pending.remove(id)
                self.reply(id, code: 3, "Timeout")
            }
        }
    }

    // MARK: - پاسخ به صفحه

    private func reply(_ id: Int, _ l: CLLocation) {
        let js = "window.__presinoGeoResult&&window.__presinoGeoResult(\(id),true,\(l.coordinate.latitude),\(l.coordinate.longitude),\(max(l.horizontalAccuracy, 0)),0,'')"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    private func reply(_ id: Int, code: Int, _ msg: String) {
        let js = "window.__presinoGeoResult&&window.__presinoGeoResult(\(id),false,0,0,0,\(code),'\(msg)')"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let ids = pending
        pending.removeAll()
        for id in ids { reply(id, l) }
        for id in watchers { reply(id, l) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as NSError).code == CLError.denied.rawValue
        let ids = pending
        pending.removeAll()
        for id in ids { reply(id, code: denied ? 1 : 2, denied ? "Location permission denied" : "Position unavailable") }
        if denied {
            for id in watchers { reply(id, code: 1, "Location permission denied") }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            let w = waiting
            waiting.removeAll()
            for (id, watch) in w { begin(id, watch: watch) }
        case .denied, .restricted:
            let w = waiting
            waiting.removeAll()
            for (id, _) in w { reply(id, code: 1, "Location permission denied") }
        default:
            break
        }
    }
}
