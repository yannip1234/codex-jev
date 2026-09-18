import Foundation
import Testing
@testable import JevCodex

@Test func projectGroupsPreserveTaskOrderAndSeparateIdenticalFolderNames() {
    let tasks = [SavedTask(id: "a", title: "Fix build", cwd: "/work/client"),
                 SavedTask(id: "b", title: "Design settings", cwd: "/other/client"),
                 SavedTask(id: "c", title: "Add search", cwd: "/work/client")]
    #expect(SidebarIndex.projects(tasks, query: "") == [
        ProjectGroup(cwd: "/work/client", tasks: [tasks[0], tasks[2]]),
        ProjectGroup(cwd: "/other/client", tasks: [tasks[1]])])
    #expect(SidebarIndex.matching(tasks, query: "  FIX  ") == [tasks[0]])
    #expect(SidebarIndex.projects(tasks, query: "/WORK") == [ProjectGroup(cwd: "/work/client", tasks: [tasks[0], tasks[2]])])
    #expect(SidebarIndex.projects(tasks, query: "missing").isEmpty)
}

@Test @MainActor func pinsPersistSeparatelyWithoutChangingTasks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let index = directory.appendingPathComponent("tasks.json")
    let tasks = [SavedTask(id: "a", title: "A real task", cwd: directory.path)]
    let original = try JSONEncoder().encode(tasks)
    try original.write(to: index)
    let model = ChatModel(indexURL: index)
    model.togglePin("missing")
    #expect(model.pinnedIDs.isEmpty)
    model.togglePin("a")
    let restored = ChatModel(indexURL: index)
    #expect(restored.pinnedIDs == ["a"])
    #expect(restored.tasks == tasks)
    #expect(try Data(contentsOf: index) == original)
    restored.togglePin("a")
    #expect(ChatModel(indexURL: index).pinnedIDs.isEmpty)
}
