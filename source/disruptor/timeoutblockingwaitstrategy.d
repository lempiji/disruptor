module disruptor.timeoutblockingwaitstrategy;

import core.sync.mutex : Mutex;
import core.sync.condition : Condition;
import core.time : Duration, MonoTime, nsecs, msecs;
import disruptor.sequence;
import disruptor.sequencer : SequenceBarrier;
import disruptor.waitstrategy : WaitStrategy;
import disruptor.timeoutexception : TimeoutException;

/// Blocking strategy that waits using a condition variable but throws
/// TimeoutException if idle for the configured timeout.
class TimeoutBlockingWaitStrategy : WaitStrategy
{
    private shared Mutex _mutex;
    private shared Condition _cond;
    private long _timeoutNanos;

    this(Duration timeout) shared
    {
        _mutex = new shared Mutex();
        _cond = new shared Condition(_mutex);
        _timeoutNanos = cast(long) timeout.total!"nsecs";
    }

    override long waitFor(long sequence, shared Sequence cursor, shared Sequence dependentSequence, shared SequenceBarrier barrier) shared
    {
        long availableSequence;
        long timeoutRemaining = _timeoutNanos;

        if (cursor.get() < sequence)
        {
            _mutex.lock();
            scope(exit) _mutex.unlock();

            while (cursor.get() < sequence)
            {
                barrier.checkAlert();
                auto before = MonoTime.currTime;
                bool notified = _cond.wait(nsecs(timeoutRemaining));
                auto waited = MonoTime.currTime - before;
                timeoutRemaining -= cast(long) waited.total!"nsecs";

                if (!notified || timeoutRemaining <= 0)
                {
                    throw TimeoutException.INSTANCE;
                }
            }
        }

        while ((availableSequence = dependentSequence.get()) < sequence)
        {
            barrier.checkAlert();
        }

        return availableSequence;
    }

    override void signalAllWhenBlocking() shared
    {
        _mutex.lock();
        scope(exit) _mutex.unlock();
        _cond.notifyAll();
    }

    string toString() const shared
    {
        import std.conv : to;
        return "TimeoutBlockingWaitStrategy{" ~
            "timeoutInNanos=" ~ to!string(_timeoutNanos) ~ "}";
    }
}

unittest
{
    import core.thread : Thread;
    import core.time : msecs;

    class DummySequenceBarrier : SequenceBarrier
    {
        override long waitFor(long sequence) shared { return 0; }
        override long getCursor() shared { return 0; }
        override bool isAlerted() shared { return false; }
        override void alert() shared {}
        override void clearAlert() shared {}
        override void checkAlert() shared {}
    }

    enum theTimeout = 50; // milliseconds
    auto waitStrategy = new shared TimeoutBlockingWaitStrategy(msecs(theTimeout));
    auto cursor = new shared Sequence(5);
    auto barrier = new shared DummySequenceBarrier();

    auto t0 = MonoTime.currTime;
    bool threw = false;
    try
    {
        waitStrategy.waitFor(6, cursor, cursor, barrier);
    }
    catch (TimeoutException)
    {
        threw = true;
    }
    auto elapsed = MonoTime.currTime - t0;
    assert(threw);
    assert(elapsed.total!"msecs" >= theTimeout);
}
