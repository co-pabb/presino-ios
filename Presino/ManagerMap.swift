import SwiftUI
import MapKit
import CoreImage
import UIKit

// MARK: - مدل داده‌ی نقشه (همان ساختار map/lists/people در manager_dashboard.php)

struct MapProject {
    let idx: Int
    let name: String
    let city: String
    let avatar: String
    let lat: Double
    let lng: Double
    let count: Int
}

struct MapPerson {
    let id: Int
    let name: String
    let proj: String
    let city: String
    let time: String
    let status: String
    let lat: Double
    let lng: Double
    let inside: Bool
    let photos: [String]
}

struct MapData {
    var projects: [MapProject] = []
    var people: [MapPerson] = []
    var lists: [String: [String]] = [:]
    var info: [String: JSON] = [:]
    var cities: [String] = []

    static func statusOf(_ name: String, inside: Bool?, lists: [String: [String]]) -> String {
        for k in ["leave", "mission", "absent"] {
            if (lists[k] ?? []).contains(name) { return k }
        }
        return inside == true ? "present" : "out"
    }

    static func parse(_ home: JSON) -> MapData {
        var d = MapData()
        let map = home.o("map")
        let listsRaw = home.o("lists")
        for (k, v) in listsRaw {
            d.lists[k] = (v as? [Any] ?? []).compactMap { $0 as? String }
        }
        for p in home.a("people") { d.info[p.s("name")] = p }
        let points = map.a("points")
        var perProj: [String: Int] = [:]
        for p in points where p.b("in") { perProj[p.s("proj"), default: 0] += 1 }
        var cityOfProj: [String: String] = [:]
        for (i, p) in map.a("projects").enumerated() {
            let city = p.s("city").trimmingCharacters(in: .whitespaces)
            cityOfProj[p.s("name")] = city
            d.projects.append(MapProject(idx: i, name: p.s("name"), city: city, avatar: p.s("av"),
                                         lat: p.d("lat") ?? 0, lng: p.d("lng") ?? 0, count: perProj[p.s("name")] ?? 0))
            if !city.isEmpty && !d.cities.contains(city) { d.cities.append(city) }
        }
        for p in points {
            guard let la = p.d("lat"), let ln = p.d("lng") else { continue }
            var photos = (p["pc"] as? [Any] ?? []).compactMap { $0 as? String }
            if photos.isEmpty && !p.s("photo").isEmpty { photos = [p.s("photo")] }
            d.people.append(MapPerson(id: p.i("id"), name: p.s("name"), proj: p.s("proj"), city: cityOfProj[p.s("proj")] ?? "",
                                      time: p.s("time"), status: statusOf(p.s("name"), inside: p.b("in"), lists: d.lists),
                                      lat: la, lng: ln, inside: p.b("in"), photos: photos))
        }
        return d
    }
}

/// فیلترهای نقشه (مثل localStorage وب؛ کلید nx_map_filter_v1)
struct MapFilter: Equatable {
    var pj = true
    var pp = true
    var st: [String: Bool] = [:]
    var cityOff: Set<String> = []

    func on(_ k: String) -> Bool { return st[k] ?? true }
    func cityOK(_ c: String) -> Bool { return c.isEmpty || !cityOff.contains(c) }
    func showPj(_ p: MapProject) -> Bool { return pj && cityOK(p.city) }
    func showPp(_ p: MapPerson) -> Bool { return pp && on(p.status) && cityOK(p.city) }
    var active: Bool { return !pj || StatusKeys.contains(where: { !on($0.0) }) || !cityOff.isEmpty }

    private static let key = "nx_map_filter_v1"

    static func load() -> MapFilter {
        var f = MapFilter()
        guard let o = UserDefaults.standard.dictionary(forKey: key) else { return f }
        if let v = o["pj"] as? Bool { f.pj = v }
        if let v = o["pp"] as? Bool { f.pp = v }
        for (k, _) in StatusKeys { if let v = o[k] as? Bool { f.st[k] = v } }
        if let c = o["cityOff"] as? [String] { f.cityOff = Set(c) }
        return f
    }

    func save() {
        var o: [String: Any] = ["pj": pj, "pp": pp, "cityOff": Array(cityOff)]
        for (k, _) in StatusKeys { o[k] = on(k) }
        UserDefaults.standard.set(o, forKey: MapFilter.key)
    }
}

