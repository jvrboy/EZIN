import SwiftUI

/// Import & manage local LLM model files. Parses GGUF headers to show architecture,
/// context length, and other metadata. When a model is selected, chat routes through
/// the configured self-hosted endpoint using the model's filename.
struct LLMModelsView: View {
    @ObservedObject private var store = LLMModelStore.shared
    @ObservedObject private var chatConfig = ChatConfigStore.shared
    @State private var showPicker = false
    @State private var importError: String?
    @State private var metadataInfo: String?

    var body: some View {
        GlassScreen(title: "LLM Models") {
            Button { showPicker = true } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Import model file").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Glass.accent.opacity(0.7)))
            }.buttonStyle(.plain)

            // Status message about how models are used
            if let selectedID = chatConfig.config.selectedLocalModelID,
               let model = store.models.first(where: { $0.id == selectedID }) {
                modelStatusCard(model)
            } else {
                Text("Import .gguf or .safetensors model files. Select one to use it via your self-hosted endpoint (llama.cpp, Ollama, vLLM). Files are stored in On My iPhone → EZIN → Models.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
            }

            if let err = importError {
                Text(err).font(.caption).foregroundStyle(Glass.sell)
                    .padding(.vertical, 4)
            }

            if store.models.isEmpty {
                EmptyState(icon: "shippingbox",
                           title: "No models imported",
                           subtitle: "Import a .gguf or .safetensors model to run inference locally via your self-hosted endpoint.")
            } else {
                GlassSection(title: "Imported (\(store.models.count))") {
                    ForEach(Array(store.models.enumerated()), id: \.element.id) { idx, m in
                        modelRow(m, index: idx, total: store.models.count)
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { urls in
                for url in urls {
                    do {
                        let model = try FileStore.shared.importModel(from: url)
                        store.add(model)
                    } catch {
                        importError = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Model Status Card

    @ViewBuilder
    private func modelStatusCard(_ model: LLMModel) -> some View {
        let hasEndpoint = CredentialStore.shared.has(.customEndpoint)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: hasEndpoint ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(hasEndpoint ? .green : .orange)
                    .font(.system(size: 16))
                Text(hasEndpoint ? "Model active" : "Endpoint needed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Selected: **\(model.name)** (\(model.sizeDisplay))")
                .font(.caption).foregroundStyle(.white.opacity(0.8))

            if hasEndpoint {
                Text("Chat will route through your endpoint using this model file.")
                    .font(.caption2).foregroundStyle(.green.opacity(0.8))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("To use this model, set up a local server:")
                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    Text("1. Run: `./server -m \(model.name) --port 8080`")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("2. Settings → Custom Endpoint → `http://localhost:8080/v1/chat/completions`")
                        .font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    // MARK: - Model Row

    @ViewBuilder
    private func modelRow(_ m: LLMModel, index: Int, total: Int) -> some View {
        let isSelected = chatConfig.config.selectedLocalModelID == m.id
        HStack(spacing: 12) {
            // Selection radio button
            Button { chatConfig.config.selectedLocalModelID = m.id } label: {
                Image(systemName: isSelected ? "circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Glass.accent : .white.opacity(0.3))
            }.buttonStyle(.plain)

            Image(systemName: "cube.box.fill")
                .foregroundStyle(isSelected ? Glass.accent : Glass.accent2)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(m.format.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    Text(m.sizeDisplay)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Spacer()

            Button { store.remove(m) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Glass.sell.opacity(0.7))
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        if index < total - 1 { Divider().overlay(Color.white.opacity(0.08)) }
    }
}
