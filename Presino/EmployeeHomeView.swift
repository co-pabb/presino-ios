import SwiftUI
import UIKit

// MARK: - رنگ‌های «آسمان کار» (همان متغیرهای hx-* صفحه‌ی اصلی کارمند در وب)

fileprivate func sk(_ hex: UInt32, _ a: Double = 1) -> Color {
    return Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: a)
}

fileprivate struct SkyPalette {
    let sky1: Color
    let sky2: Color
    let sky3: Color
    let text: Color
    let glass: Color
    let glassB: Color
    let tick: Color
    let holdBg: Color
    let hill1: Color
    let hill2: Color
    let stars: Bool

    /// light: حالت روشن برنامه — night: هنوز ورود نزده (آسمان شب)
    static func make(light: Bool, night: Bool) -> SkyPalette {
        if light {
            if night {
                return SkyPalette(sky1: sk(0xEEF2FF), sky2: sk(0xD6DEFC), sky3: sk(0xB4C4FB), text: sk(0x14204A),
                                  glass: Color.white.opacity(0.62), glassB: Color.white.opacity(0.95), tick: sk(0x14204A, 0.55),
                                  holdBg: sk(0x1B2A6B), hill1: sk(0xC9D5FB), hill2: sk(0xAEBDF3), stars: false)
            }
            return SkyPalette(sky1: sk(0xFFE3B8), sky2: sk(0xFFC4A0), sky3: sk(0x8FD0FF), text: sk(0x14204A),
                              glass: Color.white.opacity(0.55), glassB: Color.white.opacity(0.9), tick: sk(0x14204A, 0.6),
                              holdBg: sk(0x14204A), hill1: sk(0xFFD2B0), hill2: sk(0xFFB98F), stars: false)
        }
        if night {
            return SkyPalette(sky1: sk(0x2A3A8C), sky2: sk(0x17206B), sky3: sk(0x070B2E), text: .white,
                              glass: Color.white.opacity(0.16), glassB: Color.white.opacity(0.28), tick: Color.white.opacity(0.75),
                              holdBg: sk(0x12163A), hill1: sk(0x241A63), hill2: sk(0x171447), stars: true)
        }
        return SkyPalette(sky1: sk(0xFF9D5C), sky2: sk(0xFF5F7E), sky3: sk(0x3B2A8F), text: .white,
                          glass: Color.white.opacity(0.16), glassB: Color.white.opacity(0.28), tick: Color.white.opacity(0.75),
                          holdBg: sk(0x12163A), hill1: sk(0x241A63), hill2: sk(0x171447), stars: false)
    }
}

// MARK: - شکل‌ها

fileprivate struct BottomRound: Shape {
    var r: CGFloat
    func path(in rect: CGRect) -> Path {
        let p = UIBezierPath(roundedRect: rect, byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: CGSize(width: r, height: r))
        return Path(p.cgPath)
    }
}

/// تپه‌ها: همان مسیرهای SVG وب (viewBox ‏۴۳۰×۲۱۰، کشیده‌شده به عرض صفحه)
fileprivate struct HillShape: Shape {
    let kind: Int
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 430
        let sy = rect.height / 210
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { return CGPoint(x: x * sx, y: y * sy) }
        var p = Path()
        if kind == 1 {
            p.move(to: P(0, 120))
            p.addCurve(to: P(170, 110), control1: P(60, 70), control2: P(110, 90))
            p.addCurve(to: P(430, 100), control1: P(230, 130), control2: P(300, 60))
        } else if kind == 2 {
            p.move(to: P(0, 150))
            p.addCurve(to: P(220, 125), control1: P(80, 110), control2: P(150, 140))
            p.addCurve(to: P(430, 140), control1: P(290, 110), control2: P(350, 100))
        } else {
            p.move(to: P(0, 185))
            p.addCurve(to: P(250, 172), control1: P(90, 160), control2: P(170, 190))
            p.addCurve(to: P(430, 180), control1: P(330, 154), control2: P(380, 160))
        }
        p.addLine(to: P(430, 210))
        p.addLine(to: P(0, 210))
        p.closeSubpath()
        return p
    }
}

// MARK: - کمان شیفت، خورشید و برچسب ساعت کارکرد

