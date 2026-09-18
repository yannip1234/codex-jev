import SwiftUI

private typealias ComposerState<Value> = SwiftUI.State<Value>

struct ConversationView: View {
    @ObservedObject var model: ChatModel
    let followOutput: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if model.items.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "sparkle").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                            Text("What would you like to build?").font(.system(size: 25, weight: .medium))
                            Text("Choose a project and start a conversation.").font(.system(size: 14)).foregroundStyle(.secondary)
                            Button { model.chooseFolder() } label: {
                                Label(URL(fileURLWithPath: model.cwd).lastPathComponent, systemImage: "folder")
                            }.buttonStyle(.bordered).controlSize(.small).padding(.top, 4)
                                .disabled(model.selectedID != nil || model.busy || model.running)
                        }.frame(maxWidth: .infinity).padding(.top, 110).padding(.bottom, 80)
                    }
                    ForEach(model.items) { item in
                        if item.role == "You" {
                            HStack {
                                Spacer(minLength: 70)
                                Text(item.text).font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
                                    .padding(.horizontal, 18).padding(.vertical, 13)
                                    .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                            }.padding(.vertical, 4)
                        } else if item.role == "Codex" {
                            Text(item.text).font(.system(size: 15)).lineSpacing(7).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if !model.activity.tools.contains(where: { $0.id == item.id }) {
                            activity(item)
                        }
                    }
                    ActivityView(state: model.activity, running: model.running)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.items) { _, _ in if followOutput { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: model.selectedID) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func activity(_ item: ChatItem) -> some View {
        DisclosureGroup {
            Text(item.text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.role == "Command" ? "terminal" : item.role == "File changes" ? "doc.text" : "circle.grid.2x2")
                    .font(.system(size: 13))
                Text(item.role == "Command" ? "\(item.status == "inProgress" ? "Running" : "Ran") \(item.text.components(separatedBy: .newlines).first ?? "command")" : item.text)
                    .font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                if item.status == "inProgress" { ProgressView().controlSize(.mini) }
                if item.status == "failed" || item.status == "declined" {
                    Text(item.status.capitalized).font(.caption).foregroundStyle(.red)
                }
            }.foregroundStyle(.secondary)
        }.tint(.gray)
    }
}

struct ChatComposer: View {
    @ObservedObject var model: ChatModel
    @ComposerState private var showingGoal = false
    private var locked: Bool { model.busy || model.running || model.contextStatus.isCompacting }
    private var canSend: Bool { !locked && model.connected && (!model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.attachments.isEmpty) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = model.contextStatus.message {
                HStack(alignment: .top) {
                    if model.contextStatus.isCompacting { ProgressView().controlSize(.mini) }
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let goal = model.goal { GoalBanner(model: model, goal: goal) }
            if !model.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(model.attachments) { file in
                            HStack(spacing: 5) {
                                Image(systemName: file.isDirectory ? "folder" : file.isImage ? "photo" : "doc")
                                Text(file.name).lineLimit(1)
                                Button { model.attachments.removeAll { $0.id == file.id } } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).disabled(locked).accessibilityLabel("Remove \(file.name)")
                            }.font(.caption).padding(7).background(Color.gray.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
            if model.planMode { Label("Plan mode", systemImage: "lightbulb").font(.caption).foregroundStyle(.blue) }
            PromptEditor(text: $model.draft, canSubmit: canSend) { Task { await model.send() } }
                .frame(height: 56)
                .overlay(alignment: .topLeading) {
                    if model.draft.isEmpty {
                        Text("Do anything").font(.system(size: 15)).foregroundStyle(.tertiary)
                            .padding(.top, 1).padding(.leading, 5).allowsHitTesting(false)
                    }
                }
            HStack(spacing: 12) {
                Menu {
                    Button("Files and folders…", systemImage: "paperclip") { model.attachFiles() }.disabled(locked)
                    Button("Goal…", systemImage: "target") { showingGoal = true }.disabled(locked || !model.connected)
                    Toggle("Plan mode", isOn: $model.planMode).disabled(locked)
                    Divider()
                    Button("Choose project…", systemImage: "folder") { model.chooseFolder() }
                        .disabled(model.selectedID != nil || locked)
                    Button("New chat", systemImage: "square.and.pencil") { model.newTask() }.disabled(locked)
                } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .regular)).frame(width: 22, height: 26)
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).help("Project and chat actions")
                ApprovalPicker(mode: $model.approvalMode, locked: locked)
                Spacer(minLength: 4)
                ModelPicker(selection: model.modelSelection, locked: locked || !model.connected)
                Button {
                    Task { if model.running { await model.cancel() } else { await model.send() } }
                } label: {
                    Image(systemName: model.running ? "stop.fill" : "arrow.up")
                        .font(.system(size: model.running ? 11 : 15, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 32, height: 32)
                        .background(canSend || model.running ? Color.black : Color.black.opacity(0.2), in: Circle())
                }.buttonStyle(.plain)
                    .disabled(!model.running && !canSend)
                    .help(model.running ? "Stop" : "Send · Return (Shift-Return for a new line)")
                    .accessibilityLabel(model.running ? "Stop" : "Send")
            }
        }
        .padding(.horizontal, 17).padding(.top, 16).padding(.bottom, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 3)
        .frame(maxWidth: 950).padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingGoal) { GoalEditor(model: model) }
    }
}
