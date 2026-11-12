import Foundation

/// پاسخ‌های JSON سرور (همان ساختار api_mobile)
typealias JSON = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func s(_ k: String) -> String {
        if let v = self[k] as? String { return v }
        if let n = self[k] as? NSNumber { return n.stringValue }
        return ""
    }

    func i(_ k: String) -> Int {
        if let n = self[k] as? NSNumber { return n.intValue }
        if let t = self[k] as? String, let v = Int(t) { return v }
        return 0
    }

    func d(_ k: String) -> Double? {
        if let n = self[k] as? NSNumber { return n.doubleValue }
        if let t = self[k] as? String, let v = Double(t) { return v }
        return nil
    }

    func b(_ k: String) -> Bool {
        if let n = self[k] as? NSNumber { return n.boolValue }
        if let t = self[k] as? String { return t == "1" || t == "true" }
        return false
    }

    func a(_ k: String) -> [JSON] {
        return self[k] as? [JSON] ?? []
    }

    func o(_ k: String) -> JSON {
        return self[k] as? JSON ?? [:]
    }
}

/// قالب تاریخ/ساعت سرور (میلادی، ساعت محلی گوشی؛ همان قالب اپ اندروید)
enum Fmt {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f
    }

    static func dt(_ date: Date) -> String { return make("yyyy-MM-dd HH:mm:ss").string(from: date) }
    static func ymd(_ date: Date) -> String { return make("yyyy-MM-dd").string(from: date) }
    static func hm(_ date: Date) -> String { return make("HH:mm").string(from: date) }
    static func parse(_ s: String) -> Date? { return make("yyyy-MM-dd HH:mm").date(from: s) }
}
