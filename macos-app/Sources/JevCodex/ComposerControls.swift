import SwiftUI

private typealias ControlState<Value> = SwiftUI.State<Value>

struct ApprovalPicker: View {
    @Binding var mode: ApprovalMode
    let locked: Bool
    @ControlState private var showing = false
    @ControlState private var confirmFull = false
    var body: some View {
        Button { showing.toggle() } label: {
            Label(mode.title, systemImage: mode == .full ? "exclamationmark.shield" : "checkmark.shield")
                .font(.system(size: 12)).foregroundStyle(mode == .full ? Color.orange : Color.secondary)
        }.buttonStyle(.plain).disabled(locked)
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("How should actions be approved?").foregroundStyle(.secondary)
                    ForEach(ApprovalMode.allCases) { choice in
                        Button {
                            showing = false
                            if choice == .full { confirmFull = true } else { mode = choice }
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: choice == mode ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(choice.title).font(.headline)
                                    Text(choice.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(20).frame(width: 410)
            }
            .confirmationDialog("Enable full access for this task?", isPresented: $confirmFull, titleVisibility: .visible) {
                Button("Enable full access", role: .destructive) { mode = .full }
            } message: { Text("Future turns can access any file and the network without approval prompts.") }
    }
}

struct GoalEditor: View {
    @ObservedObject var model: ChatModel
    @Environment(\.dismiss) private var dismiss
    @ControlState private var objective = ""
    @ControlState private var budget = ""
    private var validBudget: Bool { budget.isEmpty || (Int(budget).map { $0 > 0 } ?? false) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set a goal").font(.title2.bold())
            Text("The harness will keep working toward this goal, including continuing after a turn ends.").foregroundStyle(.secondary)
            TextField("What should it accomplish?", text: $objective, axis: .vertical).lineLimit(3...6)
            TextField("Optional token budget", text: $budget)
            if !validBudget { Text("Enter a positive whole number.").foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Start goal") {
                    Task {
                        await model.saveGoal(objective: objective, tokenBudget: Int(budget))
                        if model.error == nil { dismiss() }
                    }
                }.buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.running || !model.connected || !validBudget || objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(24).frame(width: 480)
            .onAppear { objective = model.goal?.objective ?? ""; budget = model.goal?.tokenBudget.map(String.init) ?? "" }
    }
}

struct GoalBanner: View {
    @ObservedObject var model: ChatModel
    let goal: GoalState
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "target")
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.objective).lineLimit(2)
                Text("\(goal.status.capitalized) · \(goal.tokensUsed) tokens" + (goal.tokenBudget.map { " / \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if goal.status == "active" {
                Button("Pause") { Task { await model.updateGoal(status: "paused") } }.disabled(model.busy)
            } else if goal.status != "complete" {
                Button("Resume") { Task { await model.updateGoal(status: "active") } }.disabled(model.busy || model.running)
            }
            if goal.status != "complete" {
                Button("Complete") { Task { await model.updateGoal(status: "complete") } }.disabled(model.busy || model.running)
            }
        }.font(.system(size: 12)).padding(12).background(Color.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct QuestionSheet: View {
    @ObservedObject var model: ChatModel
    let request: UserQuestionRequest
    @ControlState private var answers: [String: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Input needed").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(request.questions) { question in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(question.header).font(.headline)
                            Text(question.question)
                            ForEach(question.options ?? [], id: \.label) { option in
                                Button { answers[question.id] = option.label } label: {
                                    HStack(alignment: .top) {
                                        Image(systemName: answers[question.id] == option.label ? "largecircle.fill.circle" : "circle")
                                        VStack(alignment: .leading) { Text(option.label); Text(option.description).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }.buttonStyle(.plain)
                            }
                            if question.isSecret == true {
                                SecureField("Your answer", text: answerBinding(question.id))
                            } else {
                                TextField("Your answer", text: answerBinding(question.id), axis: .vertical).lineLimit(1...4)
                            }
                        }
                    }
                }
            }.frame(maxHeight: 420)
            HStack {
                Spacer()
                Button("Cancel") { model.answerQuestions(request, answers: [:]) }
                Button("Submit") { model.answerQuestions(request, answers: answers) }.buttonStyle(.borderedProminent)
                    .disabled(request.questions.contains { (answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
        }.padding(24).frame(width: 560).interactiveDismissDisabled()
    }
    private func answerBinding(_ id: String) -> Binding<String> {
        Binding(get: { answers[id] ?? "" }, set: { answers[id] = $0 })
    }
}
