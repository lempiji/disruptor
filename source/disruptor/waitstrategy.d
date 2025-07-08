module disruptor.waitstrategy;

import core.atomic : pause; // for spin loop
import disruptor.sequence;
import disruptor.sequencer : SequenceBarrier;

/// Strategy used by EventProcessors to wait for a given sequence.
interface WaitStrategy
{
    /// Wait for the given sequence to be available.
    long waitFor(long sequence, shared Sequence cursor, shared Sequence dependentSequence, SequenceBarrier barrier);

    /// Signal waiting processors that the cursor has advanced.
    void signalAllWhenBlocking();
}

/// Busy spin strategy that repeatedly checks the dependent sequence.
class BusySpinWaitStrategy : WaitStrategy
{
    override long waitFor(long sequence, shared Sequence cursor, shared Sequence dependentSequence, SequenceBarrier barrier)
    {
        long available;
        while ((available = dependentSequence.get()) < sequence)
        {
            barrier.checkAlert();
            pause();
        }
        return available;
    }

    override void signalAllWhenBlocking()
    {
        // no-op for busy spin
    }
}

unittest
{
    import core.thread : Thread;
    import core.time : msecs;

    // simple barrier implementation
    class DummySequenceBarrier : SequenceBarrier
    {
        override long waitFor(long sequence) { return 0; }
        override long getCursor() { return 0; }
        override bool isAlerted() { return false; }
        override void alert() {}
        override void clearAlert() {}
        override void checkAlert() {}
    }

    auto strategy = new BusySpinWaitStrategy();
    auto cursor = new shared Sequence(0); // unused by strategy
    auto dependent = new shared Sequence(); // starts at INITIAL_VALUE (-1)
    auto barrier = new DummySequenceBarrier();

    auto t = new Thread({
        Thread.sleep(50.msecs);
        dependent.incrementAndGet();
        strategy.signalAllWhenBlocking();
    });
    t.start();

    // Wait for sequence 0
    auto result = strategy.waitFor(0, cursor, dependent, barrier);
    assert(result == 0);
    t.join();
}

public import disruptor.blockingwaitstrategy;
public import disruptor.sleepingwaitstrategy;
public import disruptor.yieldingwaitstrategy;
