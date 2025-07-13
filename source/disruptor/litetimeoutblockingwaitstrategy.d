module disruptor.litetimeoutblockingwaitstrategy;

public import core.atomic : MemoryOrder, atomicLoad, atomicStore;
import core.sync.mutex : Mutex;
import core.sync.condition : Condition;
import core.time : Duration, MonoTime, nsecs, msecs;
import disruptor.sequence : Sequence;
import disruptor.sequencer : SequenceBarrier;
import disruptor.waitstrategy : WaitStrategy;
import disruptor.timeoutexception : TimeoutException;
import disruptor.util : awaitNanos;

/// Blocking strategy with timeout that avoids unnecessary wakeups when uncontended.
class LiteTimeoutBlockingWaitStrategy : WaitStrategy
{
    private shared Mutex _mutex;
    private shared Condition _cond;
    private shared bool _signalNeeded = false;
    private long _timeoutNanos;

    this(Duration timeout) shared
    {
        _mutex = new shared Mutex();
        _cond = new shared Condition(_mutex);
        _timeoutNanos = cast(long) timeout.total!"nsecs";
    }

    override long waitFor(long sequence, shared Sequence cursorSequence,
            shared Sequence dependentSequence, shared SequenceBarrier barrier) shared
    {
        long nanos = _timeoutNanos;
        long availableSequence;
        if (cursorSequence.get() < sequence)
        {
            _mutex.lock();
            scope(exit) _mutex.unlock();
            while (cursorSequence.get() < sequence)
            {
                atomicStore!(MemoryOrder.rel)(_signalNeeded, true);

                barrier.checkAlert();
                nanos = awaitNanos(_cond, nanos);
                if (nanos <= 0)
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
        if (atomicLoad!(MemoryOrder.acq)(_signalNeeded))
        {
            atomicStore!(MemoryOrder.rel)(_signalNeeded, false);
            _mutex.lock();
            scope(exit) _mutex.unlock();
            _cond.notifyAll();
        }
    }

    string toString() const shared
    {
        import std.conv : to;
        return "LiteTimeoutBlockingWaitStrategy{" ~
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

    enum theTimeout = 50;
    auto waitStrategy = new shared LiteTimeoutBlockingWaitStrategy(msecs(theTimeout));
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

