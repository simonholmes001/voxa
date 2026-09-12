#if canImport(SwiftUI)
import SwiftUI
import VoxaRealtime

/// Presented from Home's "Reassess my course" button. Collects a free-
/// text reassessment request from the learner ("I want to focus more
/// on speaking", "this is too easy", "add travel content") and hands it
/// to the LearnerCourseViewModel. The sheet stays up during the call
/// and closes once the reassessment resolves — the app stays
/// responsive because reassessment runs in a background task.
struct ReassessCourseSheet: View {
    @Bindable private var model: LearnerCourseViewModel
    private let initialText: String
    private let onDismiss: () -> Void
    @State private var text: String = ""
    @State private var isSubmitting: Bool = false

    init(
        model: LearnerCourseViewModel,
        initialText: String = "",
        onDismiss: @escaping () -> Void
    ) {
        self.model = model
        self.initialText = initialText
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "What would you like to change?",
                        text: $text,
                        axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("reassess-input")
                        .onAppear {
                            // Populate ONCE from the banner hint. If the
                            // learner has already typed something, don't
                            // clobber it.
                            if text.isEmpty { text = initialText }
                        }
                } header: {
                    Text("Your feedback")
                } footer: {
                    Text("For example: “more speaking practice”, “this is too easy”, or “add travel vocabulary”. Leave blank to let voxa reshape based on your recent sessions.")
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Reassessing your course…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Reassess my course")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("reassess-submit")
                }
            }
            .navigationTitle("Reassess course")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await model.reassess(request: trimmed.isEmpty ? nil : trimmed)
        isSubmitting = false
        onDismiss()
    }
}
#endif
