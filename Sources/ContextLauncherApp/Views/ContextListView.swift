import AppKit
import ContextLauncherKit
import SwiftUI

struct ContextListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedContextID) {
                Section("Contexts") {
                    ForEach(model.contexts) { context in
                        ContextRow(context: context)
                            .tag(context.id)
                    }
                }
            }
            .navigationTitle("Context Launcher")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        model.beginNewContext()
                    } label: {
                        Label("New Context", systemImage: "plus")
                    }
                    .help("Create a context")

                    Button {
                        model.showDiagnostics()
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                    .help("Show diagnostics")
                }
            }
        } detail: {
            detail
        }
        .onChange(of: model.selectedContextID) { id in
            if let id {
                model.beginEditing(id: id)
            }
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.showsOnboardingCompletion || model.needsOnboarding {
            OnboardingView()
        } else if model.showsDiagnostics {
            DiagnosticsView()
        } else if model.draft != nil {
            ContextEditorView(context: Binding(
                get: { model.draft! },
                set: { model.draft = $0 }
            ))
            .id(model.editorSessionID)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("Select a context")
                    .font(.title2)
                Text("Choose a context in the sidebar or create a new one.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ContextRow: View {
    let context: LauncherContext

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ContextIconView(icon: context.icon)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.name)
                    .fontWeight(.medium)
                if !context.subtitle.isEmpty {
                    Text(context.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var summary: String {
        let profile = context.chromeProfileID.map { "Chrome \($0)" } ?? "No Chrome"
        return "\(profile) · \(context.urls.count) URLs · \(context.vscodeProjects.count) projects · \(context.applications.count) apps"
    }
}

struct ContextIconView: View {
    let icon: ContextIcon

    var body: some View {
        switch icon {
        case let .symbol(name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundColor(.accentColor)
        case let .custom(path):
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
