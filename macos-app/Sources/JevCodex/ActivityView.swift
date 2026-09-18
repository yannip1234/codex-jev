import SwiftUI

struct ActivityView: View {
    let state: ActivityState
    let running: Bool

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                if !state.summaryText.isEmpty {
                    Text(state.summaryText).font(.system(size: 12)).lineSpacing(4).textSelection(.enabled)
                }
                if let explanation = state.planExplanation, !explanation.isEmpty {
                    Text(explanation).font(.system(size: 12)).textSelection(.enabled)
                }
                ForEach(state.plan) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.status == "completed" ? "checkmark.circle.fill" : step.status == "inProgress" ? "circle.lefthalf.filled" : "circle")
                            .accessibilityLabel(step.status == "inProgress" ? "In progress" : step.status.capitalized)
                        Text(step.text).textSelection(.enabled)
                    }.font(.system(size: 12))
                }
                if !state.proposedPlan.isEmpty {
                    DisclosureGroup("Proposed plan") {
                        Text(state.proposedPlan).font(.system(size: 12)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }
                }
                ForEach(state.tools) { tool in
                    ActivityToolRow(tool: tool, running: running && state.isRunning)
                }
                if let error = state.error {
                    Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled)
                }
                if !state.hasContent {
                    Text("Waiting for activity…").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 5).padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                if running && state.isRunning { ProgressView().controlSize(.mini) }
                else { Image(systemName: state.status == "failed" ? "exclamationmark.circle" : "circle.dotted").font(.system(size: 12)) }
                Text(state.currentStep).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
            }
        }
        .foregroundStyle(.secondary).tint(.gray)
        .id(state.turnID)
    }
}

private struct ActivityToolRow: View {
    let tool: ActivityState.Tool
    let running: Bool

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if !tool.detail.isEmpty { Text(tool.detail).textSelection(.enabled) }
                if !tool.output.isEmpty { Text(tool.output).textSelection(.enabled) }
                if let code = tool.exitCode { Text("Exit code: \(code)").foregroundStyle(.secondary) }
            }.font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tool.icon)
                Text(tool.title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 2)
                if tool.isActive && running { ProgressView().controlSize(.mini) }
                else if tool.status == "completed" { Image(systemName: "checkmark").accessibilityLabel("Completed") }
                else { Text(tool.status.capitalized).foregroundStyle(tool.status == "failed" ? Color.red : Color.secondary) }
            }.font(.system(size: 12))
        }
    }
}
