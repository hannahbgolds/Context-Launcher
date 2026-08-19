import ContextLauncherKit
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importsProjects = false
    @State private var projectContextID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.showsOnboardingCompletion {
                    completion
                } else {
                    welcome
                    discovery
                    starters
                    HStack {
                        Spacer()
                        Button {
                            Task { await model.completeOnboarding() }
                        } label: {
                            if model.isSynchronizingLaunchers {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Creating Launchers…")
                                }
                            } else {
                                Text("Create Contexts and Launchers")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.isSynchronizingLaunchers)
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(36)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Welcome")
        .fileImporter(
            isPresented: $importsProjects,
            allowedContentTypes: [.folder, Self.workspaceType],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                addProjects(urls)
            case let .failure(error):
                model.presentError("Couldn’t select project", message: error.localizedDescription)
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("Welcome to Context Launcher")
                .font(.largeTitle.bold())
            Text("Create Spotlight-searchable launchers that open the Chrome profile, URLs, projects, and applications you use together.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var discovery: some View {
        GroupBox("Discovery") {
            VStack(alignment: .leading, spacing: 12) {
                discoveryRow(
                    symbol: "globe",
                    title: "Chrome profiles",
                    detail: model.chromeProfiles.isEmpty
                        ? "No profiles found"
                        : model.chromeProfiles.map(\.name).joined(separator: ", "),
                    found: !model.chromeProfiles.isEmpty
                )
                Divider()
                discoveryRow(
                    symbol: "chevron.left.forwardslash.chevron.right",
                    title: "Visual Studio Code",
                    detail: model.vscodeInstallation?.executableURL.path ?? "Not found",
                    found: model.vscodeInstallation != nil
                )
            }
            .padding(8)
        }
    }

    private var starters: some View {
        GroupBox("Starter contexts") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit these generic templates, assign Chrome profiles, and add local project folders or .code-workspace files.")
                    .foregroundStyle(.secondary)

                ForEach($model.starterContexts) { $context in
                    DisclosureGroup {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Name")
                                TextField("Name", text: $context.name)
                            }
                            GridRow {
                                Text("Launch ID")
                                TextField("ID", text: $context.id)
                            }
                            GridRow {
                                Text("Subtitle")
                                TextField("Subtitle", text: $context.subtitle)
                            }
                            GridRow {
                                Text("Chrome profile")
                                Picker("", selection: profileBinding(for: $context)) {
                                    Text("None").tag("")
                                    ForEach(model.chromeProfiles, id: \.directoryID) { profile in
                                        Text(profile.email.map { "\(profile.name) — \($0)" } ?? profile.name)
                                            .tag(profile.directoryID)
                                    }
                                }
                                .labelsHidden()
                            }
                            GridRow(alignment: .top) {
                                Text("Projects")
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(context.vscodeProjects.indices, id: \.self) { index in
                                        HStack {
                                            Text(context.vscodeProjects[index].path)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            Button {
                                                context.vscodeProjects.move(
                                                    fromOffsets: IndexSet(integer: index),
                                                    toOffset: index - 1
                                                )
                                            } label: {
                                                Image(systemName: "chevron.up")
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(index == 0)
                                            .help("Move project up")

                                            Button {
                                                context.vscodeProjects.move(
                                                    fromOffsets: IndexSet(integer: index),
                                                    toOffset: index + 2
                                                )
                                            } label: {
                                                Image(systemName: "chevron.down")
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(index == context.vscodeProjects.count - 1)
                                            .help("Move project down")

                                            Button(role: .destructive) {
                                                context.vscodeProjects.remove(at: index)
                                            } label: {
                                                Image(systemName: "minus.circle")
                                            }
                                            .buttonStyle(.borderless)
                                            .help("Remove project")
                                        }
                                    }
                                    Button("Add Folder or Workspace…") {
                                        projectContextID = context.id
                                        importsProjects = true
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack {
                            ContextIconView(icon: context.icon)
                                .frame(width: 24, height: 24)
                            Text(context.name)
                                .fontWeight(.medium)
                            Text(context.id)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
            }
            .padding(8)
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text("Your launchers are ready")
                .font(.largeTitle.bold())
            Text("Press Command-Space, type a context name such as “Work,” then press Return. Search for “New” whenever you want to create another context.")
                .font(.title3)
                .foregroundStyle(.secondary)
            GroupBox("Next steps") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Open each context to add URLs, projects, and applications.", systemImage: "slider.horizontal.3")
                    Label("Use Test Launch before saving to check the configured items.", systemImage: "play.circle")
                    Label("Open Diagnostics if a profile, application, or launcher moves.", systemImage: "stethoscope")
                }
                .padding(8)
            }
            Button("Configure My Contexts") {
                model.dismissOnboardingCompletion()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func discoveryRow(symbol: String, title: String, detail: String, found: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(found ? .green : .orange)
        }
    }

    private func profileBinding(for context: Binding<LauncherContext>) -> Binding<String> {
        Binding(
            get: { context.wrappedValue.chromeProfileID ?? "" },
            set: { context.wrappedValue.chromeProfileID = $0.isEmpty ? nil : $0 }
        )
    }

    private func addProjects(_ urls: [URL]) {
        guard let projectContextID,
              let index = model.starterContexts.firstIndex(where: { $0.id == projectContextID }) else { return }
        for url in urls where !model.starterContexts[index].vscodeProjects.contains(url) {
            model.starterContexts[index].vscodeProjects.append(url)
        }
    }

    private static let workspaceType = UTType(filenameExtension: "code-workspace") ?? .data
}
