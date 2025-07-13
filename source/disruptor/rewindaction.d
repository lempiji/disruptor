module disruptor.rewindaction;

/// Decision result for handling a RewindableException.
enum RewindAction
{
    /// Rewind and replay the whole batch from the beginning.
    REWIND,
    /// Propagate the exception to the configured ExceptionHandler.
    THROW
}

unittest
{
    assert(RewindAction.REWIND != RewindAction.THROW);
}
