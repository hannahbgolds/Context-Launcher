import Foundation

public protocol JavaScriptRunning: AnyObject {
    func run(script: String, arguments: [String]) throws -> String
}

public enum OsaScriptRunnerError: LocalizedError {
    case nonzeroExit(status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case let .nonzeroExit(status, message):
            return "osascript exited with status \(status): \(message)"
        }
    }
}

public final class OsaScriptRunner: JavaScriptRunning {
    public init() {}

    public func run(script: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script, "--"] + arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw OsaScriptRunnerError.nonzeroExit(
                status: process.terminationStatus,
                message: String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}

/// Best-effort Chrome targeting. It acts only when accessibility exposes one
/// unambiguous toolbar avatar whose label exactly names the configured profile.
/// Any missing permission, localization difference, or ambiguity returns false
/// so ContextLauncher can use the supported structured `open` fallback.
public final class ChromeAppleScriptWindowTargeter: ChromeWindowTargeting {
    private let profiles: [ChromeProfile]
    private let runner: JavaScriptRunning

    public init(profiles: [ChromeProfile]? = nil, runner: JavaScriptRunning = OsaScriptRunner()) {
        if let profiles {
            self.profiles = profiles
        } else {
            let localState = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
            self.profiles = (try? ChromeProfileDiscovery.discover(localStateURL: localState)) ?? []
        }
        self.runner = runner
    }

    public func open(urls: [URL], inProfile profileID: String) throws -> Bool {
        guard let profile = profiles.first(where: { $0.directoryID == profileID }),
              profiles.filter({ $0.name == profile.name }).count == 1,
              !profile.name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              urls.allSatisfy({ URL.validatedWebURL($0) != nil }) else {
            return false
        }
        let output = try runner.run(
            script: Self.script,
            arguments: [profile.name] + urls.map(\.absoluteString)
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "targeted"
    }

    static let script = #"""
    function attribute(element, name) {
        try { return String(element.attributes.byName(name).value()); }
        catch (_) { return ""; }
    }

    function isToolbarAvatar(element) {
        if (attribute(element, "AXRole") !== "AXButton") return false;
        const identifier = attribute(element, "AXIdentifier").toLowerCase();
        if (identifier.indexOf("avatar") < 0 && identifier.indexOf("profile") < 0) return false;
        let parent = element;
        for (let depth = 0; depth < 10; depth += 1) {
            try { parent = parent.parent(); } catch (_) { return false; }
            const role = attribute(parent, "AXRole");
            if (role === "AXToolbar") return true;
            if (role === "AXWindow") return false;
        }
        return false;
    }

    function run(argv) {
        if (argv.length < 1) return "not-targeted";
        const profileName = argv[0];
        const urls = argv.slice(1);
        const labels = [profileName, "Profile " + profileName, "Profile, " + profileName, profileName + " profile"];
        const systemEvents = Application("System Events");
        const chrome = systemEvents.applicationProcesses.byName("Google Chrome");
        try { if (!chrome.exists()) return "not-targeted"; }
        catch (_) { return "not-targeted"; }

        const matches = [];
        const windows = chrome.windows();
        for (let index = 0; index < windows.length; index += 1) {
            let contents;
            try { contents = windows[index].entireContents(); }
            catch (_) { continue; }
            const found = contents.some(function (element) {
                if (!isToolbarAvatar(element)) return false;
                const values = [attribute(element, "AXTitle"), attribute(element, "AXDescription"), attribute(element, "AXHelp")];
                return values.some(function (value) { return labels.indexOf(value) >= 0; });
            });
            if (found) matches.push(windows[index]);
        }
        if (matches.length !== 1) return "not-targeted";

        try {
            matches[0].actions.byName("AXRaise").perform();
            chrome.frontmost = true;
            delay(0.15);
            urls.forEach(function (url) {
                systemEvents.keystroke("t", { using: "command down" });
                delay(0.05);
                systemEvents.keystroke(url);
                systemEvents.keyCode(36);
            });
            return "targeted";
        } catch (_) {
            return "not-targeted";
        }
    }
    """#
}
