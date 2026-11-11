import Foundation

enum Config {
    static let host = "presino.ir"
    static let startURL = URL(string: "https://presino.ir/?pwa=1")!
    static let apiBase = "https://presino.ir/api_mobile/"
    /// مدت بیرون ماندن از محدوده تا ثبت خروج خودکار (همان ۳۰ دقیقه‌ی اپ اندروید و سرور)
    static let autoSeconds: TimeInterval = 30 * 60
}

extension Notification.Name {
    static let presinoReload = Notification.Name("presino.reload")
}
