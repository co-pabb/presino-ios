import Foundation
import BackgroundTasks
import Network
import UIKit

/// کارهای پس‌زمینه: iOS هر چند وقت یک‌بار (به‌تشخیص خودش) برنامه را بیدار می‌کند؛ هر بیدار شدن (از جمله رویداد
/// موقعیت/ژئوفنس) برای ارسال صف آفلاین و گرفتن اعلان‌های تازه استفاده می‌شود.
enum BackgroundJobs {
    private static var lastWake = Date.distantPast

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Config.refreshTaskId, using: nil) { task in
            guard let t = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(t)
        }
    }

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: Config.refreshTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task {
            await run()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    static func run() async {
        guard Session.token != nil else { return }
        _ = await OfflineQueue.shared.flush()
        await NotificationService.shared.poll()
    }

    /// بیدار شدنِ برنامه در پس‌زمینه (رویداد موقعیت): حداکثر هر ۲ دقیقه یک‌بار اجرا می‌شود
    static func wake() {
        if Date().timeIntervalSince(lastWake) < 120 { return }
        lastWake = Date()
        Task { await run() }
    }
}

/// وصل شدن دوباره‌ی اینترنت ← ارسال صف آفلاین و تازه‌سازی صفحه‌ی اصلی
final class NetWatcher {
    static let shared = NetWatcher()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ir.presino.net")
    private var wasUp = true

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            let wasDown = self?.wasUp == false
            self?.wasUp = up
            if up && wasDown && Session.token != nil {
                Task {
                    _ = await OfflineQueue.shared.flush()
                    await AppState.shared.reload()
                    await NotificationService.shared.poll()
                }
            }
        }
        monitor.start(queue: queue)
    }
}