fileprivate struct SkyArcView: View {
    let w: CGFloat
    let pal: SkyPalette
    let inn: Bool
    let F: CGFloat
    let sMin: Int
    let eMin: Int
    let tagText: String
    let rot: Double

    private var s: CGFloat { return w / 430 }
    private var oy: CGFloat { return (340 - 340 * s) / 2 }
    private var total: Double { return Double(eMin - sMin) / 60 }

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        return CGPoint(x: x * s, y: oy + y * s)
    }

    private func arcP(_ f: CGFloat) -> CGPoint {
        let a = Double(f) * Double.pi
        return pt(215 + 180 * CGFloat(cos(a)), 300 - 180 * CGFloat(sin(a)))
    }

    private func trackPath() -> Path {
        var p = Path()
        for i in 0...90 {
            let q = arcP(CGFloat(i) / 90)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        return p
    }

    private func hhmm(_ m: Int) -> String {
        let h = (m / 60) % 24
        let mm = m % 60
        return Fa.digits(String(format: "%02d:%02d", h, mm))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            trackPath()
                .stroke(pal.glass, style: StrokeStyle(lineWidth: 14 * s, lineCap: .round, lineJoin: .round))
            trackPath()
                .trimmedPath(from: 0, to: max(0.001, F))
                .stroke(LinearGradient(colors: [sk(0x7DFFC8), sk(0xFFE08A), sk(0xFF9D5C)], startPoint: .trailing, endPoint: .leading),
                        style: StrokeStyle(lineWidth: 14 * s, lineCap: .round, lineJoin: .round))
                .shadow(color: sk(0x7DFFC8, 0.45), radius: 5)
                .opacity(F > 0.005 ? 1 : 0)
            ForEach(0...max(0, Int(floor(total))), id: \.self) { h in
                tickView(h)
            }
            sunView
            tagView
            Text("شروع " + hhmm(sMin))
                .font(.system(size: 12, weight: .heavy)).foregroundColor(pal.text)
                .position(pt(395, 334))
            Text("پایان " + hhmm(eMin))
                .font(.system(size: 12, weight: .heavy)).foregroundColor(pal.text)
                .position(pt(35, 334))
        }
        .frame(width: w, height: 340, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.8), value: F)
    }

    private func tickView(_ h: Int) -> some View {
        let f = CGFloat(h) / CGFloat(max(total, 0.01))
        let p0 = arcP(min(1, f))
        let c = pt(215, 300)
        let dx = p0.x - c.x
        let dy = p0.y - c.y
        let r = max(hypot(dx, dy), 1)
        let ux = dx / r
        let uy = dy / r
        let a = CGPoint(x: p0.x + ux * 14 * s, y: p0.y + uy * 14 * s)
        let b = CGPoint(x: p0.x + ux * 22 * s, y: p0.y + uy * 22 * s)
        let lab = ((sMin / 60) + h) % 24
        let showLab = h % 2 == 0 && h > 0 && Double(h) < total - 0.5
        let lp = CGPoint(x: p0.x - ux * 26 * s, y: p0.y - uy * 26 * s + 4 * s)
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: a)
                p.addLine(to: b)
            }
            .stroke(pal.tick, style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
            if showLab {
                Text(Fa.n(lab))
                    .font(.system(size: 11.5 * s, weight: .heavy)).foregroundColor(pal.text).opacity(0.9)
                    .position(lp)
            }
        }
    }

    private var sunView: some View {
        let sp = arcP(F)
        return ZStack {
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    ZStack {
                        Capsule().fill(sk(0xFFD166)).frame(width: 3 * s, height: 10 * s).offset(y: -31 * s)
                    }
                    .frame(width: 88 * s, height: 88 * s)
                    .rotationEffect(.degrees(Double(i) * 30))
                }
            }
            .rotationEffect(.degrees(rot))
            Circle()
                .fill(RadialGradient(colors: [sk(0xFFFBE6), sk(0xFFD166), sk(0xFFD166, 0)], center: .center, startRadius: 0, endRadius: 44 * s))
                .frame(width: 88 * s, height: 88 * s)
            Circle().fill(sk(0xFFFBE6)).frame(width: 30 * s, height: 30 * s)
                .overlay(Circle().stroke(sk(0xFFD166), lineWidth: 3 * s))
        }
        .frame(width: 88 * s, height: 88 * s)
        .position(sp)
        .opacity(inn ? 1 : 0.4)
    }

    private var tagView: some View {
        let sp = arcP(F)
        let c = pt(215, 300)
        let dx = c.x - sp.x
        let dy = c.y - sp.y
        let r = max(hypot(dx, dy), 1)
        let tp = CGPoint(x: sp.x + dx / r * 52 * s, y: sp.y + dy / r * 52 * s)
        return ZStack {
            RoundedRectangle(cornerRadius: 13 * s, style: .continuous).fill(sk(0x14204A, 0.88)).frame(width: 72 * s, height: 26 * s)
            Text(tagText).font(.system(size: 12.5 * s, weight: .heavy)).foregroundColor(.white)
        }
        .position(tp)
        .opacity(inn ? 1 : 0)
    }
}

