import ContextLauncherKit
import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diagnostics")
                        .font(.largeTitle)
                    Text("Check discovery, configuration, and Spotlight launcher health.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { model.refreshDiagnostics() }
                Button("Synchronize Launchers") { model.synchronizeLaunchers() }
                    .buttonStyle(.borderedProminent)
            }

            Table(rows) {
                TableColumn("Status") { row in
                    Label(row.diagnostic.status.rawValue.capitalized, systemImage: symbol(for: row.diagnostic.status))
                        .foregroundStyle(color(for: row.diagnostic.status))
                }
                .width(min: 90, ideal: 120)
                TableColumn("Check") { row in
                    Text(row.diagnostic.code)
                }
                .width(min: 120, ideal: 170)
                TableColumn("Details") { row in
                    Text(row.diagnostic.message)
                }
            }
        }
        .padding(24)
        .navigationTitle("Diagnostics")
        .onAppear { model.refreshDiagnostics() }
    }

    private var rows: [DiagnosticRow] {
        model.diagnostics.enumerated().map { DiagnosticRow(id: $0.offset, diagnostic: $0.element) }
    }

    private func symbol(for status: Diagnostic.Status) -> String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private func color(for status: Diagnostic.Status) -> Color {
        switch status {
        case .pass: return .green
        case .warning: return .orange
        case .failure: return .red
        }
    }
}

private struct DiagnosticRow: Identifiable {
    let id: Int
    let diagnostic: Diagnostic
}
