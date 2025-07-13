module disruptor.eventuallygiveupbatchrewindstrategy;

import disruptor.batchrewindstrategy : BatchRewindStrategy;
import disruptor.rewindableexception : RewindableException;
import disruptor.rewindaction : RewindAction;

/// Strategy that rewinds for a limited number of attempts before delegating the exception.
class EventuallyGiveUpBatchRewindStrategy : BatchRewindStrategy
{
    private long _maxAttempts;

    this(long maxAttempts) shared
    {
        _maxAttempts = maxAttempts;
    }

    override RewindAction handleRewindException(RewindableException e, int attempts) shared
    {
        if (attempts == _maxAttempts)
        {
            return RewindAction.THROW;
        }
        return RewindAction.REWIND;
    }
}

