import Foundation
import Security

/// ذخیره‌ی امن توکن؛ AfterFirstUnlock یعنی وقتی برنامه در پس‌زمینه بیدار می‌شود هم خوانده می‌شود.
enum Keychain {
    private static let service = "ir.presino.app"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value = value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum Session {
    static var token: String? {
        get { Keychain.get("api_token") }
        set {
            Keychain.set(newValue, for: "api_token")
            NotificationCenter.default.post(name: .presinoSession, object: nil)
        }
    }

    /// نقش کاربر (employee یا یکی از نقش‌های مدیریتی)؛ خالی = هنوز مشخص نیست
    static var role: String {
        get { UserDefaults.standard.string(forKey: "session.role") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "session.role") }
    }

    static var userId: Int {
        get { UserDefaults.standard.integer(forKey: "session.uid") }
        set { UserDefaults.standard.set(newValue, forKey: "session.uid") }
    }

    static var isManager: Bool {
        let r = role
        return !r.isEmpty && r != "employee"
    }

    static var isEmployee: Bool { return role == "employee" }

    /// خروج کامل: توکن، نقش، داده‌های ذخیره‌شده و صف آفلاین پاک می‌شوند
    static func clear() {
        UserDefaults.standard.removeObject(forKey: "session.role")
        UserDefaults.standard.removeObject(forKey: "session.uid")
        UserDefaults.standard.removeObject(forKey: "cache.home")
        UserDefaults.standard.removeObject(forKey: "ns.last")
        OfflineQueue.shared.clearAll()
        RouteTracker.shared.reset()
        ReminderService.clearAll()
        token = nil
    }
}