// MARK: - آدرس کاشی نقشه (همان نقشه‌ی سایت از map_config.php)

enum MapConfigStore {
    private static let key = "map.tile"

    static var cached: String {
        return UserDefaults.standard.string(forKey: key) ?? "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    }

    static var attribution: String {
        return UserDefaults.standard.string(forKey: "map.attr") ?? "© OpenStreetMap"
    }

    static func refresh() async {
        guard let r = await API.call("map_config.php"), r.status == 200 else { return }
        let u = r.json.s("street_url")
        if !u.isEmpty { UserDefaults.standard.set(u, forKey: key) }
        let a = r.json.s("street_attr")
        if !a.isEmpty { UserDefaults.standard.set(a, forKey: "map.attr") }
    }

    /// MapKit فقط {x}{y}{z}{scale} را می‌شناسد
    static func template(_ raw: String) -> String {
        return raw.replacingOccurrences(of: "{s}", with: "a").replacingOccurrences(of: "{r}", with: "")
            .replacingOccurrences(of: "{ratio}", with: "")
    }
}

// MARK: - کاشی با فیلتر تم تاریک وب

final class StyledTileOverlay: MKTileOverlay {
    let dark: Bool
    private static let ctx = CIContext(options: nil)

    init(template: String, dark: Bool) {
        self.dark = dark
        super.init(urlTemplate: template)
        canReplaceMapContent = true
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let dk = self.dark
        super.loadTile(at: path) { data, err in
            guard dk, let data = data, let ci = CIImage(data: data), let f = CIFilter(name: "CIColorMatrix") else {
                result(data, err)
                return
            }
            let m = DarkTile.matrix
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: CGFloat(m[0]), y: CGFloat(m[4]), z: CGFloat(m[8]), w: 0), forKey: "inputRVector")
            f.setValue(CIVector(x: CGFloat(m[1]), y: CGFloat(m[5]), z: CGFloat(m[9]), w: 0), forKey: "inputGVector")
            f.setValue(CIVector(x: CGFloat(m[2]), y: CGFloat(m[6]), z: CGFloat(m[10]), w: 0), forKey: "inputBVector")
            f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            f.setValue(CIVector(x: CGFloat(m[3]), y: CGFloat(m[7]), z: CGFloat(m[11]), w: 0), forKey: "inputBiasVector")
            if let out = f.outputImage,
               let cg = StyledTileOverlay.ctx.createCGImage(out, from: ci.extent),
               let png = UIImage(cgImage: cg).pngData() {
                result(png, nil)
            } else {
                result(data, err)
            }
        }
    }
}

// MARK: - نشانگرها

final class PjAnn: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    let pj: MapProject
    var photo: UIImage?

    init(_ p: MapProject) {
        pj = p
        coordinate = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
        title = p.name
        subtitle = p.count > 0 ? Fa.n(p.count) + " نفر حاضر" : nil
    }
}

final class PpAnn: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    let pp: MapPerson
    var photo: UIImage?

    init(_ p: MapPerson) {
        pp = p
        coordinate = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
        title = p.name
        let label = StatusKeys.first(where: { $0.0 == p.status })?.1 ?? ""
        var parts = [label]
        if !p.proj.isEmpty { parts.append(p.proj) }
        if !p.time.isEmpty { parts.append(Fa.digits(p.time)) }
        subtitle = parts.joined(separator: " · ")
    }
}

