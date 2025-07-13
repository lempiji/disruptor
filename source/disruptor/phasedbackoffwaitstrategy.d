module disruptor.phasedbackoffwaitstrategy;

public import core.atomic : pause;
import core.thread : Thread;
import core.time : Duration, MonoTime, nsecs, msecs;
import disruptor.sequence : Sequence;
import disruptor.sequencer : SequenceBarrier;
import disruptor.waitstrategy : WaitStrategy;
import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
import disruptor.sleepingwaitstrategy : SleepingWaitStrategy;
import disruptor.liteblockingwaitstrategy : LiteBlockingWaitStrategy;

/// Wait strategy that spins, then yields, then falls back to another strategy.
class PhasedBackoffWaitStrategy : WaitStrategy
{
    enum int SPIN_TRIES = 10000;

    private long _spinTimeoutNanos;
    private long _yieldTimeoutNanos;
    private shared WaitStrategy _fallbackStrategy;

    this(Duration spinTimeout, Duration yieldTimeout, shared WaitStrategy fallbackStrategy) shared
    {
        _spinTimeoutNanos = cast(long) spinTimeout.total!"nsecs";
        _yieldTimeoutNanos = _spinTimeoutNanos + cast(long) yieldTimeout.total!"nsecs";
        _fallbackStrategy = fallbackStrategy;
    }

    static shared(PhasedBackoffWaitStrategy) withLock(Duration spinTimeout, Duration yieldTimeout)
    {
        return new shared PhasedBackoffWaitStrategy(spinTimeout, yieldTimeout, new shared BlockingWaitStrategy());
    }

    static shared(PhasedBackoffWaitStrategy) withLiteLock(Duration spinTimeout, Duration yieldTimeout)
    {
        return new shared PhasedBackoffWaitStrategy(spinTimeout, yieldTimeout, new shared LiteBlockingWaitStrategy());
    }

    static shared(PhasedBackoffWaitStrategy) withSleep(Duration spinTimeout, Duration yieldTimeout)
    {
        return new shared PhasedBackoffWaitStrategy(spinTimeout, yieldTimeout, new shared SleepingWaitStrategy(0));
    }

    override long waitFor(long sequence, shared Sequence cursor, shared Sequence dependentSequence, shared SequenceBarrier barrier) shared
    {
        long availableSequence;
        MonoTime startTime;
        bool started = false;
        int counter = SPIN_TRIES;

        do
        {
            if ((availableSequence = dependentSequence.get()) >= sequence)
            {
                return availableSequence;
            }

            if (0 == --counter)
            {
                if (!started)
                {
                    startTime = MonoTime.currTime;
                    started = true;
                }
                else
                {
                    auto timeDelta = MonoTime.currTime - startTime;
                    auto deltaNanos = cast(long) timeDelta.total!"nsecs";
                    if (deltaNanos > _yieldTimeoutNanos)
                    {
                        return _fallbackStrategy.waitFor(sequence, cursor, dependentSequence, barrier);
                    }
                    else if (deltaNanos > _spinTimeoutNanos)
                    {
                        Thread.yield();
                    }
                }
                counter = SPIN_TRIES;
            }
            pause();
        }
        while (true);
    }

    override void signalAllWhenBlocking() shared
    {
        _fallbackStrategy.signalAllWhenBlocking();
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

    auto strategy1 = PhasedBackoffWaitStrategy.withLock(msecs(1), msecs(1));
    auto cursor = new shared Sequence(0);
    auto dependent = new shared Sequence();
    auto barrier = new shared DummySequenceBarrier();

    auto t = new Thread({
        Thread.sleep(50.msecs);
        dependent.incrementAndGet();
        strategy1.signalAllWhenBlocking();
    });
    t.start();

    auto result = strategy1.waitFor(0, cursor, dependent, barrier);
    assert(result == 0);
    t.join();

    auto strategy2 = PhasedBackoffWaitStrategy.withSleep(msecs(1), msecs(1));
    dependent.set(-1);

    auto t2 = new Thread({
        Thread.sleep(50.msecs);
        dependent.incrementAndGet();
        strategy2.signalAllWhenBlocking();
    });
    t2.start();

    result = strategy2.waitFor(0, cursor, dependent, barrier);
    assert(result == 0);
    t2.join();
}

