module disruptor.processingsequencebarrier;

import core.atomic : MemoryOrder, atomicLoad, atomicStore;
import disruptor.sequence : Sequence;
import disruptor.fixedsequencegroup : FixedSequenceGroup;
import disruptor.waitstrategy : WaitStrategy;
import disruptor.sequencer : Sequencer, SequenceBarrier, DataProvider, EventPoller;
import disruptor.alertexception : AlertException;

/// Coordination barrier for tracking a cursor and dependent sequences.
class ProcessingSequenceBarrier : SequenceBarrier
{
private:
    shared Sequencer _sequencer;
    shared WaitStrategy _waitStrategy;
    shared Sequence _cursorSequence;
    shared Sequence _dependentSequence;
    shared bool _alerted = false;


public:
    this(shared Sequencer sequencer, shared WaitStrategy waitStrategy,
            shared Sequence cursorSequence, shared Sequence[] dependentSequences = [])
    {
        this._sequencer = sequencer;
        this._waitStrategy = waitStrategy;
        this._cursorSequence = cursorSequence;

        if (dependentSequences.length == 0)
        {
            this._dependentSequence = cursorSequence;
        }
        else
        {
            this._dependentSequence = new shared FixedSequenceGroup(dependentSequences);
        }
    }

    this(shared Sequencer sequencer, shared WaitStrategy waitStrategy,
            shared Sequence cursorSequence, shared Sequence[] dependentSequences = []) shared
    {
        this._sequencer = sequencer;
        this._waitStrategy = waitStrategy;
        this._cursorSequence = cursorSequence;

        if (dependentSequences.length == 0)
        {
            this._dependentSequence = cursorSequence;
        }
        else
        {
            this._dependentSequence = new shared FixedSequenceGroup(dependentSequences);
        }
    }

    override long waitFor(long sequence) shared
    {
        checkAlert();

        auto availableSequence =
            _waitStrategy.waitFor(sequence, _cursorSequence, _dependentSequence, this);

        if (availableSequence < sequence)
        {
            return availableSequence;
        }

        return _sequencer.getHighestPublishedSequence(sequence, availableSequence);
    }

    override long getCursor() shared @safe nothrow @nogc
    {
        return _dependentSequence.get();
    }

    override bool isAlerted() shared @safe nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.acq)(_alerted);
    }

    override void alert() shared
    {
        atomicStore!(MemoryOrder.rel)(_alerted, true);
        _waitStrategy.signalAllWhenBlocking();
    }

    override void clearAlert() shared @safe nothrow @nogc
    {
        atomicStore!(MemoryOrder.rel)(_alerted, false);
    }

    override void checkAlert() shared
    {
        if (atomicLoad!(MemoryOrder.acq)(_alerted))
        {
            throw AlertException.INSTANCE;
        }
    }
}

unittest
{
    import core.thread : Thread;
    import core.time : msecs;
    import disruptor.waitstrategy : BusySpinWaitStrategy;

    // Dummy sequencer that simply returns the available sequence
    class DummySequencer : Sequencer
    {
        shared Sequence cursor;
        this(shared Sequence cursor) shared { this.cursor = cursor; }
        override long getCursor() shared { return cursor.get(); }
        override int getBufferSize() { return 0; }
        override bool hasAvailableCapacity(int requiredCapacity) shared { return false; }
        override long remainingCapacity() shared { return 0; }
        override long next() shared { return 0; }
        override long next(int n) shared { return 0; }
        override long tryNext() shared { return 0; }
        override long tryNext(int n) shared { return 0; }
        override void publish(long sequence) shared {}
        override void publish(long lo, long hi) shared {}
        override void claim(long sequence) shared {}
        override bool isAvailable(long sequence) shared { return false; }
        override void addGatingSequences(shared Sequence[] gatingSequences...) shared {}
        override bool removeGatingSequence(shared Sequence sequence) shared { return false; }
        override shared(SequenceBarrier) newBarrier(shared Sequence[] sequencesToTrack...) shared { return null; }
        override long getMinimumSequence() shared { return 0; }
        override long getHighestPublishedSequence(long nextSequence, long availableSequence) shared { return availableSequence; }
        shared(EventPoller!T) newPoller(T)(shared DataProvider!T provider, shared Sequence[] gatingSequences...) shared { return null; }
    }

    auto cursor = new shared Sequence(10);
    auto sequencer = new shared DummySequencer(cursor);
    auto waitStrategy = new shared BusySpinWaitStrategy();

    auto dep1 = new shared Sequence(10);
    auto dep2 = new shared Sequence(9);
    auto dep3 = new shared Sequence(10);

    auto barrier = new shared ProcessingSequenceBarrier(sequencer, waitStrategy, cursor, [dep1, dep2, dep3]);
    auto result = barrier.waitFor(9);
    assert(result >= 9);

    // alert status
    assert(!barrier.isAlerted());
    barrier.alert();
    assert(barrier.isAlerted());
    barrier.clearAlert();
    assert(!barrier.isAlerted());

    // alert behaviour during wait
    bool caught = false;
    auto dep4 = new shared Sequence(0);
    auto barrier2 = new shared ProcessingSequenceBarrier(sequencer, waitStrategy, cursor, [dep4]);
    auto t = new Thread({
        try { barrier2.waitFor(1); } catch(Exception e) { caught = true; }
    });
    t.start();
    Thread.sleep(50.msecs);
    barrier2.alert();
    t.join();
    assert(caught);

    // wait when sequences advance later
    auto worker1 = new shared Sequence(8);
    auto worker2 = new shared Sequence(8);
    auto worker3 = new shared Sequence(8);
    auto barrier3 = new shared ProcessingSequenceBarrier(sequencer, waitStrategy, cursor, [worker1, worker2, worker3]);
    auto thread = new Thread({
        Thread.sleep(20.msecs);
        foreach (ref seq; [worker1, worker2, worker3])
            seq.incrementAndGet();
    });
    thread.start();
    auto res = barrier3.waitFor(9); // workers will move to 9
    assert(res >= 9);
    thread.join();
}

