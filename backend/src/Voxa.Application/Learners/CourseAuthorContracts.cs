using Voxa.Domain.Learners;

namespace Voxa.Application.Learners;

/// <summary>
/// Mints or re-mints a learner's course arc. Called at the end of
/// onboarding (initial mint) and when the learner asks for a
/// reassessment or accumulated debrief evidence justifies one.
/// </summary>
public interface ICourseAuthorService
{
    Task<ActiveLearningPlan> AuthorCourseAsync(
        CourseAuthorRequest request,
        CancellationToken cancellationToken);
}

/// <summary>
/// Input to the course-author pass. When <see cref="ExistingCourse"/>
/// is not null it's a re-mint — the model receives the current course
/// + the list of completed lesson ids so it can preserve progress —
/// otherwise it's an initial mint from onboarding.
/// </summary>
public sealed record CourseAuthorRequest(
    TenantId TenantId,
    UserId UserId,
    CorrelationId CorrelationId,
    LearnerProfile Profile,
    ActiveLearningPlan? ExistingCourse,
    IReadOnlyList<string> CompletedLessonIds,
    IReadOnlyList<RecordedDebrief> RecentDebriefs,
    string? ReassessmentRequest);

/// <summary>
/// Non-fatal exception raised when the author pass fails — upstream
/// error, non-JSON output, or schema violation. Endpoints map this
/// to a retryable 503.
/// </summary>
public sealed class CourseAuthorException(string message) : Exception(message);