enum MapArt {
    static func label(_ text: String, dark: Bool, maxWidth: CGFloat) -> (NSAttributedString, CGSize) {
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byTruncatingTail
        ps.alignment = .center
        let color = dark ? UIColor(white: 0.93, alpha: 1) : UIColor(red: 0.04, green: 0.08, blue: 0.19, alpha: 1)
        let at = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 10.5, weight: .semibold), .foregroundColor: color, .paragraphStyle: ps])
        let w = min(at.size().width + 14, maxWidth)
        return (at, CGSize(width: ceil(w), height: 18))
    }

    private static func drawLabel(_ text: String, dark: Bool, centerX: CGFloat, y: CGFloat, maxWidth: CGFloat, border: UIColor) {
        let (at, sz) = label(text, dark: dark, maxWidth: maxWidth)
        let r = CGRect(x: centerX - sz.width / 2, y: y, width: sz.width, height: sz.height)
        let path = UIBezierPath(roundedRect: r, cornerRadius: 8)
        (dark ? UIColor(red: 0.02, green: 0.05, blue: 0.09, alpha: 0.9) : UIColor(white: 1, alpha: 0.96)).setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = 1
        path.stroke()
        at.draw(in: CGRect(x: r.minX + 5, y: r.minY + 2.5, width: r.width - 10, height: r.height - 3))
    }

    static func person(_ p: MapPerson, photo: UIImage?, dark: Bool) -> UIImage {
        let d: CGFloat = 32
        let pad: CGFloat = 8
        let (_, ls) = label(p.name, dark: dark, maxWidth: 130)
        let w = max(d + pad * 2, ls.width + 2)
        let h = d + pad * 2 + 2 + ls.height
        let fmt = UIGraphicsImageRendererFormat()
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { rc in
            let ctx = rc.cgContext
            let c = CGPoint(x: w / 2, y: pad + d / 2)
            if p.inside {
                UIColor(red: 0.29, green: 0.87, blue: 0.5, alpha: 0.28).setFill()
                UIBezierPath(arcCenter: c, radius: d / 2 + pad - 1, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
            }
            ctx.saveGState()
            let circle = UIBezierPath(arcCenter: c, radius: d / 2, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            circle.addClip()
            if let ph = photo {
                ph.draw(in: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
            } else {
                let base: UIColor = p.inside
                    ? UIColor(hue: CGFloat(nameHue(p.name) / 360), saturation: 0.55, brightness: 0.62, alpha: 1)
                    : (dark ? UIColor(red: 0.16, green: 0.21, blue: 0.28, alpha: 1) : UIColor(red: 0.8, green: 0.84, blue: 0.88, alpha: 1))
                base.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: w, height: h))
                let ch = String(p.name.prefix(1))
                let at = NSAttributedString(string: ch, attributes: [
                    .font: UIFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: UIColor.white])
                let s = at.size()
                at.draw(at: CGPoint(x: c.x - s.width / 2, y: c.y - s.height / 2))
            }
            ctx.restoreGState()
            (p.inside ? UIColor(red: 0.29, green: 0.87, blue: 0.5, alpha: 1) : UIColor(white: 1, alpha: 0.85)).setStroke()
            circle.lineWidth = 2
            circle.stroke()
            drawLabel(p.name, dark: dark, centerX: w / 2, y: pad * 2 + d + 2, maxWidth: 130,
                      border: p.inside ? UIColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1) : (dark ? UIColor(red: 0.16, green: 0.27, blue: 0.44, alpha: 1) : UIColor(red: 0.78, green: 0.83, blue: 0.9, alpha: 1)))
        }
    }

    static func project(_ p: MapProject, photo: UIImage?, dark: Bool) -> UIImage {
        let s: CGFloat = 40
        let text = p.count > 0 ? p.name + " · " + Fa.n(p.count) + " نفر" : p.name
        let (_, ls) = label(text, dark: dark, maxWidth: 170)
        let w = max(s + 8, ls.width + 2)
        let h = s + 6 + ls.height
        let fmt = UIGraphicsImageRendererFormat()
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { rc in
            let box = CGRect(x: (w - s) / 2, y: 2, width: s, height: s)
            let path = UIBezierPath(roundedRect: box, cornerRadius: 11)
            if let ph = photo {
                rc.cgContext.saveGState()
                path.addClip()
                ph.draw(in: box)
                rc.cgContext.restoreGState()
            } else {
                UIColor(red: 0.04, green: 0.07, blue: 0.13, alpha: 1).setFill()
                path.fill()
                UIColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1).setFill()
                for r in 0..<3 {
                    for c in 0..<3 {
                        let wx = box.minX + 9 + CGFloat(c) * 8
                        let wy = box.minY + 8 + CGFloat(r) * 9
                        UIBezierPath(roundedRect: CGRect(x: wx, y: wy, width: 5, height: 6), cornerRadius: 1).fill()
                    }
                }
            }
            UIColor(white: 1, alpha: 0.9).setStroke()
            path.lineWidth = 1.5
            path.stroke()
            drawLabel(text, dark: dark, centerX: w / 2, y: s + 6, maxWidth: 170,
                      border: dark ? UIColor(red: 0.58, green: 0.77, blue: 0.99, alpha: 1) : UIColor(red: 0.11, green: 0.31, blue: 0.85, alpha: 1))
        }
    }
}

enum PhotoLoader {
    private static var cache: [String: UIImage] = [:]

