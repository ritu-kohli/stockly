import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = Keychain.claudeKey ?? ""
    @State private var isRevealed = false
    @State private var saved = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Text("Claude AI Analysis")
                                .font(.headline)
                        }
                        Text("Add your Anthropic API key to enable AI-powered news sentiment analysis. Without it, on-device NLP is used as a fallback.")
                            .font(.caption)
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
