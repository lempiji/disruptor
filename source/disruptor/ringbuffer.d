module disruptor.ringbuffer;

import disruptor.sequencer : Sequencer, Sequenced, Cursored, SequenceBarrier, DataProvider, EventPoller;
import disruptor.sequence : Sequence;
import disruptor.singleproducersequencer : SingleProducerSequencer;
import disruptor.multiproducersequencer : MultiProducerSequencer;
import disruptor.waitstrategy : WaitStrategy, BlockingWaitStrategy;
import disruptor.insufficientcapacityexception : InsufficientCapacityException;

/// Simple ring buffer backed by an array and a Sequencer.
alias EventFactory(T) = shared(T) delegate();

class RingBuffer(T) : DataProvider!T, Sequenced, Cursored
{
private:
    shared T[] entries;
    int indexMask;
    int bufferSize;
    shared Sequencer sequencer;

    this(EventFactory!T factory, int bufferSize, shared Sequencer sequencer)
    {
        this.bufferSize = bufferSize;
        this.indexMask = bufferSize - 1;
        this.sequencer = sequencer;
        entries = new shared T[](bufferSize);
        foreach (i; 0 .. bufferSize)
            entries[i] = factory();
    }

    this(EventFactory!T factory, int bufferSize, shared Sequencer sequencer) shared
    {
        this.bufferSize = bufferSize;
        this.indexMask = bufferSize - 1;
        this.sequencer = sequencer;
        entries = new shared T[](bufferSize);
        foreach (i; 0 .. bufferSize)
            entries[i] = factory();
    }

public:
    /// Create a ring buffer for a single producer.
    static shared(RingBuffer!T) createSingleProducer(EventFactory!T factory, int bufferSize, shared WaitStrategy waitStrategy)
    {
        auto seq = new shared SingleProducerSequencer(bufferSize, waitStrategy);
        return new shared RingBuffer!T(factory, bufferSize, seq);
    }

    /// Create a ring buffer for multiple producers.
    static shared(RingBuffer!T) createMultiProducer(EventFactory!T factory, int bufferSize, shared WaitStrategy waitStrategy)
    {
        auto seq = new shared MultiProducerSequencer(bufferSize, waitStrategy);
        return new shared RingBuffer!T(factory, bufferSize, seq);
    }

    override T get(long sequence) shared
    {
        return cast(T) entries[cast(size_t)(sequence & indexMask)];
    }

    override long next() shared
    {
        return sequencer.next();
    }

    override long next(int n) shared
    {
        return sequencer.next(n);
    }

    override long tryNext() shared
    {
        return sequencer.tryNext();
    }

    override long tryNext(int n) shared
    {
        return sequencer.tryNext(n);
    }

    override void publish(long sequence) shared
    {
        sequencer.publish(sequence);
    }

    override void publish(long lo, long hi) shared
    {
        sequencer.publish(lo, hi);
    }

    override int getBufferSize()
    {
        return bufferSize;
    }

    override bool hasAvailableCapacity(int requiredCapacity) shared
    {
        return sequencer.hasAvailableCapacity(requiredCapacity);
    }

    override long remainingCapacity() shared
    {
        return sequencer.remainingCapacity();
    }

    override long getCursor() shared
    {
        return sequencer.getCursor();
    }

    bool isAvailable(long sequence) shared
    {
        return sequencer.isAvailable(sequence);
    }

    void addGatingSequences(shared Sequence[] sequences...) shared
    {
        sequencer.addGatingSequences(sequences);
    }

    long getMinimumGatingSequence() shared
    {
        return sequencer.getMinimumSequence();
    }

    bool removeGatingSequence(shared Sequence sequence) shared
    {
        return sequencer.removeGatingSequence(sequence);
    }

    SequenceBarrier newBarrier(shared Sequence[] sequences...) shared
    {
        return sequencer.newBarrier(sequences);
    }
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;

    class StubEvent
    {
        long value;
    }

    auto rb = RingBuffer!StubEvent.createSingleProducer(() => new shared StubEvent(), 4, new shared BlockingWaitStrategy());
    auto seq = rb.next();
    auto evt = rb.get(seq);
    evt.value = 42;
    rb.publish(seq);

    assert(rb.get(seq).value == 42);

    auto g1 = new shared Sequence();
    auto g2 = new shared Sequence();
    rb.addGatingSequences(g1, g2);
    assert(rb.removeGatingSequence(g1));
}