    static func url(_ s: String) -> URL? {
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: Config.webBase + (s.hasPrefix("/") ? s : "/" + s))
    }

    static func first(_ cands: [String]) async -> UIImage? {
        for c in cands where !c.isEmpty {
            if let im = cache[c] { return im }
            guard let u = url(c) else { continue }
            var req = URLRequest(url: u)
            req.timeoutInterval = 15
            if let t = Session.token { req.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200, let im = UIImage(data: data) {
                cache[c] = im
                return im
            }
        }
        return nil
    }
}

// MARK: - کنترل نقشه (دکمه‌های + − و «نمایش روی نقشه»)

final class MapController: ObservableObject {
    weak var map: MKMapView?

    func zoom(_ factor: Double) {
        guard let m = map else { return }
        var r = m.region
        r.span.latitudeDelta = max(min(r.span.latitudeDelta * factor, 120), 0.0004)
        r.span.longitudeDelta = max(min(r.span.longitudeDelta * factor, 300), 0.0004)
        m.setRegion(r, animated: true)
    }

    func focus(lat: Double, lng: Double) {
        guard let m = map else { return }
        m.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                                       span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)), animated: true)
    }
}

// MARK: - نقشه‌ی MapKit

struct MapCanvas: UIViewRepresentable {
    let projects: [MapProject]
    let people: [MapPerson]
    let filter: MapFilter
    let template: String
    let dark: Bool
    let fitKey: String
    let controller: MapController

    func makeCoordinator() -> Coordinator { return Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.isRotateEnabled = false
        m.isPitchEnabled = false
        m.showsCompass = false
        m.showsScale = false
        m.pointOfInterestFilter = .excludingAll
        m.overrideUserInterfaceStyle = dark ? .dark : .light
        m.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.6892, longitude: 51.389),
                                       span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)), animated: false)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.touched))
        pan.delegate = context.coordinator
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.touched))
        pinch.delegate = context.coordinator
        m.addGestureRecognizer(pan)
        m.addGestureRecognizer(pinch)
        controller.map = m
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) {
        let co = context.coordinator
        co.dark = dark
        controller.map = m
        m.overrideUserInterfaceStyle = dark ? .dark : .light
        let tpl = MapConfigStore.template(template)
        if co.tileTemplate != tpl || co.tileDark != dark {
            if let o = co.overlay { m.removeOverlay(o) }
            let o = StyledTileOverlay(template: tpl, dark: dark)
            m.addOverlay(o, level: .aboveLabels)
            co.overlay = o
            co.tileTemplate = tpl
            co.tileDark = dark
        }
        let vp = projects.filter { filter.showPj($0) }
        let vq = people.filter { filter.showPp($0) }
        let sig = vp.map { "\($0.name)|\($0.count)" }.joined(separator: ",") + "#" + vq.map { "\($0.id)|\($0.status)|\($0.lat)|\($0.lng)" }.joined(separator: ",") + (dark ? "D" : "L")
        if sig != co.sig {
            co.sig = sig
            m.removeAnnotations(m.annotations)
            m.addAnnotations(vp.map { PjAnn($0) } as [MKAnnotation])
            m.addAnnotations(vq.map { PpAnn($0) } as [MKAnnotation])
        }
        if fitKey != co.fitKey && !co.userMoved {
            co.fitKey = fitKey
            let all = projects.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            // نزدیک‌ترین نمای «شلوغ‌ترین پروژه»؛ اگر نبود همه‌ی نقاط
            var busy: [CLLocationCoordinate2D] = []
            let present = people.filter { $0.status == "present" }
            if !present.isEmpty {
                var cnt: [String: Int] = [:]
                for p in present { cnt[p.proj, default: 0] += 1 }
                if let top = cnt.max(by: { $0.value < $1.value })?.key {
                    busy = present.filter { $0.proj == top }.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                    if let pj = projects.first(where: { $0.name == top }) {
                        busy.append(CLLocationCoordinate2D(latitude: pj.lat, longitude: pj.lng))
                    }
                }
            }
            let pts = busy.isEmpty ? all + people.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } : busy
            co.fit(m, pts)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var overlay: MKTileOverlay?
        var tileTemplate = ""
        var tileDark = false
        var dark = false
        var sig = ""
        var fitKey = ""
        var userMoved = false

        @objc func touched() { userMoved = true }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { return true }

        func fit(_ m: MKMapView, _ pts: [CLLocationCoordinate2D]) {
            if pts.isEmpty { return }
            var rect = MKMapRect.null
            for p in pts {
                let mp = MKMapPoint(p)
                rect = rect.union(MKMapRect(x: mp.x, y: mp.y, width: 0.1, height: 0.1))
            }
            let minSide = MKMapPointsPerMeterAtLatitude(pts[0].latitude) * 600
            if rect.size.width < minSide || rect.size.height < minSide {
                let c = MKMapPoint(x: rect.midX, y: rect.midY)
                rect = MKMapRect(x: c.x - minSide / 2, y: c.y - minSide / 2, width: minSide, height: minSide)
            }
            m.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 70, left: 50, bottom: 120, right: 50), animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let t = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: t) }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let a = annotation as? PpAnn {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: "pp") ?? MKAnnotationView(annotation: a, reuseIdentifier: "pp")
                v.annotation = a
                v.canShowCallout = true
                v.displayPriority = a.pp.inside ? .required : .defaultHigh
                apply(v, a)
                if a.photo == nil && !a.pp.photos.isEmpty {
                    let cands = a.pp.photos
                    Task { @MainActor [weak self, weak mapView, weak a] in
                        guard let im = await PhotoLoader.first(cands), let a = a, let self = self else { return }
                        a.photo = im
                        if let v2 = mapView?.view(for: a) { self.apply(v2, a) }
                    }
                }
                return v
            }
            if let a = annotation as? PjAnn {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: "pj") ?? MKAnnotationView(annotation: a, reuseIdentifier: "pj")
                v.annotation = a
                v.canShowCallout = true
                v.displayPriority = .defaultHigh
                applyPj(v, a)
                if a.photo == nil && !a.pj.avatar.isEmpty {
                    let cands = [a.pj.avatar]
                    Task { @MainActor [weak self, weak mapView, weak a] in
                        guard let im = await PhotoLoader.first(cands), let a = a, let self = self else { return }
                        a.photo = im
                        if let v2 = mapView?.view(for: a) { self.applyPj(v2, a) }
                    }
                }
                return v
            }
            return nil
        }

        func apply(_ v: MKAnnotationView, _ a: PpAnn) {
            let im = MapArt.person(a.pp, photo: a.photo, dark: dark)
            v.image = im
            v.centerOffset = CGPoint(x: 0, y: -(im.size.height / 2) + 8 + 16)
            v.alpha = a.pp.inside ? 1 : 0.62
        }

        func applyPj(_ v: MKAnnotationView, _ a: PjAnn) {
            let im = MapArt.project(a.pj, photo: a.photo, dark: dark)
            v.image = im
            v.centerOffset = CGPoint(x: 0, y: -(im.size.height / 2) + 22)
        }
    }
}

