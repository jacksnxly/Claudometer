import Domain

/// Application service: load every profile and fetch its usage.
///
/// Never throws — each profile's failure is captured individually so one bad
/// token (or a 429) can't sink the whole dashboard.
public struct RefreshUsageUseCase: Sendable {
    private let directory: any ProfileDirectory
    private let provider: any UsageProvider

    public init(directory: any ProfileDirectory, provider: any UsageProvider) {
        self.directory = directory
        self.provider = provider
    }

    public func execute() async -> [ProfileUsageResult] {
        let profiles: [Profile]
        do {
            profiles = try await directory.profiles()
        } catch {
            return []
        }

        var results: [ProfileUsageResult] = []
        for profile in profiles {
            do {
                let snapshot = try await provider.usage(for: profile)
                results.append(ProfileUsageResult(profile: profile, snapshot: snapshot, failure: nil))
            } catch {
                results.append(
                    ProfileUsageResult(profile: profile, snapshot: nil,
                                       failure: error.localizedDescription)
                )
            }
        }
        return results
    }
}
