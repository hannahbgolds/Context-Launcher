import ContextLauncherKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

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
                        Button("Create Contexts and Launchers") {
                            model.completeOnboarding()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(36)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Welcome")
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
                Text("Edit these generic templates now. You can add URLs, projects, and applications after setup.")
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
}
