import Foundation

public enum ContextIcon: Codable, Equatable, Sendable {
    case symbol(String)
    case custom(String)
}

public struct LauncherContext: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var icon: ContextIcon
    public var chromeProfileID: String?
    public var urls: [URL]
    public var vscodeProjects: [URL]
    public var applications: [URL]

    public init(
        id: String,
        name: String,
        subtitle: String = "",
        icon: ContextIcon = .symbol("folder"),
        chromeProfileID: String? = nil,
        urls: [URL] = [],
        vscodeProjects: [URL] = [],
        applications: [URL] = []
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
        self.chromeProfileID = chromeProfileID
        self.urls = urls
        self.vscodeProjects = vscodeProjects
        self.applications = applications
    }
}

public struct ChromeProfile: Codable, Equatable, Sendable {
    public let directoryID: String
    public let name: String
    public let email: String?

    public init(directoryID: String, name: String, email: String? = nil) {
        self.directoryID = directoryID
        self.name = name
        self.email = email
    }
}
