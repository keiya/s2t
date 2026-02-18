import SwiftUI

struct ContentView: View {
    @Bindable var orchestrator: PipelineOrchestrator

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                StatusIndicator(state: orchestrator.state, audioLevel: orchestrator.audioLevel)
                Spacer()
                if orchestrator.showCopiedFeedback {
                    Text("Copied!")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Main transcript/correction display
                    TranscriptView(
                        state: orchestrator.state,
                        transcription: orchestrator.lastTranscription,
                        correction: orchestrator.lastCorrection
                    )

                    // Correction panel (visible when we have results)
                    if orchestrator.lastTranscription != nil {
                        Divider()

                        CorrectionPanelView(
                            transcription: orchestrator.lastTranscription,
                            correction: orchestrator.lastCorrection,
                            onCopyRawTranscript: { orchestrator.copyRawTranscript() },
                            onReplayTTS: { orchestrator.replayTTS() }
                        )
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 480)
        .frame(minHeight: 300)
        .animation(.default, value: orchestrator.showCopiedFeedback)
    }
}
