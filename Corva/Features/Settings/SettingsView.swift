import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = SettingsViewModel()

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            List {
                AccountSection()

                DataSourcesSection()

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
                    Picker("Age", selection: $settings.age) {
                        Text("Not set").tag(Int?.none)
                        ForEach(18...90, id: \.self) { age in
                            Text("\(age)").tag(Int?.some(age))
                        }
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
    }
}

#Preview {
    SettingsView()
        .corvaPreview()
}
