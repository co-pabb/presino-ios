import Foundation

struct QueuedItem: Codable {
    var id: String
    var userId: Int
    var path: String
    var body: String
    var label: String
    var createdAt: Double
}

/// صف ارسال آفلاین: ثبت ورود/خروجی که بدون اینترنت انجام شده در گوشی می‌ماند و به‌محض اتصال (یا باز شدن برنامه،
/// یا بیدار شدن در پس‌زمینه) با ساعت واقعیِ ثبت به سرور فرستاده می‌شود.
final class OfflineQueue {
    static let shared = OfflineQueue()

    private let lock = NSLock()
    private var items: [QueuedItem] = []
    private var flushing = false
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("offline_queue.json")
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([QueuedItem].self, from: data) {
            items = list
        }
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    func enqueue(path: String, body: JSON, label: String) {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? "{}"
        lock.lock()
        items.append(QueuedItem(id: UUID().uuidString, userId: Session.userId, path: path, body: text,
                                label: label, createdAt: Date().timeIntervalSince1970))
        save()
        lock.unlock()
        refreshCount()
    }

    func clearAll() {
        lock.lock()
        items.removeAll()
        save()
        lock.unlock()
        refreshCount()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) {
            try? d.write(to: fileURL, options: .atomic)
        }
    }

    private func first() -> QueuedItem? {
        lock.lock()
        defer { lock.unlock() }
        return items.first
    }

    private func remove(_ id: String) {
        lock.lock()
        items.removeAll { $0.id == id }
        save()
        lock.unlock()
    }

    private func beginFlush() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if flushing { return false }
        flushing = true
        return true
    }

    private func endFlush() {
        lock.lock()
        flushing = false
        lock.unlock()
    }

    private func refreshCount() {
        let n = count
        DispatchQueue.main.async { AppState.shared.queued = n }
    }

    /// ارسال همه‌ی موارد به ترتیب؛ با اولین قطعی شبکه یا خطای سرور (۵xx) متوقف می‌شود. تعداد ارسال‌شده را برمی‌گرداند.
    @discardableResult
    func flush() async -> Int {
        guard Session.token != nil else { return 0 }
        if !beginFlush() { return 0 }
        var sent = 0
        while let item = first() {
            // مورد متعلق به کاربر دیگری (ورود با حساب دیگر) هرگز با این توکن فرستاده نمی‌شود
            if item.userId != 0, Session.userId != 0, item.userId != Session.userId {
                remove(item.id)
                continue
            }
            let body = (try? JSONSerialization.jsonObject(with: Data(item.body.utf8))) as? JSON ?? [:]
            guard let r = await API.call(item.path, method: "POST", body: body) else { break }   // اینترنت نیست
            if r.status == 401 { break }
            if r.status >= 200 && r.status < 300 {
                remove(item.id)
                sent += 1
                continue
            }
            if r.status >= 500 { break }
            // سرور پذیرفت ولی رد کرد (مثلاً تکراری یا خارج از محدوده)
            remove(item.id)
            if r.status != 409 {
                let msg = r.json.s("message")
                NotificationHelper.local(title: "❌ \(item.label) پذیرفته نشد", body: msg.isEmpty ? "سرور این ثبت آفلاین را قبول نکرد." : msg, target: "")
            }
        }
        endFlush()
        refreshCount()
        if sent > 0 {
            NotificationHelper.local(title: "✅ ثبت‌های آفلاین ارسال شد", body: "\(sent) مورد ثبت‌شده در حالت آفلاین به سرور رسید.", target: "")
            await AppState.shared.reload()
        }
        return sent
    }
}
