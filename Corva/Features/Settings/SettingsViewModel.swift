import Foundation
import Observation

@Observable
final class SettingsViewModel {
    private(set) var statuses: [DataSource: ConnectionStatus] = [:]

    func load(using provider: any HealthDataProvider) async {
        var statuses: [DataSource: ConnectionStatus] = [:]
        for source in DataSource.allCases {
            statuses[source] = await provider.connectionStatus(for: source)
        }
        self.statuses = statuses
    }

    func status(for source: DataSource) -> ConnectionStatus? {
        statuses[source]
    }

    var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}
