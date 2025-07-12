module disruptor.abstractsequencer;

import disruptor.sequence : Sequence;
import disruptor.waitstrategy : WaitStrategy;
import disruptor.sequencer : Sequencer, SequenceBarrier, Cursored, DataProvider, EventPoller;
import disruptor.sequencegroup : addSequences, removeSequence;
import disruptor.processingsequencebarrier : ProcessingSequenceBarrier;
import disruptor.util : utilGetMinimumSequence = getMinimumSequence;

/// Base class providing common sequencer functionality.
abstract class AbstractSequencer : Sequencer
{
protected:
    int bufferSize;
    shared WaitStrategy waitStrategy;
    shared Sequence cursor;
    align(16) shared Sequence[] gatingSequences = [];

public:
    this(int bufferSize, shared WaitStrategy waitStrategy)
    {
        if (bufferSize < 1)
            throw new Exception("bufferSize must not be less than 1");
        if ((bufferSize & (bufferSize - 1)) != 0)
            throw new Exception("bufferSize must be a power of 2");

        this.bufferSize = bufferSize;
        this.waitStrategy = waitStrategy;
        this.cursor = new shared Sequence(Sequencer.INITIAL_CURSOR_VALUE);
    }

    this(int bufferSize, shared WaitStrategy waitStrategy) shared
    {
        if (bufferSize < 1)
            throw new Exception("bufferSize must not be less than 1");
        if ((bufferSize & (bufferSize - 1)) != 0)
            throw new Exception("bufferSize must be a power of 2");

        this.bufferSize = bufferSize;
        this.waitStrategy = waitStrategy;
        this.cursor = new shared Sequence(Sequencer.INITIAL_CURSOR_VALUE);
    }

    /// Return the current cursor value.
    override long getCursor() shared @nogc nothrow
    {
        return cursor.get();
    }

    /// Return the ring buffer size.
    override int getBufferSize() @nogc nothrow
    {
        return bufferSize;
    }

    /// Add gating sequences to be tracked by this sequencer.
    override void addGatingSequences(shared Sequence[] sequencesToAdd...) shared
    {
        addSequences(&gatingSequences, this, sequencesToAdd);
    }

    /// Remove a gating sequence.
    override bool removeGatingSequence(shared Sequence sequence) shared
    {
        return removeSequence(&gatingSequences, sequence);
    }

    /// Get the minimum sequence seen by gating sequences.
    override long getMinimumSequence() shared @nogc nothrow
    {
        return utilGetMinimumSequence(gatingSequences, cursor.get());
    }

    /// Create a new sequence barrier tracking the given sequences.
    override shared(SequenceBarrier) newBarrier(shared Sequence[] sequencesToTrack...) shared
    {
        return new shared ProcessingSequenceBarrier(this, waitStrategy, cursor, sequencesToTrack);
    }

    // Abstract methods to be provided by subclasses.
    abstract override void claim(long sequence);
    abstract override bool isAvailable(long sequence) shared;
    abstract override bool hasAvailableCapacity(int requiredCapacity) shared;
    abstract override long remainingCapacity() shared;
    abstract override long next() shared;
    abstract override long next(int n) shared;
    abstract override long tryNext() shared;
    abstract override long tryNext(int n) shared;
    abstract override void publish(long sequence) shared;
    abstract override void publish(long lo, long hi) shared;
    abstract override long getHighestPublishedSequence(long nextSequence, long availableSequence) shared;
    EventPoller!T newPoller(T)(shared DataProvider!T provider, shared Sequence[] gatingSequences...) shared
    {
        return EventPoller!T.newInstance(provider, cast(shared Sequencer)this,
                new shared Sequence(), cursor, gatingSequences);
    }
}

unittest
{
    import disruptor.sleepingwaitstrategy : SleepingWaitStrategy;

    // Minimal implementation for testing.
    class DummySequencer : AbstractSequencer
    {
        this(int size, shared WaitStrategy strategy)
        {
            super(size, strategy);
        }

        this(int size, shared WaitStrategy strategy) shared
        {
            super(size, strategy);
        }

        void setCursor(long value) shared
        {
            cursor.set(value);
        }

        override void claim(long sequence) {}
        override bool isAvailable(long sequence) shared { return true; }
        override bool hasAvailableCapacity(int requiredCapacity) shared { return true; }
        override long remainingCapacity() shared { return 0; }
        override long next() shared { return 0; }
        override long next(int n) shared { return 0; }
        override long tryNext() shared { return 0; }
        override long tryNext(int n) shared { return 0; }
        override void publish(long sequence) shared {}
        override void publish(long lo, long hi) shared {}
        override long getHighestPublishedSequence(long nextSequence, long availableSequence) shared { return availableSequence; }
        EventPoller!T newPoller(T)(shared DataProvider!T provider, shared Sequence[] gatingSequences...) shared { return null; }
    }

    auto strategy = new shared SleepingWaitStrategy();
    shared DummySequencer seq = new shared DummySequencer(8, strategy);

    auto g1 = new shared Sequence();
    auto g2 = new shared Sequence();

    seq.addGatingSequences(g1, g2);
    assert(g1.get == seq.cursor.get());
    assert(g2.get == seq.cursor.get());

    seq.setCursor(7);

    // Both gating sequences at initial value -> minimum equals initial value
    assert(seq.getMinimumSequence() == Sequence.INITIAL_VALUE);

    g1.set(5);
    g2.set(7);
    assert(seq.getMinimumSequence() == 5);

    assert(seq.removeGatingSequence(g1));
    assert(!seq.removeGatingSequence(g1));
    assert(seq.getMinimumSequence() == 7);
}
