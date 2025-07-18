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

    this(long nanoSecondPauseTime) shared @safe nothrow
    {
        _nanoSecondPauseTime = nanoSecondPauseTime;
    }

    override RewindAction handleRewindException(RewindableException e, int attempts) shared @trusted nothrow
    {
        Thread.sleep(nsecs(_nanoSecondPauseTime));
        return RewindAction.REWIND;
    }
}

