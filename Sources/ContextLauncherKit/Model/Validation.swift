import Foundation

public enum ValidationField: String, Sendable {
    case id, name, urls, vscodeProjects, applications
}

public struct ValidationIssue: Error, Equatable, Sendable {
    public let field: ValidationField
    public let message: String

    public init(field: ValidationField, message: String) {
        self.field = field
        self.message = message
    }
}

public enum ContextValidator {
    public static func validate(_ context: LauncherContext, among existing: [LauncherContext]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if context.id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) == nil {
            issues.append(ValidationIssue(field: .id, message: "ID must contain lowercase letters, numbers, and single hyphens only."))
        }
        if existing.contains(where: { $0.id == context.id }) {
            issues.append(ValidationIssue(field: .id, message: "ID must be unique."))
        }
        if context.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ValidationIssue(field: .name, message: "Name must not be empty."))
        }
        if context.urls.contains(where: { URL.validatedWebURL($0) == nil }) {
            issues.append(ValidationIssue(field: .urls, message: "URLs must use HTTP or HTTPS."))
        }
        if context.vscodeProjects.contains(where: { !$0.isFileURL }) {
            issues.append(ValidationIssue(field: .vscodeProjects, message: "VS Code projects must be file URLs."))
        }
        if context.applications.contains(where: { !$0.isFileURL || $0.pathExtension.caseInsensitiveCompare("app") != .orderedSame }) {
            issues.append(ValidationIssue(field: .applications, message: "Applications must be .app file URLs."))
        }
        return issues
    }
}

public extension URL {
    static func validatedWebURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https"), url.host != nil else {
            return nil
        }
        return url
    }
}
