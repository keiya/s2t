import SwiftUI

struct TranscriptView: View {
    let state: PipelineState
    let transcription: TranscriptionResult?
    let correction: CorrectionResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let correction {
                Text("Corrected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(correction.correctedText)
                    .font(.title3)
                    .textSelection(.enabled)

            } else if let transcription {
                Text("Transcript")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(transcription.text)
                    .font(.title3)
                    .textSelection(.enabled)

            } else {
                stateMessage
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stateMessage: some View {
        switch state {
        case .idle:
            Text("Press and hold the hotkey to start recording")
                .foregroundStyle(.secondary)
        case .recording:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Recording... Release hotkey to stop")
            }
            .foregroundStyle(.red)
        case .processing(let step):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(processingText(for: step))
            }
            .foregroundStyle(.orange)
        case .error(let error):
            Text(error.localizedDescription)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .done:
            EmptyView()
        }
    }

    private func processingText(for step: ProcessingStep) -> String {
        switch step {
        case .transcribing: "Transcribing audio..."
        case .correcting: "Checking grammar..."
        case .speaking: "Playing TTS..."
        }
    }
}
