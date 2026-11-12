import Foundation

enum Config {
    static let host = "presino.ir"
    static let webBase = "https://presino.ir"
    static let startURL = URL(string: "https://presino.ir/?pwa=1")!
    static let apiBase = "https://presino.ir/api_mobile/"
    /// مدت بیرون ماندن از محدوده تا ثبت خروج خودکار (همان ۳۰ دقیقه‌ی اپ اندروید و سرور)
    static let autoSeconds: TimeInterval = 30 * 60
    /// شناسه‌ی کار پس‌زمینه (باید در Info.plist هم باشد)
    static let refreshTaskId = "ir.presino.app.refresh"
}

extension Notification.Name {
    static let presinoReload = Notification.Name("presino.reload")
    /// ورود یا خروج کاربر (تغییر توکن)
    static let presinoSession = Notification.Name("presino.session")
    /// باز کردن یک صفحه‌ی وب در تب «بخش‌ها»؛ userInfo["path"]
    static let presinoOpenPath = Notification.Name("presino.openPath")
    /// لمس یک اعلان؛ userInfo["target"]
    static let presinoOpenTarget = Notification.Name("presino.openTarget")
}
