module disruptor.sleepingwaitstrategy;

import core.thread : Thread;
import core.time : nsecs;
import disruptor.sequence;
import disruptor.sequencer : SequenceBarrier;
import disruptor.waitstrategy : WaitStrategy;

/// Sleeping strategy that spins, then yields, then sleeps.
class SleepingWaitStrategy : WaitStrategy
{
    enum int SPIN_THRESHOLD = 100;
    enum int DEFAULT_RETRIES = 200;
    enum long DEFAULT_SLEEP = 100; // in nanoseconds

    private int retries;
    private long sleepTimeNs;

    this()
    {
        this(DEFAULT_RETRIES, DEFAULT_SLEEP);
    }

    this(int retries)
    {
        this(retries, DEFAULT_SLEEP);
    }

    this(int retries, long sleepTimeNs)
    {
        this.retries = retries;
        this.sleepTimeNs = sleepTimeNs;
    }

    override long waitFor(long sequence, shared Sequence cursor, shared Sequence dependentSequence, SequenceBarrier barrier)
    {
        long availableSequence;
        int counter = retries;
        while ((availableSequence = dependentSequence.get()) < sequence)
        {
            counter = applyWaitMethod(barrier, counter);
        }
        return availableSequence;
    }

    override void signalAllWhenBlocking()
    {
    }

private:
    int applyWaitMethod(SequenceBarrier barrier, int counter)
    {
        barrier.checkAlert();

        if (counter > SPIN_THRESHOLD)
        {
            return counter - 1;
        }
        else if (counter > 0)
        {
            Thread.yield();
            return counter - 1;
        }
        else
        {
            Thread.sleep(nsecs(sleepTimeNs));
        }
        return counter;
    }
}

unittest
{
    import core.thread : Thread;
    import core.time : msecs;

    class DummySequenceBarrier : SequenceBarrier
    {
        override long waitFor(long sequence) { return 0; }
        override long getCursor() { return 0; }
        override bool isAlerted() { return false; }
        override void alert() {}
        override void clearAlert() {}
        override void checkAlert() {}
    }

    auto strategy = new SleepingWaitStrategy();
    auto cursor = new shared Sequence(0);
    auto dependent = new shared Sequence();
    auto barrier = new DummySequenceBarrier();

    auto t = new Thread({
        Thread.sleep(50.msecs);
        dependent.incrementAndGet();
        strategy.signalAllWhenBlocking();
    });
    t.start();

    auto result = strategy.waitFor(0, cursor, dependent, barrier);
    assert(result == 0);
    t.join();
}
