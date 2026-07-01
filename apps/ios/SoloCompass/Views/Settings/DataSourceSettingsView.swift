import SwiftUI

/// Developer-only configuration for the explore POI pipeline's base data
/// sources, reachable from `DeveloperOptionsView`. Three controls:
///
///   1. **Source policy** — compile the pipeline with Amap only, OpenMap only,
///      or both (region-routed). Writes `DataSourceSettings.policy`, read live
///      by `EnrichmentAgent.basePOIs`.
///   2. **Fetch count** — how many POIs each base source pulls per explore
///      call (`DataSourceSettings.poiFetchLimit`). Applied to the Amap /
///      Overpass services on the next `MapViewModel` construction.
///   3. **Connectivity test** — fire one minimal real request per provider via
///      `DataSourceProbe` and show ok/failed + latency, so a tester can verify
///      each API is reachable and its key valid without reading Console.
///
/// Nothing here is user-reachable: the parent panel is gated on the tester
/// unlock. Changes take effect without a rebuild.
struct DataSourceSettingsView: View {
    @State private var policy: DataSourcePolicy = DataSourceSettings.policy
    @State private var fetchLimit: Int = DataSourceSettings.poiFetchLimit
    @State private var probeStates: [DataSourceKind: ProbeState] = [:]

    /// Per-provider probe lifecycle for the "Test connection" rows.
    private enum ProbeState: Equatable {
        case idle
        case running
        case done(DataSourceProbe.Result)
    }

    var body: some View {
        List {
            policySection
            fetchCountSection
            connectivitySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("dev.dataSource.title", comment: "Data sources"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Policy

    private var policySection: some View {
        Section {
            Picker(
                NSLocalizedString("dev.dataSource.policy.label", comment: "Compile with"),
                selection: $policy
            ) {
                ForEach(DataSourcePolicy.allCases) { option in
                    Text(NSLocalizedString(option.titleKey, comment: "Data source policy")).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: policy) { _, newValue in
                DataSourceSettings.policy = newValue
                Haptics.selection()
            }
        } header: {
            header("point.3.connected.trianglepath.dotted",
                   NSLocalizedString("dev.dataSource.policy.header", comment: "Source policy"))
        } footer: {
            Text(NSLocalizedString("dev.dataSource.policy.footer", comment: "Policy footer"))
        }
    }

    // MARK: - Fetch count

    private var fetchCountSection: some View {
        Section {
            Stepper(value: $fetchLimit,
                    in: DataSourceSettings.poiFetchLimitRange,
                    step: 5) {
                HStack {
                    Image(systemName: "dial.medium")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.indigo, in: RoundedRectangle(cornerRadius: 7))
                    Text(NSLocalizedString("dev.dataSource.fetchCount.label", comment: "POIs per source"))
                    Spacer()
                    Text("\(fetchLimit)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .onChange(of: fetchLimit) { _, newValue in
                DataSourceSettings.poiFetchLimit = newValue
                Haptics.selection()
            }
        } header: {
            header("slider.horizontal.3",
                   NSLocalizedString("dev.dataSource.fetchCount.header", comment: "Fetch count"))
        } footer: {
            Text(NSLocalizedString("dev.dataSource.fetchCount.footer", comment: "Fetch count footer"))
        }
    }

    // MARK: - Connectivity

    private var connectivitySection: some View {
        Section {
            ForEach(DataSourceKind.allCases) { kind in
                connectivityRow(kind)
            }
        } header: {
            header("wifi",
                   NSLocalizedString("dev.dataSource.probe.header", comment: "Connectivity"))
        } footer: {
            Text(NSLocalizedString("dev.dataSource.probe.footer", comment: "Connectivity footer"))
        }
    }

    private func connectivityRow(_ kind: DataSourceKind) -> some View {
        let state = probeStates[kind] ?? .idle
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: kind == .amap ? "map" : "globe.asia.australia")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(kind == .amap ? Color.green : Color.blue,
                                in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString(kind.titleKey, comment: "Data source name"))
                        .font(.body)
                    if !kind.isEnabledByPolicy {
                        Text(NSLocalizedString("dev.dataSource.probe.disabled", comment: "Disabled by policy"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                testButton(kind: kind, state: state)
            }
            resultRow(state)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func testButton(kind: DataSourceKind, state: ProbeState) -> some View {
        if state == .running {
            ProgressView()
        } else {
            Button(NSLocalizedString("dev.dataSource.probe.test", comment: "Test")) {
                runProbe(kind)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func resultRow(_ state: ProbeState) -> some View {
        if case let .done(result) = state {
            HStack(spacing: 6) {
                Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(result.ok ? .green : .red)
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let ms = result.latencyMs {
                    Spacer()
                    Text("\(ms) ms")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 40)
        }
    }

    private func runProbe(_ kind: DataSourceKind) {
        probeStates[kind] = .running
        Haptics.selection()
        Task {
            let result = await DataSourceProbe.probe(kind)
            probeStates[kind] = .done(result)
            Haptics.notify(result.ok ? .success : .error)
        }
    }

    // MARK: - Helpers

    private func header(_ symbol: String, _ label: String) -> some View {
        Label(label, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationStack {
        DataSourceSettingsView()
    }
}
