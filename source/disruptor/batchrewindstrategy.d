module disruptor.batchrewindstrategy;

import disruptor.rewindableexception : RewindableException;
import disruptor.rewindaction : RewindAction;

/// Strategy for handling a RewindableException when processing an event batch.
interface BatchRewindStrategy
{
    RewindAction handleRewindException(RewindableException e, int attempts) shared;
}

