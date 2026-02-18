import SwiftUI

struct CorrectionPanelView: View {
    let transcription: TranscriptionResult?
    let correction: CorrectionResult?
    let onCopyRawTranscript: () -> Void
    let onReplayTTS: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Raw transcript section
            if let transcription {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Original")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Spacer()

                        Button("Copy", action: onCopyRawTranscript)
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }

                    Text(transcription.text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            // Issues list
            if let correction, !correction.issues.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Issues (\(correction.issues.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(Array(correction.issues.enumerated()), id: \.offset) { _, issue in
                        IssueRow(issue: issue)
                    }
                }
            }

            // Replay button
            if correction != nil {
                Divider()

                Button(action: onReplayTTS) {
                    Label("Replay", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct IssueRow: View {
    let issue: CorrectionIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                severityBadge

                Text(issue.original)
                    .strikethrough()
                    .foregroundStyle(.red)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(issue.corrected)
                    .foregroundStyle(.green)
            }
            .font(.body)

            Text(issue.reason)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let note = issue.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }

    private var severityBadge: some View {
        Text(issue.severity.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor.opacity(0.2), in: Capsule())
            .foregroundStyle(severityColor)
    }

    private var severityColor: Color {
        switch issue.severity {
        case .low: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}
