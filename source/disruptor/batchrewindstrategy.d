module disruptor.batchrewindstrategy;

public import disruptor.rewindaction : RewindAction;
import disruptor.rewindableexception : RewindableException;

/// Strategy invoked when a RewindableException occurs during batch processing.
interface BatchRewindStrategy
{
    RewindAction handleRewindException(RewindableException e, int attempts) shared @safe nothrow;
}

