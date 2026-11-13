import SwiftUI

enum OnboardingTabs: Int, Identifiable, CaseIterable {
    var id: Self { self }

    case first = 0,
         second = 1,
         third = 2

    var bgImage: String {
        switch self {
        case .first:  "ONB_1"
        case .second: "ONB_2"
        case .third:  "ONB_3"
        }
    }

    var titleTextes: [(text: LocalizedStringResource, color: LinearGradient)] {
        switch self {
        case .first:
            [
                (
                    text: "Favorite Content",
                    color: LinearGradient(colors: [.white], startPoint: .leading, endPoint: .trailing)
                ),
                (
                    text: "Anywhere",
                    color: LinearGradient(
                        stops: [
                            .init(color: .init(hex: "5B9BFF"), location: 0),
                            .init(color: .init(hex: "5B9BFF"), location: 0.54),
                            .init(color: .init(hex: "8CB9FF"), location: 0.75),
                            .init(color: .init(hex: "5B9BFF"), location: 0.93)
                        ], startPoint: .leading, endPoint: .trailing
                    ),
                ),
                (
                    text: "You Go",
                    color: LinearGradient(colors: [.white], startPoint: .leading, endPoint: .trailing)
                )
            ]
        case .second:
            [
                (
                    text: "Bring Your",
                    color: LinearGradient(colors: [.white], startPoint: .leading, endPoint: .trailing)
                ),
                (
                    text: "Own Server.",
                    color: LinearGradient(
                        stops: [
                            .init(color: .init(hex: "5B9BFF"), location: 0),
                            .init(color: .init(hex: "5B9BFF"), location: 0.54),
                            .init(color: .init(hex: "8CB9FF"), location: 0.75),
                            .init(color: .init(hex: "5B9BFF"), location: 0.93)
                        ], startPoint: .leading, endPoint: .trailing
                    ),
                )
            ]
        case .third:
            [
                (
                    text: "Nothing Stored.",
                    color: LinearGradient(colors: [.white], startPoint: .leading, endPoint: .trailing)
                ),
                (
                    text: "Nothing Shared. Ever.",
                    color: LinearGradient(
                        stops: [
                            .init(color: .init(hex: "5B9BFF"), location: 0),
                            .init(color: .init(hex: "5B9BFF"), location: 0.54),
                            .init(color: .init(hex: "8CB9FF"), location: 0.75),
                            .init(color: .init(hex: "5B9BFF"), location: 0.93)
                        ], startPoint: .leading, endPoint: .trailing
                    ),
                )
            ]
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .first:  "Browse, stream, and connect without\nborders or unnecessary restrictions."
        case .second: "Powerful encryption keeps your browsing\nprotected on every network, even public Wi-Fi."
        case .third:  "Our strict no-logs policy means your browsing\nhistory is never stored."
        }
    }
    
    var nextBtnTitle: LocalizedStringResource {
        switch self {
        case .first:
            "Get started"
        default:
            "Next"
        }
    }
}
