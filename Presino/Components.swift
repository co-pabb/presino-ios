import SwiftUI

enum Brand {
    static let blue = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let green = Color(red: 0.086, green: 0.639, blue: 0.290)
    static let red = Color(red: 0.863, green: 0.149, blue: 0.149)
    static let orange = Color(red: 0.918, green: 0.345, blue: 0.047)
}

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = Brand.blue

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline)
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
}

struct LinkTile: View {
    let title: String
    let icon: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(Brand.blue)
                        .frame(width: 44, height: 44)
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Brand.red)
                            .clipShape(Capsule())
                    }
                }
                Text(title)
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct Banner: View {
    let text: String
    var icon: String = "info.circle.fill"
    var color: Color = Brand.blue
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let t = actionTitle, let a = action {
                    Button(action: a) {
                        Text(t).font(.footnote.bold()).foregroundColor(color)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
        .cornerRadius(12)
    }
}

/// سطر «عنوان + زیرعنوان + نشان» برای فهرست‌ها
struct RowItem: View {
    let icon: String
    let title: String
    let sub: String
    let badge: String
    var tint: Color = Brand.blue

    var body: some View {
        HStack(spacing: 10) {
            Text(icon).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).lineLimit(2)
                if !sub.isEmpty {
                    Text(sub).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if !badge.isEmpty {
                Text(badge)
                    .font(.caption.bold())
                    .foregroundColor(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}
