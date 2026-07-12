import SwiftUI

/// Import & manage local LLM model files (.gguf, .safetensors, any) — no size limit.
struct LLMModelsView: View {
    @ObservedObject private var store = LLMModelStore.shared
    @State private var showPicker = false
    @State private var importError: String?

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

            Text("Supports .gguf, .safetensors, .bin and any other format. Files are copied into On My iPhone → EZIN → Models with no size limit.")
                .font(.caption2).foregroundStyle(.white.opacity(0.4))

            if let err = importError {
                Text(err).font(.caption).foregroundStyle(Glass.sell)
            }

            if store.models.isEmpty {
                EmptyState(icon: "shippingbox",
                           title: "No models imported",
                           subtitle: "Import a .gguf or .safetensors model to run inference locally.")
            } else {
                GlassSection(title: "Imported (\(store.models.count))") {
                    ForEach(Array(store.models.enumerated()), id: \.element.id) { idx, m in
                        HStack(spacing: 12) {
                            Image(systemName: "cube.box.fill").foregroundStyle(Glass.accent2).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.88)).lineLimit(1)
                                Text("\(m.format.uppercased()) · \(m.sizeDisplay)").font(.caption2).foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer()
                            Button { store.remove(m) } label: {
                                Image(systemName: "trash").foregroundStyle(Glass.sell)
                            }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 10)
                        if idx < store.models.count - 1 { Divider().overlay(Color.white.opacity(0.08)) }
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
}
