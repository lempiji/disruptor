module disruptor.timeoutexception;

/// Exception thrown when a wait strategy times out waiting for a sequence.
class TimeoutException : Exception
{
    static __gshared TimeoutException INSTANCE;

    this(string msg = "Timeout", string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

shared static this()
{
    TimeoutException.INSTANCE = new TimeoutException();
}
