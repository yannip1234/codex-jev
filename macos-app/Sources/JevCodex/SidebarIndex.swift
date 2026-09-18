import Foundation

struct ProjectGroup: Identifiable, Equatable {
    let cwd: String
    var tasks: [SavedTask]
    var id: String { cwd }
    var title: String { URL(fileURLWithPath: cwd).lastPathComponent }
}

enum SidebarIndex {
    static func matching(_ tasks: [SavedTask], query: String) -> [SavedTask] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
            || $0.cwd.localizedCaseInsensitiveContains(search) }
    }

    static func projects(_ tasks: [SavedTask], query: String) -> [ProjectGroup] {
        var groups: [ProjectGroup] = []
        for task in matching(tasks, query: query) {
            if let index = groups.firstIndex(where: { $0.cwd == task.cwd }) { groups[index].tasks.append(task) }
            else { groups.append(ProjectGroup(cwd: task.cwd, tasks: [task])) }
        }
        return groups
    }
}
