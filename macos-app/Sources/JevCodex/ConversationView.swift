import SwiftUI

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
                        } else {
                            activity(item)
                        }
                    }
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
    private var locked: Bool { model.busy || model.running }
    private var canSend: Bool { !locked && model.connected && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $model.draft)
                .font(.system(size: 15)).scrollContentBackground(.hidden)
                .frame(height: 56)
                .overlay(alignment: .topLeading) {
                    if model.draft.isEmpty {
                        Text("Do anything").font(.system(size: 15)).foregroundStyle(.tertiary)
                            .padding(.top, 1).padding(.leading, 5).allowsHitTesting(false)
                    }
                }
            HStack(spacing: 12) {
                Menu {
                    Button("Choose project…", systemImage: "folder") { model.chooseFolder() }
                        .disabled(model.selectedID != nil || locked)
                    Button("New chat", systemImage: "square.and.pencil") { model.newTask() }.disabled(locked)
                } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .regular)).frame(width: 22, height: 26)
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).help("Project and chat actions")
                Label("Workspace access", systemImage: "checkmark.shield")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .help("The harness can write within this project and asks before actions that need approval.")
                Spacer(minLength: 4)
                ModelPicker(selection: model.modelSelection, locked: locked || !model.connected)
                Button {
                    Task { if model.running { await model.cancel() } else { await model.send() } }
                } label: {
                    Image(systemName: model.running ? "stop.fill" : "arrow.up")
                        .font(.system(size: model.running ? 11 : 15, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 32, height: 32)
                        .background(canSend || model.running ? Color.black : Color.black.opacity(0.2), in: Circle())
                }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.running && !canSend)
                    .help(model.running ? "Stop" : "Send · ⌘Return")
                    .accessibilityLabel(model.running ? "Stop" : "Send")
            }
        }
        .padding(.horizontal, 17).padding(.top, 16).padding(.bottom, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 3)
        .frame(maxWidth: 950).padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }
}
