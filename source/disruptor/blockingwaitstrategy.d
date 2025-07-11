module disruptor.blockingwaitstrategy;

import core.sync.mutex : Mutex;
import core.sync.condition : Condition;
import core.atomic : pause;
import core.thread : Thread;
import disruptor.sequence;
import disruptor.sequencer : SequenceBarrier;
import disruptor.waitstrategy : WaitStrategy;

/// Blocking strategy that waits on a condition variable.
class BlockingWaitStrategy : WaitStrategy
{
    private shared Mutex _mutex;
    private shared Condition _cond;

    this() shared
    {
        _mutex = new shared Mutex();
        _cond = new shared Condition(_mutex);
    }

    override long waitFor(long sequence, shared Sequence cursor, shared Sequence dependentSequence, shared SequenceBarrier barrier) shared
    {
        long availableSequence;
        if (cursor.get() < sequence)
        {
            _mutex.lock();
            scope(exit) _mutex.unlock();
            while (cursor.get() < sequence)
            {
                barrier.checkAlert();
                _cond.wait();
            }
        }

        while ((availableSequence = dependentSequence.get()) < sequence)
        {
            barrier.checkAlert();
            pause();
        }
        return availableSequence;
    }

    override void signalAllWhenBlocking() shared
    {
        _mutex.lock();
        scope(exit) _mutex.unlock();
        _cond.notifyAll();
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

    auto strategy = new shared BlockingWaitStrategy();
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
