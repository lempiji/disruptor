module disruptor.simplebatchrewindstrategy;

import disruptor.batchrewindstrategy : BatchRewindStrategy;
import disruptor.rewindableexception : RewindableException;
import disruptor.rewindaction : RewindAction;

/// Batch rewind strategy that always rewinds.
class SimpleBatchRewindStrategy : BatchRewindStrategy
{
    override RewindAction handleRewindException(RewindableException e, int attempts) shared
    {
        return RewindAction.REWIND;
    }
}

