module disruptor.simplebatchrewindstrategy;

import disruptor.batchrewindstrategy : BatchRewindStrategy;
import disruptor.rewindaction : RewindAction;
import disruptor.rewindableexception : RewindableException;

/// Batch rewind strategy that always rewinds.
class SimpleBatchRewindStrategy : BatchRewindStrategy
{
    override RewindAction handleRewindException(RewindableException e, int attempts) shared
    {
        return RewindAction.REWIND;
    }
}

