module disruptor.processingsequencebarrier;

import disruptor.sequence : Sequence;
import disruptor.fixedsequencegroup : FixedSequenceGroup;
import disruptor.waitstrategy : WaitStrategy;
import disruptor.sequencer : Sequencer, SequenceBarrier, DataProvider, EventPoller;

/// Exception thrown when a SequenceBarrier is alerted.
class AlertException : Exception
{
    this(string msg = "Alerted", string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Coordination barrier for tracking a cursor and dependent sequences.
class ProcessingSequenceBarrier : SequenceBarrier
{
private:
    Sequencer _sequencer;
    WaitStrategy _waitStrategy;
    shared Sequence _cursorSequence;
    shared Sequence _dependentSequence;
    bool _alerted = false;

public:
    this(Sequencer sequencer, WaitStrategy waitStrategy,
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

    override long waitFor(long sequence) shared
    {
        checkAlert();

        auto availableSequence =
            _waitStrategy.waitFor(sequence, _cursorSequence, _dependentSequence, this);

        if (availableSequence < sequence)
        {
            return availableSequence;
        }

        return (cast(Sequencer)_sequencer).getHighestPublishedSequence(sequence, availableSequence);
    }

    override long getCursor() shared
    {
        return _dependentSequence.get();
    }

    override bool isAlerted() shared
    {
        return _alerted;
    }

    override void alert() shared
    {
        _alerted = true;
        _waitStrategy.signalAllWhenBlocking();
    }

    override void clearAlert() shared
    {
        _alerted = false;
    }

    override void checkAlert() shared
    {
        if (_alerted)
        {
            throw new AlertException();
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
        this(shared Sequence cursor) { this.cursor = cursor; }
        override long getCursor() shared { return cursor.get(); }
        override int getBufferSize() { return 0; }
        override bool hasAvailableCapacity(int requiredCapacity) { return false; }
        override long remainingCapacity() { return 0; }
        override long next() { return 0; }
        override long next(int n) { return 0; }
        override long tryNext() { return 0; }
        override long tryNext(int n) { return 0; }
        override void publish(long sequence) {}
        override void publish(long lo, long hi) {}
        override void claim(long sequence) {}
        override bool isAvailable(long sequence) { return false; }
        override void addGatingSequences(shared Sequence[] gatingSequences...) {}
        override bool removeGatingSequence(shared Sequence sequence) { return false; }
        override SequenceBarrier newBarrier(shared Sequence[] sequencesToTrack...) { return null; }
        override long getMinimumSequence() { return 0; }
        override long getHighestPublishedSequence(long nextSequence, long availableSequence) { return availableSequence; }
        EventPoller!T newPoller(T)(DataProvider!T provider, shared Sequence[] gatingSequences...) { return null; }
    }

    auto cursor = new shared Sequence(10);
    auto sequencer = new DummySequencer(cursor);
    auto waitStrategy = new BusySpinWaitStrategy();

    auto dep1 = new shared Sequence(10);
    auto dep2 = new shared Sequence(9);
    auto dep3 = new shared Sequence(10);

    auto barrier = cast(shared) new ProcessingSequenceBarrier(sequencer, waitStrategy, cursor, [dep1, dep2, dep3]);
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
    auto barrier2 = cast(shared) new ProcessingSequenceBarrier(sequencer, waitStrategy, cursor, [dep4]);
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
    auto barrier3 = cast(shared) new ProcessingSequenceBarrier(sequencer, waitStrategy, cursor, [worker1, worker2, worker3]);
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

