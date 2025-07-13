module disruptor.ringbuffer;

import disruptor.sequencer : Sequencer, Sequenced, Cursored, SequenceBarrier, DataProvider, EventPoller;
import disruptor.abstractsequencer : AbstractSequencer;
import disruptor.sequence : Sequence;
import disruptor.singleproducersequencer : SingleProducerSequencer;
import disruptor.multiproducersequencer : MultiProducerSequencer;
import disruptor.producertype : ProducerType;
import disruptor.waitstrategy : WaitStrategy, BlockingWaitStrategy;
import disruptor.insufficientcapacityexception : InsufficientCapacityException;
import disruptor.eventsink : EventSink;
import disruptor.eventtranslator;
import std.conv : to;

/// Simple ring buffer backed by an array and a Sequencer.
alias EventFactory(T) = shared(T) delegate();

class RingBuffer(T) : DataProvider!T, Sequenced, Cursored, EventSink!T
{
private:
    enum int BUFFER_PAD = 32;
    shared T[] entries;
    int indexMask;
    int bufferSize;
    shared AbstractSequencer sequencer;

    this(EventFactory!T factory, int bufferSize, shared AbstractSequencer sequencer)
    {
        if (bufferSize < 1)
            throw new Exception("bufferSize must not be less than 1");
        if ((bufferSize & (bufferSize - 1)) != 0)
            throw new Exception("bufferSize must be a power of 2");

        this.bufferSize = bufferSize;
        this.indexMask = bufferSize - 1;
        this.sequencer = sequencer;
        entries = new shared T[](bufferSize + 2 * BUFFER_PAD);
        foreach (i; 0 .. bufferSize)
            entries[BUFFER_PAD + i] = factory();
    }

    this(EventFactory!T factory, int bufferSize, shared AbstractSequencer sequencer) shared
    {
        if (bufferSize < 1)
            throw new Exception("bufferSize must not be less than 1");
        if ((bufferSize & (bufferSize - 1)) != 0)
            throw new Exception("bufferSize must be a power of 2");

        this.bufferSize = bufferSize;
        this.indexMask = bufferSize - 1;
        this.sequencer = sequencer;
        entries = new shared T[](bufferSize + 2 * BUFFER_PAD);
        foreach (i; 0 .. bufferSize)
            entries[BUFFER_PAD + i] = factory();
    }

