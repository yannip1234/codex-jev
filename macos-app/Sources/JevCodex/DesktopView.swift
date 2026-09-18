import SwiftUI

private typealias DesktopState<Value> = SwiftUI.State<Value>

struct ContentView: View {
    @ObservedObject var model: ChatModel
    @DesktopState private var followOutput = true
    private var locked: Bool { model.busy || model.running || model.contextStatus.isCompacting }

    var body: some View {
        HSplitView {
            DesktopSidebar(model: model).frame(minWidth: 230, idealWidth: 260, maxWidth: 310)
            VStack(spacing: 0) {
                header
                Divider().opacity(0.45)
                if let error = model.error {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        Text(error).font(.system(size: 12)).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button { model.error = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss error")
                    }.padding(12).frame(maxWidth: 950)
                        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 28).padding(.top, 12)
                }
                ConversationView(model: model, followOutput: followOutput)
                ChatComposer(model: model)
            }.frame(minWidth: 620).background(.white)
        }
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.light)
        .sheet(item: Binding(get: { model.userQuestions.first }, set: { _ in })) { request in
            QuestionSheet(model: model, request: request)
        }
        .sheet(item: Binding(get: { model.approvals.first }, set: { _ in })) { approval in
            VStack(alignment: .leading, spacing: 16) {
                Text(approval.title).font(.title2.bold())
                Text("Review this action before allowing it to run.").foregroundStyle(.secondary)
                ScrollView {
                    Text(approval.detail).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 160, maxHeight: 420)
                HStack {
                    Spacer()
                    Button("Decline") { model.decide(approval, accept: false) }.keyboardShortcut(.cancelAction)
                    Button("Allow Once") { model.decide(approval, accept: true) }.buttonStyle(.borderedProminent)
                }
            }.padding(24).frame(width: 640).interactiveDismissDisabled()
        }
    }

    private var header: some View {
        HStack(spacing: 15) {
            Text(model.taskTitle).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Spacer(minLength: 10)
            if model.busy || model.running { ProgressView().controlSize(.mini) }
            Text(model.running ? model.activity.currentStep : model.connected ? "Ready" : "Disconnected")
                .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).frame(maxWidth: 220).help(model.status)
            if let selectedID = model.selectedID {
                Button { model.togglePin(selectedID) } label: {
                    Image(systemName: model.pinnedIDs.contains(selectedID) ? "pin.fill" : "pin")
                }.buttonStyle(.plain).foregroundStyle(.secondary).help("Pin or unpin this task")
            }
            Button { model.copyTranscript() } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.items.isEmpty).help("Copy transcript")
            Menu {
                Button("Compact context", systemImage: "arrow.down.right.and.arrow.up.left") { Task { await model.compact() } }
                    .disabled(model.selectedID == nil || locked || !model.connected)
                Button("Reconnect", systemImage: "arrow.clockwise") { Task { await model.reconnect() } }.disabled(locked)
                Toggle("Follow output", isOn: $followOutput)
                Divider()
                Button("Show project in Finder", systemImage: "folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: model.cwd)
                }
                SettingsLink { Text("Settings…") }
            } label: { Image(systemName: "ellipsis").font(.system(size: 17)) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).foregroundStyle(.secondary)
                .accessibilityLabel("Conversation actions")
        }
        .padding(.horizontal, 22).frame(height: 52)
    }
}
