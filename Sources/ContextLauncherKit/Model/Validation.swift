import Foundation

public enum ValidationField: String, Sendable {
    case id, name, subtitle, urls, vscodeProjects, applications
}

public struct ValidationIssue: Error, Equatable, Sendable {
    public let field: ValidationField
    public let message: String

    public init(field: ValidationField, message: String) {
        self.field = field
        self.message = message
    }
}

public enum ResourceValidator {
    public static func exists(_ url: URL, fileManager: FileManager = .default) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    public static func isValidExistingProject(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard url.isFileURL,
              let type = try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeDirectory
            || (type == .typeRegular && url.pathExtension.caseInsensitiveCompare("code-workspace") == .orderedSame)
    }

    public static func isValidExistingApplication(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard url.isFileURL,
              url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              let type = try? fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeDirectory
    }
}

public enum ContextValidator {
    public static func isValidID(_ id: String) -> Bool {
        id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
    }

    public static func validate(_ context: LauncherContext, among existing: [LauncherContext]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if !isValidID(context.id) {
            issues.append(ValidationIssue(field: .id, message: "ID must contain lowercase letters, numbers, and single hyphens only."))
        }
        if context.id == "new" {
            issues.append(ValidationIssue(field: .id, message: "ID 'new' is reserved for the New launcher."))
        }
        if existing.contains(where: { $0.id == context.id }) {
            issues.append(ValidationIssue(field: .id, message: "ID must be unique."))
        }
        if context.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ValidationIssue(field: .name, message: "Name must not be empty."))
        }
        if containsASCIIControlCharacter(context.name) {
            issues.append(ValidationIssue(field: .name, message: "Name must not contain ASCII control characters."))
        }
        if containsASCIIControlCharacter(context.subtitle) {
            issues.append(ValidationIssue(field: .subtitle, message: "Subtitle must not contain ASCII control characters."))
        }
        if context.urls.contains(where: { URL.validatedWebURL($0) == nil }) {
            issues.append(ValidationIssue(field: .urls, message: "URLs must use HTTP or HTTPS."))
        }
        if !context.urls.isEmpty && context.chromeProfileID?.isEmpty != false {
            issues.append(ValidationIssue(field: .urls, message: "Choose a Chrome profile before adding URLs."))
        }
        if context.vscodeProjects.contains(where: {
            !$0.isFileURL || (ResourceValidator.exists($0) && !ResourceValidator.isValidExistingProject($0))
        }) {
            issues.append(ValidationIssue(field: .vscodeProjects, message: "Existing VS Code projects must be folders or .code-workspace files."))
        }
        if context.applications.contains(where: {
            !$0.isFileURL
                || $0.pathExtension.caseInsensitiveCompare("app") != .orderedSame
                || (ResourceValidator.exists($0) && !ResourceValidator.isValidExistingApplication($0))
        }) {
            issues.append(ValidationIssue(field: .applications, message: "Applications must be actual .app bundle directories when they exist."))
        }
        return issues
    }

    private static func containsASCIIControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
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
