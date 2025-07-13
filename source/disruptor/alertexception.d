module disruptor.alertexception;

/// Exception thrown when a SequenceBarrier is alerted.
class AlertException : Exception
{
    static __gshared AlertException INSTANCE;

    this(string msg = "Alerted", string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

shared static this()
{
    AlertException.INSTANCE = new AlertException();
}
