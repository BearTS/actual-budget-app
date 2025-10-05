import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var syncId: String = ""
    @State private var password: String = ""

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 24) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Connection")
                                .font(AppTheme.Fonts.subtitle)
                                .foregroundColor(.primary)
                            
                            TextField("Base URL", text: $baseURL).textFieldStyle(GlassTextFieldStyle())
                            TextField("API Key", text: $apiKey).textFieldStyle(GlassTextFieldStyle())
                            TextField("Sync ID", text: $syncId).textFieldStyle(GlassTextFieldStyle())
                            SecureField("Budget Encryption Password", text: $password).textFieldStyle(GlassTextFieldStyle())
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Preferences")
                                .font(AppTheme.Fonts.subtitle)
                                .foregroundColor(.primary)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Theme:")
                                    .font(AppTheme.Fonts.subheadline)
                                    .foregroundStyle(.secondary)
                                Picker("Theme", selection: $appState.currentTheme) {
                                    ForEach(AppState.Theme.allCases) { theme in
                                        Text(theme.rawValue).tag(theme)
                                    }
                                }
                                .tint(AppTheme.accent)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Currency:")
                                    .font(AppTheme.Fonts.subheadline)
                                    .foregroundStyle(.secondary)
                                Picker("Currency", selection: $appState.currencyCode) {
                                    ForEach(CurrencyFormatter.supportedCurrencies, id: \.0) { code, name in
                                        Text("\(code) - \(name)").tag(code)
                                    }
                                }
                                .tint(AppTheme.accent)
                            }

                            Toggle("Enable Demo Mode", isOn: $appState.isDemoMode)
                                .tint(AppTheme.accent)

                            NavigationLink {
                                LogsView()
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .foregroundColor(AppTheme.accent)
                                    Text("View Logs")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }

                            Button(role: .destructive) {
                                appState.resetConfiguration()
                            } label: {
                                Text("Reset & Sign Out")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding(.top)
                        }
                    }

                }
                .padding()
                
                HStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "heart.fill").foregroundColor(.red)
                    Link(destination: URL(string: "https://github.com/bearts")!) {
                        Text("Made with love by Anuj Parihar")
                            .font(AppTheme.Fonts.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            baseURL = appState.baseURLString
            apiKey = appState.apiKey
            syncId = appState.syncId
            password = appState.budgetEncryptionPassword
        }
        .onDisappear {
            appState.baseURLString = baseURL
            appState.apiKey = apiKey
            appState.syncId = syncId
            appState.budgetEncryptionPassword = password
        }
    }
}