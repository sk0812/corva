import SwiftUI

/// Sets up an experiment: what you're changing, how to compare, what to measure, how long.
struct NewExperimentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ExperimentStore.self) private var store
    @Environment(\.healthDataProvider) private var provider
    @Environment(\.metricFormatter) private var format
    @State private var title: String
    @State private var design: Experiment.Design
    @State private var outcomes: [Metric] = [.recovery, .hrv, .sleep]
    @State private var length = 21
    /// Recent history, for estimating what each length can detect.
    @State private var history: [DailySummary] = []

    init(title: String = "", design: Experiment.Design = .randomised) {
        _title = State(initialValue: title)
        _design = State(initialValue: design)
    }

    private static let suggestions: [(title: String, design: Experiment.Design)] = [
        ("No caffeine after 2 PM", .randomised),
        ("Evening alcohol", .onOff),
        ("Magnesium before bed", .randomised),
        ("Screens off by 10 PM", .randomised),
        ("Late workout", .onOff),
    ]
    private static let measurable: [Metric] = [.recovery, .hrv, .sleep, .restingHeartRate, .respiratoryRate, .skinTemperature]
    private static let lengths = [14, 21, 28, 42]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. No caffeine after 2 PM", text: $title)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xs) {
                            ForEach(Self.suggestions, id: \.title) { suggestion in
                                Button(suggestion.title) {
                                    title = suggestion.title
                                    design = suggestion.design
                                }
                                .buttonStyle(.glass)
                                .font(.footnote)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.m, bottom: Spacing.xs, trailing: Spacing.m))
                } header: {
                    Text("What are you changing?")
                }

                Section {
                    Picker("Design", selection: $design) {
                        ForEach(Experiment.Design.allCases) { design in
                            Text(design.title).tag(design)
                        }
                    }
                } header: {
                    Text("How to compare")
                } footer: {
                    Text(design.explanation)
                }

                Section {
                    ForEach(Self.measurable) { metric in
                        Toggle(metric.title, isOn: binding(for: metric))
                    }
                } header: {
                    Text("Measure")
                } footer: {
                    Text("The first one you pick is the headline. Pick a few: each extra measure is another chance of a fluke.")
                }

                Section {
                    Picker("Length", selection: $length) {
                        ForEach(Self.lengths, id: \.self) { days in
                            Text("\(days) days").tag(days)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Length")
                } footer: {
                    Text(lengthFooter)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CorvaColor.background)
            .task { history = (try? await provider.summaries(endingOn: .now, count: Baseline.windowDays)) ?? [] }
            .navigationTitle("New experiment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", role: .confirm) {
                        let calendar = Calendar.current
                        let start = calendar.startOfDay(for: .now)
                        store.add(Experiment(
                            title: title.trimmingCharacters(in: .whitespaces),
                            design: design,
                            start: start,
                            length: length,
                            outcomes: outcomes,
                            taggedEvenings: design == .randomised
                                ? Experiment.randomPlan(start: start, length: length, calendar: calendar)
                                : []
                        ))
                        dismiss()
                    }
                    .tint(CorvaColor.bioAge)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || outcomes.isEmpty)
                }
            }
        }
    }

    private var lengthFooter: String {
        var text = design == .randomised
            ? "Starts tonight. Corva shows each evening whether it’s an ON or OFF night."
            : "Starts tonight. Longer experiments can detect smaller effects."
        if let metric = outcomes.first {
            let values = history.compactMap(metric.value(in:))
            let spread = Statistics.standardDeviation(values)
            if values.count >= Baseline.minimumDays, spread > 0 {
                let detectable = ExperimentAnalysis.plannedSensitivity(design: design, length: length, standardDeviation: spread)
                text += " Over \(length) days it should catch a change of about ±\(format.valueWithUnit(detectable, for: metric)) in \(metric.title)."
            }
        }
        return text
    }

    /// Keeps selection order, so the first metric picked stays the headline.
    private func binding(for metric: Metric) -> Binding<Bool> {
        Binding {
            outcomes.contains(metric)
        } set: { isOn in
            if isOn {
                if !outcomes.contains(metric) { outcomes.append(metric) }
            } else {
                outcomes.removeAll { $0 == metric }
            }
        }
    }
}

#Preview {
    NewExperimentView()
        .corvaPreview()
}
