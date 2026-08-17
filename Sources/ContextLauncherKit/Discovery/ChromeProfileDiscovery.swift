import Foundation

public enum ChromeProfileDiscovery {
    public enum Error: Swift.Error, Equatable {
        case malformedMetadata
        case unreadableLocalState
    }

    private struct LocalState: Decodable {
        let profile: Profile?
    }

    private struct Profile: Decodable {
        let infoCache: [String: ProfileInfo]?

        enum CodingKeys: String, CodingKey { case infoCache = "info_cache" }
    }

    private struct ProfileInfo: Decodable {
        let name: String?
        let email: String?

        enum CodingKeys: String, CodingKey { case name, email = "user_name" }
    }

    public static func parse(localStateData: Data) throws -> [ChromeProfile] {
        do {
            let state = try JSONDecoder().decode(LocalState.self, from: localStateData)
            let infoCache = state.profile?.infoCache ?? [:]
            return infoCache.keys.sorted().map { directoryID in
                let info = infoCache[directoryID]!
                return ChromeProfile(directoryID: directoryID, name: info.name ?? directoryID, email: info.email)
            }
        } catch {
            throw Error.malformedMetadata
        }
    }

    public static func discover(localStateURL: URL) throws -> [ChromeProfile] {
        do {
            return try parse(localStateData: Data(contentsOf: localStateURL))
        } catch let error as Error {
            throw error
        } catch {
            throw Error.unreadableLocalState
        }
    }
}
