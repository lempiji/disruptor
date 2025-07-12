module disruptor.rewindableexception;

/// Exception indicating a batch should be rewound and processed again.
class RewindableException : Exception
{
    this(Throwable cause = null, string file = __FILE__, size_t line = __LINE__)
    {
        super("REWINDING BATCH", file, line, cause);
    }
}

unittest
{
    auto ex = new RewindableException();
    assert(ex.msg == "REWINDING BATCH");
}