// MARK: - کارت نقشه‌ی زنده‌ی پرسنل (کارت اول داشبورد مدیر)

private struct ListSheetKey: Identifiable {
    let id: String
}

struct StaffMapCard: View {
    let home: JSON
    var height: CGFloat = 420
    var onClose: (() -> Void)? = nil
    var showsFullscreen = true

    @Environment(\.colorScheme) private var scheme
    @StateObject private var ctl = MapController()
    @State private var filter = MapFilter.load()
    @State private var filterOpen = false
    @State private var sheet: ListSheetKey?
    @State private var fullscreen = false
    @State private var template = MapConfigStore.cached
    @State private var anchor: (Int, Date) = (0, Date())

    private var dark: Bool { return scheme == .dark }
    private var nx: Nx { return Nx(dark: dark) }

    private var data: MapData { return MapData.parse(home) }

    private func nowSeconds(_ date: Date) -> Int {
        let base = home.i("server_seconds")
        if base > 0 {
            return (base + Int(date.timeIntervalSince(anchor.1))) % 86400
        }
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }

    private func greeting(_ h: Int) -> String {
        if h < 5 { return "شب بخیر" }
        if h < 12 { return "صبح بخیر" }
        if h < 15 { return "ظهر بخیر" }
        if h < 19 { return "عصر بخیر" }
        return "شب بخیر"
    }

