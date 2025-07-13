module disruptor.liteblockingwaitstrategy;

public import core.atomic : MemoryOrder, atomicLoad, atomicStore, pause;
import core.sync.mutex : Mutex;
import core.sync.condition : Condition;
import disruptor.sequence : Sequence;
import disruptor.sequencer : SequenceBarrier;
import disruptor.waitstrategy : WaitStrategy;

/// Blocking strategy that reduces lock contention by tracking when signalling is needed.
class LiteBlockingWaitStrategy : WaitStrategy
{
    private shared Mutex _mutex;
    private shared Condition _cond;
    private shared bool _signalNeeded = false;

    this() shared
    {
        _mutex = new shared Mutex();
        _cond = new shared Condition(_mutex);
    }

    override long waitFor(long sequence, shared Sequence cursorSequence,
            shared Sequence dependentSequence, shared SequenceBarrier barrier) shared
    {
        long availableSequence;
        if (cursorSequence.get() < sequence)
        {
            _mutex.lock();
            scope(exit) _mutex.unlock();
            do
            {
                atomicStore!(MemoryOrder.rel)(_signalNeeded, true);

                if (cursorSequence.get() >= sequence)
                {
                    break;
                }

                barrier.checkAlert();
                _cond.wait();
            }
            while (cursorSequence.get() < sequence);
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
        return "LiteBlockingWaitStrategy{" ~
            "signalNeeded=" ~ to!string(atomicLoad!(MemoryOrder.acq)(_signalNeeded)) ~
            "}";
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

    auto strategy = new shared LiteBlockingWaitStrategy();
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