    shared(T) elementAt(long sequence) shared nothrow
    {
        return entries[BUFFER_PAD + cast(size_t)(sequence & indexMask)];
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

    /// Create a ring buffer with the given producer type.
    static shared(RingBuffer!T) create(ProducerType producerType, EventFactory!T factory, int bufferSize, shared WaitStrategy waitStrategy)
    {
        final switch (producerType)
        {
        case ProducerType.SINGLE:
            return createSingleProducer(factory, bufferSize, waitStrategy);
        case ProducerType.MULTI:
            return createMultiProducer(factory, bufferSize, waitStrategy);
        }
        throw new Exception(producerType.to!string);
    }

    override shared(T) get(long sequence) shared nothrow
    {
        return elementAt(sequence);
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

    /**
     * Claim a specific sequence and return the preallocated entry.
     * The cursor will only advance when the sequence is subsequently published.
     */
    shared(T) claimAndGetPreallocated(long sequence) shared
    {
        sequencer.claim(sequence);
        return get(sequence);
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

    shared(SequenceBarrier) newBarrier(shared Sequence[] sequences...) shared
    {
        return sequencer.newBarrier(sequences);
    }

    shared(EventPoller!T) newPoller(shared Sequence[] gatingSequences...) shared
    {
        return sequencer.newPoller!T(this, gatingSequences);
    }

    // EventSink implementation using translators ---------------------------------

    override void publishEvent(EventTranslator!T translator) shared
    {
        auto seq = sequencer.next();
        translateAndPublish(translator, seq);
    }

    override bool tryPublishEvent(EventTranslator!T translator) shared
    {
        try
        {
            auto seq = sequencer.tryNext();
            translateAndPublish(translator, seq);
            return true;
        }
        catch (InsufficientCapacityException e)
        {
            return false;
        }
    }

    void publishEvent(A)(EventTranslatorOneArg!(T, A) translator, A arg0) shared
    {
        auto seq = sequencer.next();
        translateAndPublish(translator, seq, arg0);
    }

    bool tryPublishEvent(A)(EventTranslatorOneArg!(T, A) translator, A arg0) shared
    {
        try
        {
            auto seq = sequencer.tryNext();
            translateAndPublish(translator, seq, arg0);
            return true;
        }
        catch (InsufficientCapacityException e)
        {
            return false;
        }
    }

    void publishEvent(A, B)(EventTranslatorTwoArg!(T, A, B) translator, A arg0, B arg1) shared
    {
        auto seq = sequencer.next();
        translateAndPublish(translator, seq, arg0, arg1);
    }

    bool tryPublishEvent(A, B)(EventTranslatorTwoArg!(T, A, B) translator, A arg0, B arg1) shared
    {
        try
        {
            auto seq = sequencer.tryNext();
            translateAndPublish(translator, seq, arg0, arg1);
            return true;
        }
        catch (InsufficientCapacityException e)
        {
            return false;
        }
    }

    void publishEvent(A, B, C)(EventTranslatorThreeArg!(T, A, B, C) translator, A arg0, B arg1, C arg2) shared
    {
        auto seq = sequencer.next();
        translateAndPublish(translator, seq, arg0, arg1, arg2);
    }

    bool tryPublishEvent(A, B, C)(EventTranslatorThreeArg!(T, A, B, C) translator, A arg0, B arg1, C arg2) shared
    {
        try
        {
            auto seq = sequencer.tryNext();
            translateAndPublish(translator, seq, arg0, arg1, arg2);
            return true;
        }
        catch (InsufficientCapacityException e)
        {
            return false;
        }
    }

    void publishEvent(Args...)(EventTranslatorVararg!T translator, Args args) shared
    {
        auto seq = sequencer.next();
        translateAndPublish(translator, seq, args);
    }

    bool tryPublishEvent(Args...)(EventTranslatorVararg!T translator, Args args) shared
    {
        try
        {
            auto seq = sequencer.tryNext();
            translateAndPublish(translator, seq, args);
            return true;
        }
        catch (InsufficientCapacityException e)
        {
            return false;
        }
    }

    override void publishEvents(EventTranslator!T[] translators) shared
    {
        publishEvents(translators, 0, cast(int)translators.length);
    }

    override void publishEvents(EventTranslator!T[] translators, int batchStartsAt, int batchSize) shared
    {
        checkBounds(translators, batchStartsAt, batchSize);
        auto finalSeq = sequencer.next(batchSize);
        translateAndPublishBatch(translators, batchStartsAt, batchSize, finalSeq);
    }

    override bool tryPublishEvents(EventTranslator!T[] translators) shared
    {
        return tryPublishEvents(translators, 0, cast(int)translators.length);
    }

    override bool tryPublishEvents(EventTranslator!T[] translators, int batchStartsAt, int batchSize) shared
    {
        checkBounds(translators, batchStartsAt, batchSize);
        try
        {
            auto finalSeq = sequencer.tryNext(batchSize);
            translateAndPublishBatch(translators, batchStartsAt, batchSize, finalSeq);
            return true;
        }
        catch (InsufficientCapacityException e)
        {
            return false;
        }
    }

    void publishEvents(A)(EventTranslatorOneArg!(T, A) translator, A[] arg0) shared
    {
        publishEvents(translator, 0, cast(int)arg0.length, arg0);
    }

    void publishEvents(A)(EventTranslatorOneArg!(T, A) translator, int batchStartsAt, int batchSize, A[] arg0) shared
    {
        checkBounds(arg0, batchStartsAt, batchSize);
        auto finalSeq = sequencer.next(batchSize);
        translateAndPublishBatch(translator, arg0, batchStartsAt, batchSize, finalSeq);
    }

    bool tryPublishEvents(A)(EventTranslatorOneArg!(T, A) translator, A[] arg0) shared
    {
        return tryPublishEvents(translator, 0, cast(int)arg0.length, arg0);
    }

    bool tryPublishEvents(A)(EventTranslatorOneArg!(T, A) translator, int batchStartsAt, int batchSize, A[] arg0) shared
    {
        checkBounds(arg0, batchStartsAt, batchSize);
        try
        {
            auto finalSeq = sequencer.tryNext(batchSize);
            translateAndPublishBatch(translator, arg0, batchStartsAt, batchSize, finalSeq);
            return true;
        }
        catch (InsufficientCapacityException e)
        {
            return false;
        }
    }

    void publishEvents(A, B)(EventTranslatorTwoArg!(T, A, B) translator, A[] arg0, B[] arg1) shared
    {
        publishEvents(translator, 0, cast(int)arg0.length, arg0, arg1);
    }

    void publishEvents(A, B)(EventTranslatorTwoArg!(T, A, B) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1) shared
    {
        checkBounds(arg0, arg1, batchStartsAt, batchSize);
        auto finalSeq = sequencer.next(batchSize);
        translateAndPublishBatch(translator, arg0, arg1, batchStartsAt, batchSize, finalSeq);
    }

    bool tryPublishEvents(A, B)(EventTranslatorTwoArg!(T, A, B) translator, A[] arg0, B[] arg1) shared
    {
        return tryPublishEvents(translator, 0, cast(int)arg0.length, arg0, arg1);
    }

    bool tryPublishEvents(A, B)(EventTranslatorTwoArg!(T, A, B) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1) shared
    {
        checkBounds(arg0, arg1, batchStartsAt, batchSize);
        try
        {
            auto finalSeq = sequencer.tryNext(batchSize);
            translateAndPublishBatch(translator, arg0, arg1, batchStartsAt, batchSize, finalSeq);
            return true;
        }
        catch (InsufficientCapacityException e)
        {
            return false;
        }
    }

    void publishEvents(A, B, C)(EventTranslatorThreeArg!(T, A, B, C) translator, A[] arg0, B[] arg1, C[] arg2) shared
    {
        publishEvents(translator, 0, cast(int)arg0.length, arg0, arg1, arg2);
    }

    void publishEvents(A, B, C)(EventTranslatorThreeArg!(T, A, B, C) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1, C[] arg2) shared
    {
        checkBounds(arg0, arg1, arg2, batchStartsAt, batchSize);
        auto finalSeq = sequencer.next(batchSize);
        translateAndPublishBatch(translator, arg0, arg1, arg2, batchStartsAt, batchSize, finalSeq);
    }

    bool tryPublishEvents(A, B, C)(EventTranslatorThreeArg!(T, A, B, C) translator, A[] arg0, B[] arg1, C[] arg2) shared
    {
        return tryPublishEvents(translator, 0, cast(int)arg0.length, arg0, arg1, arg2);
    }

    bool tryPublishEvents(A, B, C)(EventTranslatorThreeArg!(T, A, B, C) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1, C[] arg2) shared
    {
        checkBounds(arg0, arg1, arg2, batchStartsAt, batchSize);
        try
        {
            auto finalSeq = sequencer.tryNext(batchSize);
            translateAndPublishBatch(translator, arg0, arg1, arg2, batchStartsAt, batchSize, finalSeq);
            return true;
        }
        catch (InsufficientCapacityException e)
        {
            return false;
        }
    }

    void publishEvents(Args...)(EventTranslatorVararg!T translator, Args[] args) shared
    {
        publishEvents(translator, 0, cast(int)args.length, args);
    }

    void publishEvents(Args...)(EventTranslatorVararg!T translator, int batchStartsAt, int batchSize, Args[] args) shared
    {
        checkBounds(args, batchStartsAt, batchSize);
        auto finalSeq = sequencer.next(batchSize);
        translateAndPublishBatch(translator, batchStartsAt, batchSize, finalSeq, args);
    }

    bool tryPublishEvents(Args...)(EventTranslatorVararg!T translator, Args[] args) shared
    {
        return tryPublishEvents(translator, 0, cast(int)args.length, args);
    }

    bool tryPublishEvents(Args...)(EventTranslatorVararg!T translator, int batchStartsAt, int batchSize, Args[] args) shared
    {
        checkBounds(args, batchStartsAt, batchSize);
        try
        {
            auto finalSeq = sequencer.tryNext(batchSize);
            translateAndPublishBatch(translator, batchStartsAt, batchSize, finalSeq, args);
            return true;
        }
        catch (InsufficientCapacityException e)
        {
            return false;
        }
    }

private:
    void checkBatchSizing(int batchStartsAt, int batchSize) shared
    {
        if (batchStartsAt < 0 || batchSize < 0)
            throw new Exception("Both batchStartsAt and batchSize must be positive", __FILE__, __LINE__);
        if (batchSize > bufferSize)
            throw new Exception("The ring buffer cannot accommodate " ~ batchSize.to!string ~ " events", __FILE__, __LINE__);
    }

    void checkBounds(TT)(TT[] arr, int batchStartsAt, int batchSize) shared
    {
        checkBatchSizing(batchStartsAt, batchSize);
        if (batchStartsAt + batchSize > arr.length)
            throw new Exception("Batch overruns available arguments", __FILE__, __LINE__);
    }

    void checkBounds(A, B)(A[] arg0, B[] arg1, int batchStartsAt, int batchSize) shared
    {
        checkBounds(arg0, batchStartsAt, batchSize);
        checkBounds(arg1, batchStartsAt, batchSize);
    }

    void checkBounds(A, B, C)(A[] arg0, B[] arg1, C[] arg2, int batchStartsAt, int batchSize) shared
    {
        checkBounds(arg0, batchStartsAt, batchSize);
        checkBounds(arg1, batchStartsAt, batchSize);
        checkBounds(arg2, batchStartsAt, batchSize);
    }

    void translateAndPublish(EventTranslator!T translator, long sequence) shared
    {
        try
        {
            translator.translateTo(cast(T)get(sequence), sequence);
        }
        finally
        {
            sequencer.publish(sequence);
        }
    }

    void translateAndPublish(A)(EventTranslatorOneArg!(T, A) translator, long sequence, A arg0) shared
    {
        try
        {
            translator.translateTo(cast(T)get(sequence), sequence, arg0);
        }
        finally
        {
            sequencer.publish(sequence);
        }
    }

    void translateAndPublish(A, B)(EventTranslatorTwoArg!(T, A, B) translator, long sequence, A arg0, B arg1) shared
    {
        try
        {
            translator.translateTo(cast(T)get(sequence), sequence, arg0, arg1);
        }
        finally
        {
            sequencer.publish(sequence);
        }
    }

    void translateAndPublish(A, B, C)(EventTranslatorThreeArg!(T, A, B, C) translator, long sequence, A arg0, B arg1, C arg2) shared
    {
        try
        {
            translator.translateTo(cast(T)get(sequence), sequence, arg0, arg1, arg2);
        }
        finally
        {
            sequencer.publish(sequence);
        }
    }

    void translateAndPublish(Args...)(EventTranslatorVararg!T translator, long sequence, Args args) shared
    {
        try
        {
            translator.translateTo(cast(T)get(sequence), sequence, args);
        }
        finally
        {
            sequencer.publish(sequence);
        }
    }

    void translateAndPublishBatch(EventTranslator!T[] translators, int batchStartsAt, int batchSize, long finalSequence) shared
    {
        auto initial = finalSequence - (batchSize - 1);
        auto seq = initial;
        try
        {
            foreach (i; batchStartsAt .. batchStartsAt + batchSize)
            {
                translators[i].translateTo(cast(T)get(seq), seq);
                ++seq;
            }
        }
        finally
        {
            sequencer.publish(initial, finalSequence);
        }
    }

    void translateAndPublishBatch(A)(EventTranslatorOneArg!(T, A) translator, A[] arg0, int batchStartsAt, int batchSize, long finalSequence) shared
    {
        auto initial = finalSequence - (batchSize - 1);
        auto seq = initial;
        try
        {
            foreach (i; batchStartsAt .. batchStartsAt + batchSize)
            {
                translator.translateTo(cast(T)get(seq), seq, arg0[i]);
                ++seq;
            }
        }
        finally
        {
            sequencer.publish(initial, finalSequence);
        }
    }

    void translateAndPublishBatch(A, B)(EventTranslatorTwoArg!(T, A, B) translator, A[] arg0, B[] arg1, int batchStartsAt, int batchSize, long finalSequence) shared
    {
        auto initial = finalSequence - (batchSize - 1);
        auto seq = initial;
        try
        {
            foreach (i; batchStartsAt .. batchStartsAt + batchSize)
            {
                translator.translateTo(cast(T)get(seq), seq, arg0[i], arg1[i]);
                ++seq;
            }
        }
        finally
        {
            sequencer.publish(initial, finalSequence);
        }
    }

    void translateAndPublishBatch(A, B, C)(EventTranslatorThreeArg!(T, A, B, C) translator, A[] arg0, B[] arg1, C[] arg2, int batchStartsAt, int batchSize, long finalSequence) shared
    {
        auto initial = finalSequence - (batchSize - 1);
        auto seq = initial;
        try
        {
            foreach (i; batchStartsAt .. batchStartsAt + batchSize)
            {
                translator.translateTo(cast(T)get(seq), seq, arg0[i], arg1[i], arg2[i]);
                ++seq;
            }
        }
        finally
        {
            sequencer.publish(initial, finalSequence);
        }
    }

    void translateAndPublishBatch(Args...)(EventTranslatorVararg!T translator, int batchStartsAt, int batchSize, long finalSequence, Args[] args) shared
    {
        auto initial = finalSequence - (batchSize - 1);
        auto seq = initial;
        try
        {
            foreach (i; batchStartsAt .. batchStartsAt + batchSize)
            {
                translator.translateTo(cast(T)get(seq), seq, args[i]);
                ++seq;
            }
        }
        finally
        {
            sequencer.publish(initial, finalSequence);
        }
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
    (cast(StubEvent) evt).value = 42;
    rb.publish(seq);

    assert(rb.get(seq).value == 42);

    auto g1 = new shared Sequence();
    auto g2 = new shared Sequence();
    rb.addGatingSequences(g1, g2);
    assert(rb.removeGatingSequence(g1));
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;

    class StubEvent
    {
        long value;
    }

    auto rb = RingBuffer!StubEvent.createSingleProducer(() => new shared StubEvent(), 8, new shared BlockingWaitStrategy());

    assert(rb.getCursor() == -1);

    auto ev = rb.claimAndGetPreallocated(0);
    assert(rb.getCursor() == -1);

    (cast(StubEvent)ev).value = 7;
    rb.publish(0);

    assert(rb.getCursor() == 0);
    assert(rb.get(0).value == 7);
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;

    class StubEvent
    {
        long value;
    }

    class MyTranslator : EventTranslator!StubEvent
    {
        override void translateTo(StubEvent event, long sequence)
        {
            event.value = sequence + 29;
        }
    }

    auto rb = RingBuffer!StubEvent.createMultiProducer(() => new shared StubEvent(), 32, new shared BlockingWaitStrategy());
    rb.addGatingSequences(new shared Sequence());

    auto t = new MyTranslator();
    rb.publishEvent(t);
    rb.publishEvent(t);

    assert(rb.get(0).value == 0 + 29);
    assert(rb.get(1).value == 1 + 29);

    auto rb2 = RingBuffer!StubEvent.createMultiProducer(() => new shared StubEvent(), 4, new shared BlockingWaitStrategy());
    rb2.addGatingSequences(new shared Sequence());

    foreach (i; 0 .. 4)
        assert(rb2.tryPublishEvent(t));

    foreach (i; 0 .. 4)
        assert(rb2.get(i).value == i + 29);

    assert(!rb2.tryPublishEvent(t));
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import disruptor.producertype : ProducerType;

    class StubEvent
    {
        long value;
    }

    auto factory = () => new shared StubEvent();
    auto ws = new shared BlockingWaitStrategy();

    auto single = RingBuffer!StubEvent.create(ProducerType.SINGLE, factory, 4, ws);
    auto seq = single.next();
    (cast(StubEvent)single.get(seq)).value = 3;
    single.publish(seq);
    assert(single.get(seq).value == 3);

    auto multi = RingBuffer!StubEvent.create(ProducerType.MULTI, factory, 8, ws);
    seq = multi.next();
    (cast(StubEvent)multi.get(seq)).value = 5;
    multi.publish(seq);
    assert(multi.get(seq).value == 5);
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import std.exception : assertThrown;

    class StubEvent
    {
        long value;
    }

    auto factory = () => new shared StubEvent();
    auto ws = new shared BlockingWaitStrategy();

    assertThrown!Exception(RingBuffer!StubEvent.createSingleProducer(factory, 0, ws));
    assertThrown!Exception(RingBuffer!StubEvent.createSingleProducer(factory, 3, ws));
    assertThrown!Exception(RingBuffer!StubEvent.createMultiProducer(factory, 0, ws));
    assertThrown!Exception(RingBuffer!StubEvent.createMultiProducer(factory, 3, ws));
}

