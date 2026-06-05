import SwiftUI
import StatsUsageDomain

/// General preferences: language, launch at login, resource mode.
struct GeneralSettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker("Language", selection: languageBinding) {
                Text("English").tag(AppLanguage.en)
                Text("简体中文").tag(AppLanguage.zhHans)
            }
            Toggle("Launch at login", isOn: launchAtLoginBinding)
            Picker("Resource mode", selection: resourceModeBinding) {
                Text("Responsive (3 min)").tag(ResourceMode.responsive)
                Text("Balanced (5 min)").tag(ResourceMode.balanced)
                Text("Relaxed (10 min)").tag(ResourceMode.relaxed)
                Text("Low power (15 min)").tag(ResourceMode.lowPower)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("General")
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { viewModel.config.language },
                set: { newValue in viewModel.updateConfig { $0.language = newValue } })
    }
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { viewModel.config.launchAtLoginEnabled },
                set: { newValue in viewModel.updateConfig { $0.launchAtLoginEnabled = newValue } })
    }
    private var resourceModeBinding: Binding<ResourceMode> {
        Binding(get: { viewModel.config.resourceMode },
                set: { newValue in viewModel.updateConfig { $0.resourceMode = newValue } })
    }
}

/// Menu-bar preferences: which provider drives the text, display style, appearance.
struct MenuBarSettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker("Status-bar provider", selection: statusProviderBinding) {
                Text("Auto").tag(String?.none)
                ForEach(viewModel.config.providers) { provider in
                    Text(provider.name).tag(String?.some(provider.id))
                }
            }
            Picker("Widget style", selection: widgetStyleBinding) {
                ForEach(MenuBarWidgetStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
            Picker("Appearance", selection: appearanceBinding) {
                Text("Follow wallpaper").tag(StatusBarAppearanceMode.followWallpaper)
                Text("Dark").tag(StatusBarAppearanceMode.dark)
                Text("Light").tag(StatusBarAppearanceMode.light)
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Menu Bar")
    }

    private var statusProviderBinding: Binding<String?> {
        Binding(get: { viewModel.config.statusBarProviderID },
                set: { newValue in viewModel.updateConfig { $0.statusBarProviderID = newValue } })
    }
    private var widgetStyleBinding: Binding<MenuBarWidgetStyle> {
        Binding(get: { viewModel.config.menuBarWidgetStyle },
                set: { newValue in viewModel.updateConfig { $0.menuBarWidgetStyle = newValue } })
    }
    private var appearanceBinding: Binding<StatusBarAppearanceMode> {
        Binding(get: { viewModel.config.statusBarAppearanceMode },
                set: { newValue in viewModel.updateConfig { $0.statusBarAppearanceMode = newValue } })
    }
}

/// Notch hub preferences: enable, which provider drives the collapsed readout,
/// and whether it expands on hover.
struct NotchSettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Form {
            Toggle("Show notch hub", isOn: enabledBinding)
            Picker("Collapsed provider", selection: providerBinding) {
                Text("First available").tag(String?.none)
                ForEach(viewModel.config.providers) { provider in
                    Text(provider.name).tag(String?.some(provider.id))
                }
            }
            .disabled(!viewModel.config.notchEnabled)
            Toggle("Expand on hover", isOn: expandBinding)
                .disabled(!viewModel.config.notchEnabled)
            Text("The hub floats at the top-center of the screen, hugging the notch on Macs that have one. Hover to expand into a live usage panel; click to open Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Notch")
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { viewModel.config.notchEnabled },
                set: { newValue in viewModel.updateConfig { $0.notchEnabled = newValue } })
    }
    private var providerBinding: Binding<String?> {
        Binding(get: { viewModel.config.notchProviderID },
                set: { newValue in viewModel.updateConfig { $0.notchProviderID = newValue } })
    }
    private var expandBinding: Binding<Bool> {
        Binding(get: { viewModel.config.notchExpandOnHover },
                set: { newValue in viewModel.updateConfig { $0.notchExpandOnHover = newValue } })
    }
}

/// Providers list: enable/disable and poll interval per provider.
struct ProvidersSettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        List {
            ForEach(viewModel.config.providers) { provider in
                HStack {
                    Toggle(isOn: enabledBinding(provider.id)) {
                        VStack(alignment: .leading) {
                            Text(provider.name)
                            Text(provider.type.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(provider.pollIntervalSec / 60) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Providers")
    }

    private func enabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.config.providers.first(where: { $0.id == id })?.enabled ?? false },
            set: { newValue in
                viewModel.updateConfig { config in
                    if let idx = config.providers.firstIndex(where: { $0.id == id }) {
                        config.providers[idx].enabled = newValue
                    }
                }
            }
        )
    }
}

/// About tab: version + update check.
struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("StatsUsage").font(.title2.bold())
            Text("Version \(AppVersion.current)").foregroundStyle(.secondary)
            Text("A menu-bar console for AI subscription usage.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}
