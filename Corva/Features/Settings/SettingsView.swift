import SwiftUI

struct SettingsView: View {
    @Environment(\.healthDataProvider) private var provider
    @Environment(AppSettings.self) private var settings
    @State private var model = SettingsViewModel()

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            List {
                Section {
                    ForEach(DataSource.allCases) { source in
                        DataSourceRow(source: source, status: model.status(for: source))
                    }
                } header: {
                    Text("Data sources")
                } footer: {
                    Text("Corva reads sleep, heart rate and activity data from connected sources.")
                }
                .listRowBackground(CorvaColor.surface)

                Section("Appearance") {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(AppSettings.Appearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(CorvaColor.surface)

                Section {
                    Stepper(value: $settings.age, in: 18...90) {
                        LabeledContent("Age", value: "\(settings.age)")
                    }
                    Picker("Sex", selection: $settings.sex) {
                        ForEach(BiologicalSex.allCases) { sex in
                            Text(sex.title).tag(sex)
                        }
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Used only to pick the reference values bio age compares you with.")
                }
                .listRowBackground(CorvaColor.surface)

                Section {
                    Picker("Currency", selection: $settings.currencyCode) {
                        ForEach(AppSettings.stakeCurrencies, id: \.self) { code in
                            Text(Locale.current.localizedString(forCurrencyCode: code) ?? code).tag(code)
                        }
                    }
                } header: {
                    Text("Pacts")
                } footer: {
                    Text("For new pacts. Payments aren’t connected yet, so no money moves.")
                }
                .listRowBackground(CorvaColor.surface)

                Section("Units") {
                    Picker("Temperature", selection: $settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    Picker("Distance", selection: $settings.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                }
                .listRowBackground(CorvaColor.surface)

                Section("About") {
                    LabeledContent("Version", value: model.version)
                    LabeledContent("Baseline window", value: "\(Baseline.windowDays) days")
                }
                .listRowBackground(CorvaColor.surface)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Settings")
            // The title sits in the top bar row, not on its own row below it.
            .toolbarTitleDisplayMode(.inlineLarge)
        }
        .task { await model.load(using: provider) }
    }
}

private struct DataSourceRow: View {
    let source: DataSource
    let status: ConnectionStatus?

    var body: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title).textStyle(.body)
                Text(source.subtitle).textStyle(.caption)
            }
            Spacer(minLength: Spacing.s)
            statusView
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .connected(let lastSync):
            VStack(alignment: .trailing, spacing: 2) {
                Text("Connected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CorvaColor.textPrimary)
                Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
                    .textStyle(.caption)
            }
        case .notConnected:
            Text("Not connected")
                .font(.subheadline)
                .foregroundStyle(CorvaColor.textTertiary)
        case nil:
            ProgressView()
        }
    }
}

#Preview {
    SettingsView()
        .corvaPreview()
}
