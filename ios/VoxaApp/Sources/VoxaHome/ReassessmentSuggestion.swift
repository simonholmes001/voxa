import Foundation
import VoxaRealtime

/// Decides whether Home should show a "should I adjust your plan?"
/// banner based on the current course and the planner's most recent
/// recommendation. The learner ALWAYS confirms — this type never
/// mutates anything; it only produces the banner's title + rationale
/// text so a tap can open the Reassess sheet with a pre-filled hint.
///
/// Kept as a pure enum so the trigger heuristic is unit-testable
/// without a rendered view or a device.
public enum ReassessmentSuggestion: Sendable, Equatable {
    /// No suggestion — Home renders the plain course card. Either
    /// the course is fresh or the planner is on-track with the arc.
    case none
    /// Suggest a reassessment. Rendered as a soft-tinted banner
    /// above the course card. Tapping the banner opens the Reassess
    /// sheet with `hintText` pre-filled as an editable suggestion.
    case suggested(title: String, rationale: String, hintText: String)

    /// The rule the app uses today (Phase C3).
    ///
    /// Trigger: the learner has completed at least a minimum number
    /// of lessons AND the planner's most recent recommendation is a
    /// remediation activity (`mistakes_replay` or
    /// `pronunciation_drill`). Both together say "the arc isn't
    /// pointing at what the learner actually needs to work on right
    /// now" — the right moment to offer a reshape.
    ///
    /// Explicitly never triggered when the course is empty, when the
    /// planner is idle/failed, or when the planner recommends a
    /// forward-motion activity (`guided_lesson`, `open_practice`,
    /// `roleplay`, etc.).
    public static func evaluate(
        course: LearnerCourseState,
        plan: LearnerPlanState,
        minimumCompletedLessons: Int = 3
    ) -> ReassessmentSuggestion {
        guard case let .ready(courseValue) = course else { return .none }
        guard case let .ready(planValue) = plan else { return .none }

        let completedCount = courseValue.lessons.filter { $0.status == .completed }.count
        guard completedCount >= minimumCompletedLessons else { return .none }

        let intent = planValue.recommendedSession.activityIntent
        switch intent {
        case "mistakes_replay":
            let focus = planValue.recommendedSession.focusTitle
            let rationale = focus.isEmpty
                ? "You've been catching recurring mistakes lately. A quick reshape can put those front-and-centre in your plan."
                : "\(focus) has come up more than once. Reshape your plan so the tutor tackles it head-on."
            let hint = focus.isEmpty
                ? "focus more on my recurring mistakes"
                : "focus more on \(focus.lowercased())"
            return .suggested(
                title: "Should I adjust your plan?",
                rationale: rationale,
                hintText: hint)

        case "pronunciation_drill":
            let focus = planValue.recommendedSession.focusTitle
            let rationale = focus.isEmpty
                ? "Your pronunciation keeps needing extra work. A reshape can slot more drills into the arc."
                : "\(focus) is a persistent pronunciation target. A reshape can weave more of it through your plan."
            let hint = focus.isEmpty
                ? "add more pronunciation practice"
                : "more pronunciation work on \(focus.lowercased())"
            return .suggested(
                title: "Should I adjust your plan?",
                rationale: rationale,
                hintText: hint)

        default:
            return .none
        }
    }
}
