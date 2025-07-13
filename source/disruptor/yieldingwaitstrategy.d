module disruptor.yieldingwaitstrategy;

import core.thread : Thread;
import disruptor.sequence;
import disruptor.sequencer : SequenceBarrier;
import disruptor.waitstrategy : WaitStrategy;

/// Yielding strategy that initially spins then yields the CPU.
class YieldingWaitStrategy : WaitStrategy
{
    enum int SPIN_TRIES = 100;

    override long waitFor(long sequence, shared Sequence cursor, shared Sequence dependentSequence, shared SequenceBarrier barrier) shared
    {
        long availableSequence;
        int counter = SPIN_TRIES;
        while ((availableSequence = dependentSequence.get()) < sequence)
        {
            counter = applyWaitMethod(barrier, counter);
        }
        return availableSequence;
    }

    override void signalAllWhenBlocking() shared
    {
    }

private:
    int applyWaitMethod(shared SequenceBarrier barrier, int counter) shared
    {
        barrier.checkAlert();

        if (counter == 0)
        {
            Thread.yield();
        }
        else
        {
            return counter - 1;
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
        override long waitFor(long sequence) shared @safe nothrow { return 0; }
        override long getCursor() shared @safe nothrow { return 0; }
        override bool isAlerted() shared @safe nothrow { return false; }
        override void alert() shared @safe nothrow {}
        override void clearAlert() shared @safe nothrow {}
        override void checkAlert() shared @safe nothrow {}
    }

    auto strategy = new shared YieldingWaitStrategy();
    auto cursor = new shared Sequence(0);
    auto dependent = new shared Sequence();
    auto barrier = new shared DummySequenceBarrier();

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
