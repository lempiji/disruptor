module disruptor.nanosecondpausebatchrewindstrategy;

import core.thread : Thread;
import core.time : nsecs;
import disruptor.batchrewindstrategy : BatchRewindStrategy;
import disruptor.rewindableexception : RewindableException;
import disruptor.rewindaction : RewindAction;

/// Strategy that pauses for a specified number of nanoseconds before rewinding.
class NanosecondPauseBatchRewindStrategy : BatchRewindStrategy
{
    private long _nanoSecondPauseTime;

    this(long nanoSecondPauseTime) shared
    {
        _nanoSecondPauseTime = nanoSecondPauseTime;
    }

    override RewindAction handleRewindException(RewindableException e, int attempts) shared
    {
        Thread.sleep(nsecs(_nanoSecondPauseTime));
        return RewindAction.REWIND;
    }
}

