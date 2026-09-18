import SwiftUI

private typealias PickerState<Value> = SwiftUI.State<Value>

struct ModelPicker: View {
    @ObservedObject var selection: ModelSelection
    let locked: Bool
    @PickerState private var expanded = false

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 6) {
                Text(selection.selectedModel?.displayName ?? "Default model").lineLimit(1)
                if let effort = selection.selectedEffort { Text("· \(effort.label)").foregroundStyle(.secondary) }
                Image(systemName: "chevron.down").font(.caption2)
            }.font(.callout).padding(.horizontal, 10).padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(locked || selection.models.isEmpty)
        .accessibilityLabel("Model and reasoning effort")
        .popover(isPresented: $expanded, arrowEdge: .top) {
            VStack(spacing: 20) {
                HStack(alignment: .top) {
                    Image(systemName: "bolt").font(.title3).foregroundStyle(.secondary).padding(.top, 4)
                    Spacer(minLength: 8)
                    VStack(spacing: 4) {
                        Menu {
                            ForEach(selection.selectedModel?.efforts ?? []) { effort in
                                Button(effort.label) { selection.selectEffort(effort.id) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selection.selectedEffort?.label ?? "Default effort")
                                    .foregroundStyle(Color.blue)
                                Image(systemName: "chevron.right").font(.callout).foregroundStyle(.secondary)
                            }.font(.title2)
                        }
                        .menuStyle(.button).buttonStyle(.plain)
                        .menuIndicator(.hidden).tint(.blue).fixedSize()
                        Menu {
                            ForEach(selection.models) { model in
                                Button { selection.selectModel(model.id) } label: {
                                    if model.id == selection.modelID { Label(model.displayName, systemImage: "checkmark") }
                                    else { Text(model.displayName) }
                                }
                            }
                        } label: {
                            Text(selection.selectedModel?.displayName ?? "Default model")
                                .font(.title3).foregroundStyle(.secondary)
                        }.menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("Choose model")
                    }
                    Spacer(minLength: 8)
                    Button { selection.reset() } label: {
                        Image(systemName: "arrow.counterclockwise").font(.title3).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).padding(.top, 4)
                        .help("Reset to the default model and effort").accessibilityLabel("Reset model and effort")
                }
                if let model = selection.selectedModel, !model.efforts.isEmpty {
                    EffortSteps(options: model.efforts, selected: selection.effort, onSelect: selection.selectEffort)
                }
                if let notice = selection.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(20).frame(width: 330)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
            .disabled(locked)
        }
        .onChange(of: locked) { _, locked in if locked { expanded = false } }
    }
}

private struct EffortSteps: View {
    let options: [ReasoningOption]
    let selected: String?
    let onSelect: (String) -> Void
    private var selectedIndex: Int { options.firstIndex { $0.id == selected } ?? 0 }

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 18
            let spacing = (geometry.size.width - inset * 2) / CGFloat(max(options.count - 1, 1))
            let position = options.count == 1 ? geometry.size.width / 2 : inset + CGFloat(selectedIndex) * spacing
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule().fill(Color.blue).frame(width: position + inset)
                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { Spacer(minLength: 0) }
                        Button { onSelect(option.id) } label: {
                            Circle().fill(index <= selectedIndex ? .white.opacity(0.4) : .secondary.opacity(0.4))
                                .frame(width: 6, height: 6).frame(width: 24, height: 36).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("\(option.label): \(option.description)")
                            .accessibilityLabel(option.label)
                            .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                    }
                }.padding(.horizontal, 6)
                Circle().fill(.white).overlay(Circle().strokeBorder(.black.opacity(0.06)))
                    .shadow(color: .black.opacity(0.13), radius: 2, y: 1)
                    .frame(width: 40, height: 40).offset(x: position - 20).allowsHitTesting(false)
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let index = options.count == 1 ? 0 : Int(((value.location.x - inset) / spacing).rounded())
                onSelect(options[min(max(index, 0), options.count - 1)].id)
            })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Reasoning effort")
            .accessibilityValue(options[selectedIndex].label)
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 1 : -1
                onSelect(options[min(max(selectedIndex + delta, 0), options.count - 1)].id)
            }
        }.frame(height: 36)
    }
}
