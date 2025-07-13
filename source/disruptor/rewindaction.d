module disruptor.rewindaction;

/// Decision returned by a BatchRewindStrategy on how to handle a RewindableException.
enum RewindAction
{
    /// Rewind and replay the whole batch.
    REWIND,
    /// Propagate the exception to the configured ExceptionHandler.
    THROW
}

