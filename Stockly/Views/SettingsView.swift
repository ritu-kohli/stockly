import SwiftUI

struct SettingsView: View {
//    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: PortfolioViewModel
    @State private var apiKey: String = Keychain.claudeKey ?? ""
    @State private var isRevealed = false
    @State private var saved = false
    @State private var exportURL: URL?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importResult: String?
    @State private var showImportResult = false
    @State private var supabaseURL: String = Keychain.supabaseURL ?? ""
    @State private var supabaseKey: String = Keychain.supabaseAnonKey ?? ""
    @State private var isSupabaseKeyRevealed = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "cylinder.split.1x2")
                                .foregroundColor(.green)
                            Text("Supabase Database")
                                .font(.headline)
                        }
                        Text("Connect to Supabase to persist your portfolio in the cloud. Data survives app deletion and works across devices.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    TextField("Project URL (https://xxx.supabase.co)", text: $supabaseURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.footnote, design: .monospaced))

                    HStack {
                        Group {
                            if isSupabaseKeyRevealed {
                                TextField("Anon Key", text: $supabaseKey)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("Anon Key", text: $supabaseKey)
                            }
                        }
                        .font(.system(.footnote, design: .monospaced))
                        Button(action: { isSupabaseKeyRevealed.toggle() }) {
                            Image(systemName: isSupabaseKeyRevealed ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Cloud Storage")
                } footer: {
                    Text("Get these from your Supabase project → Settings → API. Both are stored securely in the iOS Keychain.")
                }

                Section {
                    Link(destination: URL(string: "https://supabase.com")!) {
                        Label("Create Supabase Project", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("Supabase Setup")
                } footer: {
                    Text("Run this SQL in your Supabase SQL editor:\n\nCREATE TABLE holdings (\n  id text PRIMARY KEY,\n  sym text NOT NULL,\n  name text NOT NULL,\n  shares float8 NOT NULL,\n  cost float8 NOT NULL,\n  stock_group text NOT NULL,\n  created_at timestamptz DEFAULT now()\n);\n\nALTER TABLE holdings ENABLE ROW LEVEL SECURITY;\nCREATE POLICY \"Allow all\" ON holdings FOR ALL USING (true);")
                        .font(.system(.footnote, design: .monospaced))
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Text("Claude AI Analysis")
                                .font(.headline)
                        }
                        Text("Add your Anthropic API key to enable AI-powered news sentiment analysis. Without it, on-device NLP is used as a fallback.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("AI Settings")
                }

                Section {
                    HStack {
                        Group {
                            if isRevealed {
                                TextField("sk-ant-...", text: $apiKey)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("sk-ant-...", text: $apiKey)
                            }
                        }
                        .font(.system(.body, design: .monospaced))

                        Button(action: { isRevealed.toggle() }) {
                            Image(systemName: isRevealed ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if !apiKey.isEmpty {
                        Button(role: .destructive, action: {
                            apiKey = ""
                            Keychain.claudeKey = nil
                        }) {
                            Label("Remove API Key", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Get your API key at console.anthropic.com. The key is stored securely in the iOS Keychain and never leaves your device.")
                }

                Section {
                    Link(destination: URL(string: "https://console.anthropic.com")!) {
                        Label("Get API Key", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://www.anthropic.com/pricing")!) {
                        Label("View Pricing", systemImage: "dollarsign.circle")
                    }
                } header: {
                    Text("Resources")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Keychain.claudeKey = apiKey.trimmingCharacters(in: .whitespaces)
                        Keychain.supabaseURL = supabaseURL.trimmingCharacters(in: .whitespaces)
                        Keychain.supabaseAnonKey = supabaseKey.trimmingCharacters(in: .whitespaces)
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() }
                    }
                    .fontWeight(.semibold)
                }
            }
            .overlay {
                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .clipShape(Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: saved)
        }
    }
}
