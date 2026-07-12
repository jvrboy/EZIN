import SwiftUI

/// Build and manage processing pipelines (ordered analysis stages).
struct PipelinesView: View {
    @ObservedObject private var store = PipelineStore.shared
    @State private var newName = ""

    var body: some View {
        GlassScreen(title: "Pipelines") {
            GlassSection(title: "New pipeline") {
                HStack {
                    GlassField(placeholder: "Pipeline name", text: $newName)
                    Button {
                        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        store.add(Pipeline(name: newName, stages: Pipeline.default.stages))
                        newName = ""
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundStyle(Glass.accent)
                    }.buttonStyle(.plain)
                }
            }

            ForEach(store.pipelines) { pipeline in
                PipelineCard(pipeline: pipeline)
            }
        }
    }
}

struct PipelineCard: View {
    @ObservedObject private var store = PipelineStore.shared
    @State var pipeline: Pipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(pipeline.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                Spacer()
                Toggle("", isOn: $pipeline.enabled).labelsHidden().tint(Glass.accent)
                    .onChange(of: pipeline.enabled) { _ in store.update(pipeline) }
                Button { store.remove(pipeline) } label: {
                    Image(systemName: "trash").foregroundStyle(Glass.sell)
                }.buttonStyle(.plain)
            }

            ForEach(Array(pipeline.stages.enumerated()), id: \.element.id) { idx, stage in
                HStack(spacing: 10) {
                    Text("\(idx + 1)").font(.system(size: 11, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.1))).foregroundStyle(.white.opacity(0.7))
                    Text(stage.kind.rawValue).font(.system(size: 13)).foregroundStyle(.white.opacity(stage.enabled ? 0.85 : 0.35))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { pipeline.stages[idx].enabled },
                        set: { pipeline.stages[idx].enabled = $0; store.update(pipeline) }
                    )).labelsHidden().tint(Glass.accent2).scaleEffect(0.8)
                }
                if idx < pipeline.stages.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 8).padding(.leading, 9)
                }
            }

            Menu {
                ForEach(PipelineStage.Kind.allCases, id: \.self) { kind in
                    Button(kind.rawValue) {
                        pipeline.stages.append(PipelineStage(kind: kind))
                        store.update(pipeline)
                    }
                }
            } label: {
                HStack { Image(systemName: "plus"); Text("Add stage").font(.caption) }
                    .foregroundStyle(Glass.accent2)
            }
        }
        .padding(14).glassCard()
    }
}
