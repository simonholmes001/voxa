namespace Voxa.Domain.Learners;

public readonly record struct TenantId
{
    private TenantId(string value) => Value = value;

    public string Value { get; }

    public static TenantId Create(string value)
    {
        return string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException("Tenant id is required.", nameof(value))
            : new TenantId(value.Trim());
    }
}

public readonly record struct UserId
{
    private UserId(string value) => Value = value;

    public string Value { get; }

    public static UserId Create(string value)
    {
        return string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException("User id is required.", nameof(value))
            : new UserId(value.Trim());
    }
}

public readonly record struct CorrelationId
{
    private CorrelationId(string value) => Value = value;

    public string Value { get; }

    public static CorrelationId Create(string? value)
    {
        return string.IsNullOrWhiteSpace(value)
            ? new CorrelationId(Guid.NewGuid().ToString("n"))
            : new CorrelationId(value.Trim());
    }
}

public readonly record struct LearnerStateVersion
{
    private LearnerStateVersion(long value) => Value = value;

    public long Value { get; }

    public static LearnerStateVersion Create(long value)
    {
        return value < 0
            ? throw new ArgumentOutOfRangeException(nameof(value), "Learner state version cannot be negative.")
            : new LearnerStateVersion(value);
    }

    public LearnerStateVersion Next() => Create(Value + 1);
}
