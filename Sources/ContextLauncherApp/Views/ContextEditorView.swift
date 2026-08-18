import ContextLauncherKit
import SwiftUI
import UniformTypeIdentifiers

struct ContextEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding private var context: LauncherContext
    @State private var urlRows: [URLRow]
    @State private var pastedURLs = ""
    @State private var usesCustomIcon: Bool
    @State private var importsIcon = false
    @State private var importsProjects = false
    @State private var importsApplications = false
    @State private var confirmsDelete = false

    init(context: Binding<LauncherContext>) {
        _context = context
        _urlRows = State(initialValue: context.wrappedValue.urls.map { URLRow(text: $0.absoluteString) })
        if case .custom = context.wrappedValue.icon {
            _usesCustomIcon = State(initialValue: true)
        } else {
            _usesCustomIcon = State(initialValue: false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                generalSection
                chromeSection
                urlsSection
                projectsSection
                applicationsSection
            }
            .formStyle(.grouped)

            Divider()
            actionBar
                .padding(16)
        }
        .navigationTitle(context.name)
        .fileImporter(isPresented: $importsIcon, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result, let path = model.importIcon(from: url) {
                context.icon = .custom(path)
                usesCustomIcon = true
            } else if case let .failure(error) = result {
                model.presentError("Couldn’t select icon", message: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $importsProjects,
            allowedContentTypes: [.folder, Self.workspaceType],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                appendUnique(urls, to: &context.vscodeProjects)
            case let .failure(error):
                model.presentError("Couldn’t select project", message: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $importsApplications,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                appendUnique(urls, to: &context.applications)
            case let .failure(error):
                model.presentError("Couldn’t select application", message: error.localizedDescription)
            }
        }
        .alert("Delete \(context.name)?", isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive) { model.deleteDraft() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved context and its generated Spotlight launcher.")
        }
    }

    private var generalSection: some View {
        Section("General") {
            TextField("Name", text: $context.name)
            TextField("Launch ID", text: $context.id)
                .textContentType(.username)
            TextField("Subtitle", text: $context.subtitle)

            Picker("Icon", selection: $usesCustomIcon) {
                Text("SF Symbol").tag(false)
                Text("Custom Image").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: usesCustomIcon) { custom in
                if !custom, case .custom = context.icon {
                    context.icon = .symbol("folder")
                }
            }

            if usesCustomIcon {
                HStack {
                    ContextIconView(icon: context.icon)
                        .frame(width: 32, height: 32)
                    Button("Choose Image…") { importsIcon = true }
                    if case let .custom(path) = context.icon {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack {
                    ContextIconView(icon: context.icon)
                        .frame(width: 28, height: 28)
                    TextField("SF Symbol", text: symbolName)
                }
            }
        }
    }

    private var chromeSection: some View {
        Section("Chrome") {
            Toggle("Open a Chrome profile", isOn: chromeEnabled)
            if context.chromeProfileID != nil {
                Picker("Profile", selection: chromeProfileID) {
                    Text("Choose a profile").tag("")
                    ForEach(model.chromeProfiles, id: \.directoryID) { profile in
                        Text(profile.email.map { "\(profile.name) — \($0)" } ?? profile.name)
                            .tag(profile.directoryID)
                    }
                }
                if model.chromeProfiles.isEmpty {
                    Text("No Chrome profiles were discovered. Diagnostics can help locate Chrome metadata.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var urlsSection: some View {
        Section("URLs") {
            ForEach(urlRows.indices, id: \.self) { index in
                HStack {
                    TextField("https://example.com", text: $urlRows[index].text)
                    reorderButtons(index: index, count: urlRows.count) { from, to in
                        urlRows.move(fromOffsets: IndexSet(integer: from), toOffset: to)
                    }
                    Button(role: .destructive) { urlRows.remove(at: index) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove URL")
                }
            }

            Button {
                urlRows.append(URLRow(text: ""))
            } label: {
                Label("Add URL", systemImage: "plus")
            }

            DisclosureGroup("Paste multiple URLs") {
                TextEditor(text: $pastedURLs)
                    .font(.body.monospaced())
                    .frame(minHeight: 70)
                Button("Add Pasted URLs") {
                    let lines = pastedURLs
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    urlRows.append(contentsOf: lines.map(URLRow.init(text:)))
                    pastedURLs = ""
                }
                .disabled(pastedURLs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var projectsSection: some View {
        Section("VS Code Projects") {
            ForEach(context.vscodeProjects.indices, id: \.self) { index in
                HStack {
                    Image(systemName: "folder")
                    Text(context.vscodeProjects[index].path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    reorderButtons(index: index, count: context.vscodeProjects.count) { from, to in
                        context.vscodeProjects.move(fromOffsets: IndexSet(integer: from), toOffset: to)
                    }
                    Button(role: .destructive) { context.vscodeProjects.remove(at: index) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove project")
                }
            }
            Button { importsProjects = true } label: {
                Label("Add Folder or Workspace…", systemImage: "folder.badge.plus")
            }
        }
    }

    private var applicationsSection: some View {
        Section("Applications") {
            ForEach(context.applications.indices, id: \.self) { index in
                HStack {
                    Image(systemName: "app")
                    Text(context.applications[index].lastPathComponent)
                    Spacer()
                    Button(role: .destructive) { context.applications.remove(at: index) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove application")
                }
            }
            Button { importsApplications = true } label: {
                Label("Add Application…", systemImage: "plus.app")
            }
        }
    }

    private var actionBar: some View {
        HStack {
            if model.canDeleteDraft {
                Button("Delete", role: .destructive) { confirmsDelete = true }
            }
            Spacer()
            Button("Cancel") { model.cancelEditing() }
                .keyboardShortcut(.cancelAction)
            Button("Test Launch") {
                if let prepared = preparedContext() { model.testLaunch(prepared) }
            }
            Button("Save") {
                if let prepared = preparedContext() { model.save(prepared) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var symbolName: Binding<String> {
        Binding(
            get: {
                if case let .symbol(name) = context.icon { return name }
                return "folder"
            },
            set: { context.icon = .symbol($0) }
        )
    }

    private var chromeEnabled: Binding<Bool> {
        Binding(
            get: { context.chromeProfileID != nil },
            set: { enabled in
                context.chromeProfileID = enabled ? (model.chromeProfiles.first?.directoryID ?? "") : nil
            }
        )
    }

    private var chromeProfileID: Binding<String> {
        Binding(
            get: { context.chromeProfileID ?? "" },
            set: { context.chromeProfileID = $0 }
        )
    }

    private func preparedContext() -> LauncherContext? {
        let values = urlRows
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let urls = values.compactMap(URL.init(string:))
        guard urls.count == values.count else {
            model.presentError("Check the URLs", message: "Each URL must be a complete HTTP or HTTPS address.")
            return nil
        }
        var prepared = context
        prepared.urls = urls
        return prepared
    }

    @ViewBuilder
    private func reorderButtons(index: Int, count: Int, move: @escaping (Int, Int) -> Void) -> some View {
        Button { move(index, index - 1) } label: {
            Image(systemName: "chevron.up")
        }
        .buttonStyle(.borderless)
        .disabled(index == 0)
        .help("Move up")

        Button { move(index, index + 2) } label: {
            Image(systemName: "chevron.down")
        }
        .buttonStyle(.borderless)
        .disabled(index == count - 1)
        .help("Move down")
    }

    private func appendUnique(_ urls: [URL], to destination: inout [URL]) {
        for url in urls where !destination.contains(url) {
            destination.append(url)
        }
    }

    private static let workspaceType = UTType(filenameExtension: "code-workspace") ?? .data
}

private struct URLRow: Identifiable {
    let id = UUID()
    var text: String
}