    var body: some View {
        let d = data
        let fitKey = "\(d.projects.count)|\(d.people.filter { $0.status == "present" }.count)|\(d.people.count)"
        ZStack(alignment: .topLeading) {
            MapCanvas(projects: d.projects, people: d.people, filter: filter, template: template, dark: dark,
                      fitKey: fitKey, controller: ctl)
            clockBlock
            controls(d)
            statusChips(d)
            Text(MapConfigStore.attribution)
                .font(.system(size: 9.5))
                .foregroundColor(nx.text.opacity(0.6))
                .padding(.leading, 8).padding(.bottom, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: height)
        .background(nx.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(nx.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
        .onAppear { anchor = (home.i("server_seconds"), Date()) }
        .task {
            await MapConfigStore.refresh()
            template = MapConfigStore.cached
        }
        .sheet(item: $sheet) { key in
            StatusListSheet(statusKey: key.id, data: d, nx: nx) { lat, lng in
                sheet = nil
                ctl.focus(lat: lat, lng: lng)
            }
        }
        .fullScreenCover(isPresented: $fullscreen) {
            ZStack(alignment: .topTrailing) {
                Color(.systemBackground).ignoresSafeArea()
                StaffMapCard(home: home, height: UIScreen.main.bounds.height - 120, onClose: { fullscreen = false }, showsFullscreen: false)
                    .padding(8)
            }
        }
    }

    // ساعت و تاریخ و سلام (بالا راست، بدون کادر)
    private var clockBlock: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
            let sec = nowSeconds(ctx.date)
            let h = sec / 3600, m = sec % 3600 / 60, s = sec % 60
            let shadowC = dark ? Color.black.opacity(0.9) : Color.white
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%02d:%02d:%02d", h, m, s))
                    .font(.system(size: 28, weight: .ultraLight)).tracking(3)
                    .foregroundColor(dark ? .white : Color(red: 0.04, green: 0.08, blue: 0.19))
                Text(Fa.digits(home.o("map").s("date_text").isEmpty ? (home.s("weekday") + " " + home.s("today_jalali")) : home.o("map").s("date_text")))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(dark ? Color.white.opacity(0.92) : Color(red: 0.11, green: 0.16, blue: 0.28))
                Text(greeting(h))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(dark ? Color(red: 0.58, green: 0.77, blue: 0.99) : Color(red: 0.11, green: 0.31, blue: 0.85))
            }
            .shadow(color: shadowC, radius: dark ? 2 : 5, y: dark ? 1 : 0)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .allowsHitTesting(false)
    }

    private func glass() -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(dark ? Color(red: 0.04, green: 0.07, blue: 0.13).opacity(0.78) : Color.white.opacity(0.88))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(dark ? Color(red: 0.16, green: 0.27, blue: 0.44) : Color(red: 0.78, green: 0.83, blue: 0.9), lineWidth: 1))
    }

    private func roundButton(_ label: String, _ symbol: Bool, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if symbol { Image(systemName: label).font(.system(size: 14, weight: .semibold)) } else { Text(label).font(.system(size: 18, weight: .semibold)) }
            }
            .foregroundColor(active ? nx.blue : nx.text)
            .frame(width: 34, height: 34)
            .background(glass())
        }
    }

    // دکمه‌های + − ⤢ و فیلتر (بالا چپ)
    private func controls(_ d: MapData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            roundButton("plus", true) { ctl.zoom(0.5) }
            roundButton("minus", true) { ctl.zoom(2) }
            if showsFullscreen {
                roundButton("arrow.up.left.and.arrow.down.right", true) { fullscreen = true }
            } else if let c = onClose {
                roundButton("xmark", true) { c() }
            }
            roundButton("line.3.horizontal.decrease", true, active: filter.active || filterOpen) { filterOpen.toggle() }
            if filterOpen { filterPanel(d) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggleRow(_ title: String, count: Int, on: Bool, sub: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundColor(on ? nx.blue : nx.muted)
                Text(title).font(.system(size: 12)).foregroundColor(nx.text)
                Spacer(minLength: 6)
                Text(Fa.n(count)).font(.system(size: 11)).foregroundColor(nx.muted)
            }
            .padding(.leading, sub ? 18 : 6).padding(.vertical, 5).padding(.trailing, 6)
        }
    }

    private func filterPanel(_ d: MapData) -> some View {
        var cnt: [String: Int] = [:]
        for p in d.people { cnt[p.status, default: 0] += 1 }
        return VStack(alignment: .leading, spacing: 0) {
            toggleRow("پروژه‌ها", count: d.projects.count, on: filter.pj) { filter.pj.toggle(); filter.save() }
            toggleRow("کارمندان", count: d.people.count, on: filter.pp) {
                let turnOn = !filter.pp
                filter.pp = turnOn
                for (k, _) in StatusKeys { filter.st[k] = turnOn }
                filter.save()
            }
            ForEach(StatusKeys, id: \.0) { item in
                toggleRow(item.1, count: cnt[item.0] ?? 0, on: filter.on(item.0), sub: true) {
                    filter.st[item.0] = !filter.on(item.0)
                    filter.pp = StatusKeys.contains(where: { filter.on($0.0) })
                    filter.save()
                }
            }
            if d.cities.count > 1 {
                ForEach(d.cities, id: \.self) { c in
                    toggleRow("شهر " + c, count: d.projects.filter { $0.city == c }.count, on: !filter.cityOff.contains(c)) {
                        if filter.cityOff.contains(c) { filter.cityOff.remove(c) } else { filter.cityOff.insert(c) }
                        filter.save()
                    }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .frame(width: 190)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(dark ? Color(red: 0.04, green: 0.07, blue: 0.13).opacity(0.97) : Color.white.opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(nx.borderStrong, lineWidth: 1))
    }

    // پنج وضعیت پرسنل (پایین، سه‌تا در هر ردیف)
    private func statusChips(_ d: MapData) -> some View {
        let rows: [[(String, String)]] = [Array(StatusKeys.prefix(3)), Array(StatusKeys.suffix(2))]
        return VStack(spacing: 4) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(rows[r], id: \.0) { item in
                        Button(action: { sheet = ListSheetKey(id: item.0) }) {
                            HStack(spacing: 5) {
                                Circle().fill(nx.status(item.0)).frame(width: 6, height: 6)
                                Text(item.1).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                                    .foregroundColor(dark ? Color(red: 0.9, green: 0.93, blue: 0.98) : Color(red: 0.11, green: 0.16, blue: 0.28))
                                Spacer(minLength: 0)
                                Text(Fa.n(d.lists[item.0]?.count ?? 0)).font(.system(size: 12, weight: .heavy))
                                    .foregroundColor(dark ? .white : Color(red: 0.04, green: 0.08, blue: 0.19))
                            }
                            .padding(.horizontal, 7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(glass())
                        }
                    }
                    if rows[r].count < 3 { Spacer().frame(maxWidth: .infinity) }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .padding(8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - فهرست افراد هر وضعیت (با جستجو و «نمایش روی نقشه»)

private struct StatusListSheet: View {
    let statusKey: String
    let data: MapData
    let nx: Nx
    let show: (Double, Double) -> Void
    @State private var q = ""
    @Environment(\.presentationMode) private var presentation

    private var title: String { return StatusKeys.first(where: { $0.0 == statusKey })?.1 ?? "" }

    private var names: [String] {
        var base = data.lists[statusKey] ?? []
        if statusKey == "present" && base.isEmpty { base = data.people.filter { $0.status == "present" }.map { $0.name } }
        let t = q.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? base : base.filter { $0.contains(t) }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(names, id: \.self) { nm in
                    row(nm)
                }
                if names.isEmpty {
                    Text("موردی نیست").foregroundColor(nx.muted)
                }
            }
            .listStyle(PlainListStyle())
            .navigationTitle(title + " (" + Fa.n((data.lists[statusKey] ?? []).count) + ")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("بستن") { presentation.wrappedValue.dismiss() } }
            }
            .searchable(text: $q, prompt: "جستجوی نام")
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func row(_ nm: String) -> some View {
        let info = data.info[nm] ?? [:]
        let pt = data.people.first(where: { $0.name == nm })
        var sub: [String] = []
        let proj = info.s("proj")
        if !proj.isEmpty { sub.append(proj) }
        let time = info.s("time")
        if !time.isEmpty { sub.append(Fa.digits(time)) }
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color(hue: nameHue(nm) / 360, saturation: 0.55, brightness: 0.62))
                Text(String(nm.prefix(1))).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(nm).font(.system(size: 14, weight: .semibold))
                if !sub.isEmpty { Text(sub.joined(separator: " · ")).font(.system(size: 11)).foregroundColor(nx.muted) }
            }
            Spacer()
            if let p = pt {
                Button(action: { show(p.lat, p.lng) }) {
                    Text("⌖ نمایش روی نقشه").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(LinearGradient(gradient: Gradient(colors: [nx.blue, nx.blueDark]), startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}
