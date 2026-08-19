import Foundation

public enum StarterContexts {
    public static let all: [LauncherContext] = [
        LauncherContext(id: "uni", name: "Uni", subtitle: "University", icon: .symbol("graduationcap")),
        LauncherContext(id: "leet", name: "Leet", subtitle: "Practice", icon: .symbol("chevron.left.forwardslash.chevron.right")),
        LauncherContext(id: "work", name: "Work", subtitle: "Work", icon: .symbol("briefcase")),
        LauncherContext(id: "org", name: "Org", subtitle: "Organization", icon: .symbol("person.3"))
    ]
}

public enum OnboardingState {
    public static func needsOnboarding(contexts: [LauncherContext], setupPending: Bool = false) -> Bool {
        setupPending || contexts.isEmpty
    }
}