// MARK: - مدل سطرهای «روز من»

fileprivate struct DayEvent: Identifiable {
    let id = UUID()
    let kind: String      // g=ورود، a=عقب‌افتاده، b=وظیفه، p=برنامه‌ی شخصی، m=فردا، now=نشانگر «اکنون»
    let small: String
    let title: String
    let sub: String
    let path: String
}

/// صفحه‌ی اول کارمند «آسمان کار» — دقیقاً مثل صفحه‌ی اصلی کارمند در وب:
/// ساعت و کمان شیفت با خورشید، دکمه‌ی «۱ ثانیه نگه دارید»، چهار گوی، «روز من» و آخرین درخواست‌ها
struct EmployeeHomeView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var perm = PermissionState.shared
    @Environment(\.colorScheme) private var scheme
    let openWeb: (String) -> Void
    let openNotifications: () -> Void
    @State private var holdP: CGFloat = 0
    @State private var floatUp = false
    @State private var avatar: UIImage?

    init(openWeb: @escaping (String) -> Void, openNotifications: @escaping () -> Void) {
        self.openWeb = openWeb
        self.openNotifications = openNotifications
    }

    private var home: JSON { return state.home }
    private var isIn: Bool { return home.s("next_action") == "check_out" }
    private var dark: Bool { return scheme == .dark }
    private var nx: Nx { return Nx(dark: dark) }
    private var logs: [JSON] { return home.a("today_logs") }
    private var screenW: CGFloat { return UIScreen.main.bounds.width }

    private var topInset: CGFloat {
        let w = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first(where: { $0.isKeyWindow })
        return w?.safeAreaInsets.top ?? 44
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                sceneView
                VStack(spacing: 14) {
                    banners
                    orbsView
                    dayView
                    recentView
                    Spacer().frame(height: 18)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(nx.bg.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .refreshable { await state.reload() }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { floatUp = true }
        .task(id: home.s("photo_url")) {
            let u = home.s("photo_url")
            if !u.isEmpty { avatar = await PhotoLoader.first([u]) }
        }
    }

    // MARK: - زمان‌ها

    private func toMin(_ t: String) -> Int? {
        let a = t.split(separator: ":")
        if a.count < 2 { return nil }
        guard let h = Int(a[0]), let m = Int(a[1]) else { return nil }
        return h * 60 + m
    }

    private var shiftRange: (Int, Int) {
        let sh = home.o("shift")
        var s: Int? = nil
        var e: Int? = nil
        if sh.b("is_working") {
            s = toMin(sh.s("start_time"))
            e = toMin(sh.s("end_time"))
        }
        if s == nil || e == nil {
            let first = logs.first(where: { $0.s("type") == "check_in" })
            let base = first != nil ? (toMin(first!.s("time")) ?? 480) : 480
            s = base
            e = base + 480
        }
        let ss = s ?? 480
        var ee = e ?? (ss + 480)
        if ee <= ss { ee += 1440 }
        return (ss, ee)
    }

    private func workedSeconds(now: Date) -> Double {
        var closed = 0.0
        var openStart: Double? = nil
        for l in logs {
            guard let m = toMin(l.s("time")) else { continue }
            let t = Double(m * 60)
            if l.s("type") == "check_in" {
                if openStart == nil { openStart = t }
            } else if let o = openStart {
                closed += max(0, t - o)
                openStart = nil
            }
        }
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let nowS = Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0))
        if let o = openStart { return closed + max(0, nowS - o) }
        return closed
    }

    // MARK: - آسمان

    private var sceneView: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
            skyScene(now: ctx.date)
        }
    }

    private func skyScene(now: Date) -> some View {
        let w = screenW
        let inset = topInset
        let night = !isIn
        let pal = SkyPalette.make(light: !dark, night: night)
        let range = shiftRange
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let hh = c.hour ?? 0
        let mi = c.minute ?? 0
        let se = c.second ?? 0
        var nm = Double(hh * 60 + mi) + Double(se) / 60
        if range.1 > 1440 && nm < Double(range.0) { nm += 1440 }
        let span = Double(range.1 - range.0)
        let target: CGFloat = isIn ? CGFloat(max(0.01, min(1, (nm - Double(range.0)) / max(span, 1)))) : 0
        let wm = Int(workedSeconds(now: now) / 60)
        let tag = Fa.digits("\(wm / 60):" + String(format: "%02d", wm % 60))
        let rot = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 40) / 40 * 360
        let dateText = home.s("today_readable").isEmpty ? home.s("today_jalali") : home.s("today_readable")

        return ZStack(alignment: .topLeading) {
            LinearGradient(gradient: Gradient(stops: [
                .init(color: pal.sky3, location: 0),
                .init(color: pal.sky2, location: 0.62),
                .init(color: pal.sky1, location: 1)]), startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Spacer().frame(height: inset)
                ZStack(alignment: .topLeading) {
                    if pal.stars { starsView(w: w) }
                    SkyArcView(w: w, pal: pal, inn: isIn, F: target, sMin: range.0, eMin: range.1, tagText: tag, rot: rot)
                        .offset(y: 34)
                    clockView(pal: pal, hh: hh, mi: mi, se: se, w: w).offset(y: 226)
                    subRow(pal: pal, text: dateText, w: w).offset(y: 330)
                    hillsView(pal: pal, w: w).offset(y: 322)
                    holdButton(pal: pal, w: w).offset(y: 376)
                    Text("۱ ثانیه نگه دارید")
                        .font(.system(size: 11.5, weight: .bold)).foregroundColor(pal.text).opacity(0.9)
                        .frame(width: w).offset(y: 495)
                    headerView(pal: pal, w: w)
                }
                .frame(width: w, height: 530, alignment: .topLeading)
            }
        }
        .frame(width: w, height: 530 + inset, alignment: .topLeading)
        .clipShape(BottomRound(r: 38))
        .environment(\.layoutDirection, .leftToRight)
    }

    private func starsView(w: CGFloat) -> some View {
        func fr(_ v: Double) -> Double { return v - floor(v) }
        return ZStack(alignment: .topLeading) {
            ForEach(0..<30, id: \.self) { i in
                let x = fr(sin(Double(i) * 12.9898) * 43758.5453)
                let y = fr(sin(Double(i) * 78.233) * 12345.6789) * 0.55
                Circle().fill(Color.white).frame(width: 3, height: 3)
                    .position(x: CGFloat(x) * w, y: CGFloat(y) * 530)
            }
        }
        .frame(width: w, height: 530, alignment: .topLeading)
    }

    private func p2(_ n: Int) -> String { return Fa.digits(String(format: "%02d", n)) }

    private func clockView(pal: SkyPalette, hh: Int, mi: Int, se: Int, w: CGFloat) -> some View {
        HStack(spacing: 8) {
            flap(pal: pal, text: p2(hh))
            VStack(spacing: 12) {
                Circle().fill(pal.text).frame(width: 7, height: 7)
                Circle().fill(pal.text).frame(width: 7, height: 7)
            }
            flap(pal: pal, text: p2(mi))
            ZStack {
                Circle().stroke(pal.glass, lineWidth: 4)
                Circle().trim(from: 0, to: CGFloat(se) / 60)
                    .stroke(pal.text, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(p2(se)).font(.system(size: 14, weight: .heavy)).foregroundColor(pal.text)
            }
            .frame(width: 46, height: 46)
            .padding(.leading, 4)
        }
        .frame(width: w, height: 92)
    }

    private func flap(pal: SkyPalette, text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(pal.glass)
            RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(pal.glassB, lineWidth: 1)
            Rectangle().fill(Color.black.opacity(0.14)).frame(height: 2)
            Text(text).font(.system(size: 58, weight: .heavy)).foregroundColor(pal.text).minimumScaleFactor(0.6)
        }
        .frame(width: 88, height: 92)
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 8)
    }

    private func subRow(pal: SkyPalette, text: String, w: CGFloat) -> some View {
        let off = state.offline
        return HStack(spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(off ? sk(0xFF8A9A) : sk(0x7DFFC8)).frame(width: 8, height: 8)
                    .overlay(Circle().stroke((off ? sk(0xFF8A9A) : sk(0x7DFFC8)).opacity(0.3), lineWidth: 3))
                Text(off ? "آفلاین" : "آنلاین").font(.system(size: 12.5, weight: .heavy)).foregroundColor(pal.text)
            }
            .padding(.horizontal, 14).padding(.vertical, 5)
            .background(Capsule().fill(pal.glass))
            .overlay(Capsule().stroke(pal.glassB, lineWidth: 1))
            Text(Fa.digits(text)).font(.system(size: 12.5, weight: .heavy)).foregroundColor(pal.text)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(Capsule().fill(pal.glass))
                .overlay(Capsule().stroke(pal.glassB, lineWidth: 1))
        }
        .frame(width: w)
    }

    private func hillsView(pal: SkyPalette, w: CGFloat) -> some View {
        ZStack {
            HillShape(kind: 1).fill(pal.hill1).opacity(0.8)
            HillShape(kind: 2).fill(pal.hill2)
            HillShape(kind: 3).fill(nx.bg)
        }
        .frame(width: w, height: 210)
    }

    // MARK: - دکمه‌ی نگه‌داشتن

    private func holdButton(pal: SkyPalette, w: CGFloat) -> some View {
        let ringFg: Color = dark ? Color.white : pal.holdBg
        let ringBg: Color = dark ? Color.white.opacity(0.32) : pal.holdBg.opacity(0.18)
        return ZStack {
            Circle().fill(ringBg)
            Circle().trim(from: 0, to: holdP)
                .stroke(ringFg, style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .padding(3.5)
            Circle().fill(pal.holdBg).padding(7)
            Text(isIn ? "ثبت خروج" : "ثبت ورود")
                .font(.system(size: 13.5, weight: .heavy)).foregroundColor(.white)
        }
        .frame(width: 104, height: 104)
        .shadow(color: Color.black.opacity(0.3), radius: 14, x: 0, y: 8)
        .contentShape(Circle())
        .frame(width: w)
        .onLongPressGesture(minimumDuration: 1.0, maximumDistance: 60, pressing: { pressing in
            if pressing {
                withAnimation(.linear(duration: 1.0)) { holdP = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.15)) { holdP = 0 }
            }
        }, perform: {
            holdP = 0
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if !state.busy && !perm.blocking { submit() }
        })
    }

    // MARK: - هدر داخل آسمان

    private func headerView(pal: SkyPalette, w: CGFloat) -> some View {
        let full = home.o("employee").s("full_name")
        let first = full.split(separator: " ").first.map(String.init) ?? full
        return HStack(spacing: 10) {
            Menu {
                Button("درخواست‌ها") { openWeb("/employee/requests.php") }
                Button("وظایف") { openWeb("/tasks/my_tasks.php") }
                Button("پیام‌ها") { openWeb("/employee/messages.php") }
                Button("گزارش‌ها") { openWeb("/employee/reports.php") }
                Button("فیش حقوقی") { openWeb("/employee/payslip.php") }
                Button("برنامه‌ی شخصی") { openWeb("/tasks/personal.php") }
                Button("پروفایل") { openWeb("/employee/profile.php") }
            } label: {
                circleIcon("line.3.horizontal", pal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(first.isEmpty ? "سلام" : "سلام، " + first)
                    .font(.system(size: 18, weight: .heavy)).foregroundColor(pal.text).lineLimit(1)
                Text("پروژه: " + projectLabel).font(.system(size: 12)).foregroundColor(pal.text).opacity(0.9).lineLimit(1)
            }
            .environment(\.layoutDirection, .rightToLeft)
            Spacer(minLength: 4)
            Button(action: { ThemeStore.toggle(currentlyDark: dark) }) {
                circleIcon("circle.lefthalf.filled", pal)
            }
            Button(action: openNotifications) {
                ZStack(alignment: .topTrailing) {
                    circleIcon("bell", pal)
                    if state.unread > 0 {
                        Text(Fa.n(state.unread)).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(Brand.red).clipShape(Capsule())
                    }
                }
            }
            Button(action: { openWeb("/employee/profile.php") }) {
                ZStack {
                    Circle().fill(pal.glass)
                    if let a = avatar {
                        Image(uiImage: a).resizable().scaledToFill()
                    } else {
                        Text(String(first.prefix(1))).font(.system(size: 18, weight: .heavy)).foregroundColor(pal.text)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(width: w, alignment: .leading)
    }

    private func circleIcon(_ symbol: String, _ pal: SkyPalette) -> some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundColor(pal.text)
            .frame(width: 44, height: 44)
            .background(Circle().fill(pal.glass))
    }

    private var projectLabel: String {
        if let l = logs.last {
            let n = l.s("project_name")
            if !n.isEmpty && n != "-" { return n }
        }
        let ps = home.a("projects")
        if ps.count == 1 { return ps[0].s("name") }
        return ps.isEmpty ? "—" : Fa.n(ps.count) + " پروژه"
    }

    // MARK: - هشدارها (بدون تغییر نسبت به نسخه‌ی قبل)

    @ViewBuilder private var banners: some View {
        if let m = state.message {
            Banner(text: m, icon: "info.circle.fill", color: Brand.blue)
        }
        if state.offline {
            Banner(text: "اینترنت قطع است؛ آخرین اطلاعات ذخیره‌شده نمایش داده می‌شود. ثبت ورود و خروج در این حالت هم کار می‌کند و بعداً ارسال می‌شود.",
                   icon: "wifi.slash", color: Brand.orange)
        }
        if state.queued > 0 {
            Banner(text: "\(state.queued) ثبت آفلاین در انتظار ارسال به سرور است.", icon: "arrow.triangle.2.circlepath",
                   color: Brand.orange, actionTitle: "ارسال اکنون", action: { Task { _ = await OfflineQueue.shared.flush() } })
        }
        if perm.wantsAlways {
            Banner(text: "برای ثبت خودکار ورود و خروج و ثبت مسیر در پس‌زمینه، دسترسی موقعیت را روی «همیشه» بگذارید.",
                   icon: "location.fill", color: Brand.orange, actionTitle: "باز کردن تنظیمات", action: { PermissionState.openSettings() })
        }
        if perm.notifDenied {
            Banner(text: "اعلان‌ها خاموش است؛ یادآور ورود و خروج و اعلان‌های مدیر را دریافت نمی‌کنید.",
                   icon: "bell.slash.fill", color: Brand.red, actionTitle: "باز کردن تنظیمات", action: { PermissionState.openSettings() })
        }
    }

    // MARK: - ثبت تردد

    private func submit() {
        let type = isIn ? "check_out" : "check_in"
        Task {
            let res = await AttendanceService.submit(type: type)
            switch res {
            case .done(let m):
                state.toast("✅ " + m)
            case .queued(let m):
                state.toast("📴 " + m)
            case .failed(let m):
                state.toast("⚠️ " + m)
            case .needsWeb(let m):
                state.toast(m)
                openWeb("/employee/index.php")
            }
        }
    }

    // MARK: - گوی‌ها

    private struct OrbSpec {
        let size: CGFloat
        let right: CGFloat?
        let left: CGFloat?
        let top: CGFloat
        let hi: UInt32
        let lo: UInt32
        let shadow: UInt32
        let title: String
        let big: String
        let bigSize: CGFloat
        let path: String
        let delay: Double
    }

    private var orbSpecs: [OrbSpec] {
        let st = home.o("stats")
        let hours = st.i("worked_hours")
        let days = hours / 8
        let rem = hours % 8
        let light = !dark
        return [
            OrbSpec(size: 178, right: 2, left: nil, top: 6,
                    hi: light ? 0xB9A3FF : 0x9B7BFF, lo: light ? 0x6D4FE0 : 0x4B2FC7, shadow: light ? 0x6D4FE0 : 0x6A4DFF,
                    title: "کارکرد این ماه", big: Fa.n(days) + " روز\nو " + Fa.n(rem) + " ساعت", bigSize: 26, path: "/employee/reports_monthly.php", delay: 0),
            OrbSpec(size: 118, right: nil, left: 20, top: 0,
                    hi: light ? 0xFFC999 : 0xFFB36B, lo: light ? 0xEA7A2A : 0xC2410C, shadow: light ? 0xEA7A2A : 0xFF7A2F,
                    title: "درخواست‌ها", big: Fa.n(st.i("requests_pending")), bigSize: 30, path: "/employee/reports_requests.php", delay: 0.8),
            OrbSpec(size: 104, right: nil, left: 70, top: 150,
                    hi: light ? 0x9DDCFF : 0x6FD0FF, lo: light ? 0x2F84E8 : 0x1663D6, shadow: light ? 0x2F84E8 : 0x2F8CFF,
                    title: "پروژه‌ها", big: Fa.n(home.a("projects").count), bigSize: 28, path: "/employee/my_projects.php", delay: 1.6),
            OrbSpec(size: 132, right: 36, left: nil, top: 168,
                    hi: light ? 0xFFB3D6 : 0xFF8FC1, lo: light ? 0xD9468F : 0xBE185D, shadow: light ? 0xD9468F : 0xFF4D9A,
                    title: "حقوق", big: "مشاهده فیش", bigSize: 15, path: "/employee/payslip.php", delay: 0.4)
        ]
    }

    private var orbsView: some View {
        let w = screenW - 32
        return ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { i in
                orb(orbSpecs[i], w: w)
            }
        }
        .frame(width: w, height: 300, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func orb(_ o: OrbSpec, w: CGFloat) -> some View {
        let x: CGFloat = o.right != nil ? (w - (o.right ?? 0) - o.size) : (o.left ?? 0)
        let g = RadialGradient(colors: [sk(o.hi), sk(o.lo)], center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: o.size * 0.85)
        return Button(action: { openWeb(o.path) }) {
            VStack(spacing: 2) {
                Text(o.title).font(.system(size: 12, weight: .bold)).foregroundColor(.white).opacity(0.95)
                Text(o.big).font(.system(size: o.bigSize, weight: .heavy)).foregroundColor(.white)
                    .multilineTextAlignment(.center).minimumScaleFactor(0.6).lineLimit(2)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
            .frame(width: o.size, height: o.size)
            .background(Circle().fill(g))
            .shadow(color: sk(o.shadow, dark ? 0.55 : 0.4), radius: 16, x: 0, y: 12)
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: x, y: o.top + (floatUp ? -9 : 0))
        .animation(Animation.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(o.delay), value: floatUp)
    }

    // MARK: - روز من

    private func evColor(_ k: String) -> Color {
        let light = !dark
        switch k {
        case "g": return sk(light ? 0x047857 : 0x6DF0C4)
        case "a": return sk(light ? 0xB45309 : 0xFFD166)
        case "b": return sk(light ? 0x1D4ED8 : 0x7CB4FF)
        case "p": return sk(light ? 0xBE185D : 0xFF8FC1)
        default: return sk(light ? 0x5B6591 : 0xB4BBE0)
        }
    }

    private var dayEvents: [DayEvent] {
        var out: [DayEvent] = []
        if let f = logs.first(where: { $0.s("type") == "check_in" }) {
            out.append(DayEvent(kind: "g", small: Fa.digits(f.s("time")), title: "ورود ثبت شد", sub: f.s("project_name"), path: ""))
        }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowStr = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        let nowEv = DayEvent(kind: "now", small: "", title: "اکنون", sub: "", path: "")
        var placed = false
        let today = home.a("plan_today")
        for it in today {
            let t = it.s("time")
            let od = it.b("overdue")
            if !placed && !t.isEmpty && t > nowStr && !od {
                out.append(nowEv)
                placed = true
            }
            let isTask = it.s("kind") == "task"
            let kind = od ? "a" : (isTask ? "b" : "p")
            let small = t.isEmpty ? (od ? "عقب‌افتاده" : "امروز") : Fa.digits(t)
            out.append(DayEvent(kind: kind, small: small, title: it.s("title"), sub: it.s("sub"),
                                path: isTask ? "/tasks/my_tasks.php" : "/tasks/personal.php"))
        }
        if !placed { out.append(nowEv) }
        for it in home.a("plan_tomorrow") {
            let t = it.s("time")
            let isTask = it.s("kind") == "task"
            out.append(DayEvent(kind: "m", small: t.isEmpty ? "فردا" : "فردا · " + Fa.digits(t), title: it.s("title"), sub: it.s("sub"),
                                path: isTask ? "/tasks/my_tasks.php" : "/tasks/personal.php"))
        }
        return out
    }

    private var dayView: some View {
        let evs = dayEvents
        return VStack(alignment: .leading, spacing: 0) {
            Text("روز من").font(.system(size: 17, weight: .heavy)).foregroundColor(nx.text).padding(.top, 8).padding(.bottom, 14)
            ForEach(evs) { e in
                eventRow(e)
            }
            if home.a("plan_today").isEmpty {
                Text("برای امروز برنامه‌ای ندارید 🎉").font(.system(size: 12)).foregroundColor(nx.muted).padding(.bottom, 14)
            }
            HStack {
                if home.b("tasks_enabled") {
                    Button(action: { openWeb("/tasks/my_tasks.php") }) {
                        Text("همهٔ دستورکارهای من ‹").font(.system(size: 12.5, weight: .bold)).foregroundColor(nx.blue)
                    }
                }
                Spacer()
                Button(action: { openWeb("/tasks/personal.php") }) {
                    Text("برنامهٔ شخصی ‹").font(.system(size: 12.5, weight: .bold)).foregroundColor(nx.blue)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRow(_ e: DayEvent) -> some View {
        let isNow = e.kind == "now"
        let col: Color = isNow ? sk(0xFFC233) : evColor(e.kind)
        return HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .top) {
                Capsule().fill(LinearGradient(colors: [sk(0xFFB36B), sk(0x7C4DFF, 0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3)
                if isNow {
                    Capsule().fill(sk(0xFFC233)).frame(width: 21, height: 3).padding(.top, 8)
                } else {
                    Circle().fill(col).frame(width: 13, height: 13)
                        .overlay(Circle().stroke(col.opacity(0.3), lineWidth: 5))
                        .padding(.top, 20)
                }
            }
            .frame(width: 22)
            if isNow {
                Text("اکنون").font(.system(size: 11.5, weight: .heavy)).foregroundColor(sk(0xE0A100))
                    .padding(.bottom, 14)
            } else {
                Button(action: { if !e.path.isEmpty { openWeb(e.path) } }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.small).font(.system(size: 12, weight: .heavy)).foregroundColor(col)
                        Text(e.title).font(.system(size: 14.5, weight: .bold)).foregroundColor(nx.text).multilineTextAlignment(.leading)
                        if !e.sub.isEmpty {
                            Text(e.sub).font(.system(size: 12)).foregroundColor(nx.muted).lineLimit(2).multilineTextAlignment(.leading)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(nx.card))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(nx.border, lineWidth: 1))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - آخرین درخواست‌ها

    private func reqIcon(_ t: String) -> String {
        if t.hasPrefix("forgot") || t.hasPrefix("attendance") { return "🕒" }
        switch t {
        case "leave": return "🏖️"
        case "mission": return "🧭"
        case "advance": return "💵"
        case "loan": return "🏦"
        case "transport": return "🚌"
        default: return "📝"
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "approved": return nx.green
        case "rejected": return nx.red
        default: return nx.orange
        }
    }

    private var recentView: some View {
        let items = home.a("recent_requests")
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("آخرین درخواست‌ها").font(.system(size: 17, weight: .heavy)).foregroundColor(nx.text)
                Spacer()
                Button(action: { openWeb("/employee/requests.php") }) {
                    Text("مشاهده همه").font(.system(size: 12.5, weight: .bold)).foregroundColor(nx.blue)
                }
            }
            .padding(.bottom, 4)
            ForEach(Array(items.enumerated()), id: \.offset) { _, r in
                requestRow(r)
            }
            if items.isEmpty {
                Text("درخواستی ثبت نکرده‌اید").font(.system(size: 12)).foregroundColor(nx.muted).padding(.vertical, 6).padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(nx.card))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(nx.border, lineWidth: 1))
    }

    private func requestRow(_ r: JSON) -> some View {
        let c = statusColor(r.s("status"))
        return VStack(spacing: 0) {
            Divider().background(nx.border)
            HStack(spacing: 12) {
                Text(reqIcon(r.s("type"))).font(.system(size: 16))
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(nx.bg))
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.s("title")).font(.system(size: 14, weight: .bold)).foregroundColor(nx.text)
                    Text(Fa.digits(r.s("sub"))).font(.system(size: 12)).foregroundColor(nx.muted)
                }
                Spacer(minLength: 4)
                Text(r.s("status_label")).font(.system(size: 11.5, weight: .bold)).foregroundColor(c)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(c.opacity(0.14)))
            }
            .padding(.vertical, 12)
        }
    }
}
