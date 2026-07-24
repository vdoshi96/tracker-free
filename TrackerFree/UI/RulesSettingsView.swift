import SwiftUI

struct RulesSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Audited Rules")
                        .font(.title2.bold())
                    Text("Unknown parameters remain unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Import…") {
                    state.importRules()
                }

                Button("Export…") {
                    state.exportRules()
                }
            }
            .padding()

            List {
                Section("Built-in rules") {
                    ForEach(state.builtInRuleRows) { rule in
                        RuleRow(rule: rule) { enabled in
                            state.setBuiltInRule(rule.id, enabled: enabled)
                        }
                    }
                }

                Section("User rules") {
                    if state.userRuleRows.isEmpty {
                        Text("No user rules.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.userRuleRows) { rule in
                            RuleRow(rule: rule) { enabled in
                                state.setUserRule(rule.id, enabled: enabled)
                            }
                        }
                    }
                }
            }

            HStack {
                Text(state.rulesStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Reset Built-in Enablement") {
                    state.resetBuiltInRuleEnablement()
                }

                Button("Remove User Rules", role: .destructive) {
                    state.resetUserRules()
                }
                .disabled(state.userRuleRows.isEmpty)
            }
            .padding()
        }
    }
}

private struct RuleRow: View {
    let rule: RuleDisplayRow
    let onEnabledChange: (Bool) -> Void

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { rule.enabled },
                set: { enabled in
                    onEnabledChange(enabled)
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName)
                Text(rule.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .disabled(rule.isHardGuard)
    }
}
