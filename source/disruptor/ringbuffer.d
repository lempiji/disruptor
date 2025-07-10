module disruptor.ringbuffer;

import disruptor.sequencer : Sequencer, SequenceBarrier, Cursored, DataProvider, EventPoller;
import disruptor.multiproducersequencer : MultiProducerSequencer;
import disruptor.waitstrategy : WaitStrategy, BlockingWaitStrategy;
import disruptor.sequence : Sequence;

/// Defines producer types for ring buffer creation.
enum ProducerType
{
    SINGLE,
    MULTI
}

/// Factory function type used to preallocate ring buffer entries.
alias EventFactory(T) = T delegate();

/**
 * Ring based store of reusable entries.
 */
final class RingBuffer(T) : Cursored, DataProvider!T
{
    enum long INITIAL_CURSOR_VALUE = Sequence.INITIAL_VALUE;

private:
    int bufferSize;
    size_t indexMask;
    T[] entries;
    Sequencer sequencer;

public:
    this(EventFactory!T factory, Sequencer sequencer)
    {
        this.sequencer = sequencer;
        bufferSize = sequencer.getBufferSize();
        if (bufferSize < 1)
            throw new Exception("bufferSize must not be less than 1");
        if ((bufferSize & (bufferSize - 1)) != 0)
            throw new Exception("bufferSize must be a power of 2");

        indexMask = bufferSize - 1;
        entries = new T[](bufferSize);
        foreach (i; 0 .. bufferSize)
            entries[i] = factory();
    }

    static RingBuffer!T createMultiProducer(T)(EventFactory!T factory, int bufferSize, shared WaitStrategy waitStrategy)
    {
        auto seq = new MultiProducerSequencer(bufferSize, waitStrategy);
        return new RingBuffer!T(factory, seq);
    }

    static RingBuffer!T createMultiProducer(T)(EventFactory!T factory, int bufferSize)
    {
        return createMultiProducer(factory, bufferSize, new shared BlockingWaitStrategy());
    }

    static RingBuffer!T createSingleProducer(T)(EventFactory!T factory, int bufferSize, shared WaitStrategy waitStrategy)
    {
        // SingleProducerSequencer not yet ported; use MultiProducerSequencer
        auto seq = new MultiProducerSequencer(bufferSize, waitStrategy);
        return new RingBuffer!T(factory, seq);
    }

    static RingBuffer!T createSingleProducer(T)(EventFactory!T factory, int bufferSize)
    {
        return createSingleProducer(factory, bufferSize, new shared BlockingWaitStrategy());
    }

    static RingBuffer!T create(T)(ProducerType producerType, EventFactory!T factory, int bufferSize, shared WaitStrategy waitStrategy)
    {
        final switch (producerType)
        {
            case ProducerType.SINGLE:
                return createSingleProducer(factory, bufferSize, waitStrategy);
            case ProducerType.MULTI:
                return createMultiProducer(factory, bufferSize, waitStrategy);
        }
        assert(0);
    }

    override T get(long sequence)
    {
        return entries[cast(size_t)(sequence & indexMask)];
    }

    T claimAndGetPreallocated(long sequence)
    {
        sequencer.claim(sequence);
        return get(sequence);
    }

    long next()
    {
        return sequencer.next();
    }

    long next(int n)
    {
        return sequencer.next(n);
    }

    long tryNext()
    {
        return sequencer.tryNext();
    }

    long tryNext(int n)
    {
        return sequencer.tryNext(n);
    }

    void publish(long sequence)
    {
        sequencer.publish(sequence);
    }

    void publish(long lo, long hi)
    {
        sequencer.publish(lo, hi);
    }

    bool isAvailable(long sequence)
    {
        return sequencer.isAvailable(sequence);
    }

    void addGatingSequences(shared Sequence[] sequences...)
    {
        sequencer.addGatingSequences(sequences);
    }

    bool removeGatingSequence(shared Sequence sequence)
    {
        return sequencer.removeGatingSequence(sequence);
    }

    long getMinimumGatingSequence()
    {
        return sequencer.getMinimumSequence();
    }

    SequenceBarrier newBarrier(shared Sequence[] sequencesToTrack...)
    {
        return sequencer.newBarrier(sequencesToTrack);
    }


    override long getCursor() shared
    {
        return sequencer.getCursor();
    }

    int getBufferSize() @nogc nothrow
    {
        return bufferSize;
    }

    long remainingCapacity()
    {
        return sequencer.remainingCapacity();
    }
}

unittest
{
    import disruptor.waitstrategy : BusySpinWaitStrategy;

    class StubEvent
    {
        int value;
        this(int v = 0) { value = v; }
    }

    EventFactory!StubEvent factory = delegate() { return new StubEvent(); };
    auto mps = new MultiProducerSequencer(8, new shared BusySpinWaitStrategy());
    auto rb = new RingBuffer!StubEvent(factory, mps);
    auto barrier = rb.newBarrier();

    long seqVal = rb.next();
    auto evt = rb.get(seqVal);
    evt.value = 7;
    rb.publish(seqVal);
    assert((cast(shared)barrier).waitFor(seqVal) >= seqVal);
    assert(rb.get(seqVal).value == 7);

    // wrap around
    foreach (i; 0 .. rb.getBufferSize * 2)
    {
        long s = rb.next();
        rb.publish(s);
    }
    assert(rb.isAvailable(rb.getBufferSize * 2 - 1));
}

