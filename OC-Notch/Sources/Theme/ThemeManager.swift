import Foundation
import Observation

extension Notification.Name {
    static let notchThemeDidChange = Notification.Name("notchThemeDidChange")
}

enum NotchTheme: String, CaseIterable, Identifiable, Sendable {
    case classic
    case neo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classique"
        case .neo: return "Neo"
        }
    }
}

@MainActor
@Observable
final class ThemeManager {
    @MainActor static let shared = ThemeManager()

    private static let storageKey = "OCNotch.selectedTheme"

    var current: NotchTheme {
        didSet {
            guard oldValue != current else { return }
            UserDefaults.standard.set(current.rawValue, forKey: Self.storageKey)
            NotificationCenter.default.post(name: .notchThemeDidChange, object: current)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let stored = NotchTheme(rawValue: raw) {
            self.current = stored
        } else {
            self.current = .neo
        }
    }
}
