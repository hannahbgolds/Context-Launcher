import Foundation

public enum ContextLauncherRoute: Equatable, Sendable {
    case new
    case edit(String)

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "contextlauncher",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else { return nil }

        switch (components.host?.lowercased(), components.path) {
        case ("new", ""), ("new", "/"):
            self = .new
        case let ("edit", path):
            let pieces = path.split(separator: "/", omittingEmptySubsequences: true)
            guard pieces.count == 1 else { return nil }
            let id = String(pieces[0])
            guard ContextValidator.isValidID(id) else { return nil }
            self = .edit(id)
        default:
            return nil
        }
    }

    public var url: URL? {
        var components = URLComponents()
        components.scheme = "contextlauncher"
        switch self {
        case .new:
            components.host = "new"
        case let .edit(id):
            guard ContextValidator.isValidID(id) else { return nil }
            components.host = "edit"
            components.path = "/\(id)"
        }
        return components.url
    }
}
