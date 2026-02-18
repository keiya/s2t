import SwiftUI

struct StatusIndicator: View {
    let state: PipelineState
    var audioLevel: Float = 0

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if case .recording = state {
                LevelMeter(level: CGFloat(audioLevel))
                    .frame(width: 60, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        switch state {
        case .idle: .gray
        case .recording: .red
        case .processing: .orange
        case .done: .green
        case .error: .red
        }
    }

    private var statusText: String {
        switch state {
        case .idle:
            "Ready — Press hotkey to record"
        case .recording:
            "Recording..."
        case .processing(let step):
            switch step {
            case .transcribing: "Transcribing..."
            case .correcting: "Correcting..."
            case .speaking: "Speaking..."
            }
        case .done:
            "Done — Copied to clipboard"
        case .error(let error):
            error.localizedDescription
        }
    }
}

struct LevelMeter: View {
    let level: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)

                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: max(0, geo.size.width * level))
            }
        }
    }

    private var barColor: Color {
        if level > 0.8 { .red }
        else if level > 0.5 { .orange }
        else { .green }
    }
}
