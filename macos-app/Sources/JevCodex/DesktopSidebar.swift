import SwiftUI

private typealias SidebarState<Value> = SwiftUI.State<Value>

struct DesktopSidebar: View {
    @ObservedObject var model: ChatModel
    @SidebarState private var query = ""
    @SidebarState private var searching = false
    @SidebarState private var collapsed: Set<String> = []
    private var locked: Bool { model.busy || model.running }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Jev Codex").font(.system(size: 18, weight: .semibold))
                Spacer()
                Button { searching.toggle(); if !searching { query = "" } } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Search tasks and projects")
                    .accessibilityLabel("Search tasks and projects")
            }.padding(.horizontal, 18).padding(.top, 48).padding(.bottom, 18)
            if searching {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search tasks or projects", text: $query).textFieldStyle(.plain)
                }.padding(9).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
            Button { model.newTask() } label: {
                Label("New chat", systemImage: "square.and.pencil")
                    .font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.buttonStyle(.plain).padding(.horizontal, 8).padding(.bottom, 14).disabled(locked)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Pinned")
                    let pinned = SidebarIndex.matching(model.tasks, query: query).filter { model.pinnedIDs.contains($0.id) }
                    if pinned.isEmpty {
                        Text(query.isEmpty ? "Pin a task to keep it here" : "No matching pinned tasks")
                            .font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 10).padding(.vertical, 5)
                    }
                    ForEach(pinned) { task in taskRow(task) }
                    sectionLabel("Projects").padding(.top, 20)
                    let groups = SidebarIndex.projects(model.tasks, query: query)
                    if groups.isEmpty {
                        Text(query.isEmpty ? "Your project tasks will appear here." : "No matching tasks or projects.")
                            .font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 10).padding(.vertical, 5)
                    }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Button {
                                if !collapsed.insert(group.id).inserted { collapsed.remove(group.id) }
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "folder").font(.system(size: 14))
                                    Text(group.title).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: collapsed.contains(group.id) ? "chevron.right" : "chevron.down")
                                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                                }.font(.system(size: 14)).padding(.horizontal, 10).padding(.vertical, 9)
                            }.buttonStyle(.plain).help(group.cwd)
                            if !collapsed.contains(group.id) || !query.isEmpty {
                                ForEach(group.tasks) { task in taskRow(task).padding(.leading, 23) }
                            }
                        }.padding(.bottom, 8)
                    }
                }.padding(.horizontal, 8).padding(.bottom, 18)
            }
            Divider().opacity(0.5)
            HStack(spacing: 9) {
                Text(String(model.accountLabel.prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(Color.gray, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.accountLabel).font(.system(size: 12)).lineLimit(1)
                    Text(model.connected ? "Connected" : "Disconnected").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                SettingsLink { Image(systemName: "gearshape").font(.system(size: 15)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Settings")
            }.padding(.horizontal, 16).padding(.vertical, 14)
        }
        .background(Color(red: 0.955, green: 0.955, blue: 0.955))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
            .padding(.horizontal, 10).padding(.vertical, 5)
    }

    private func taskRow(_ task: SavedTask) -> some View {
        Button { Task { await model.select(task.id) } } label: {
            Text(task.title).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
                .background(model.selectedID == task.id ? Color.black.opacity(0.055) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(locked).help(task.title)
        .contextMenu {
            Button(model.pinnedIDs.contains(task.id) ? "Unpin task" : "Pin task", systemImage: "pin") { model.togglePin(task.id) }
        }
    }
}
