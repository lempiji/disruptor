module disruptor.batcheventprocessorbuilder;

import disruptor.batcheventprocessor : BatchEventProcessor;
import disruptor.eventhandler : EventHandler, EventHandlerBase;
import disruptor.rewindableeventhandler : RewindableEventHandler;
import disruptor.batchrewindstrategy : BatchRewindStrategy;
import disruptor.sequencer : DataProvider, SequenceBarrier;
import disruptor.sequence : Sequence;
import disruptor.ringbuffer : RingBuffer;
import disruptor.simplebatchrewindstrategy : SimpleBatchRewindStrategy;
import disruptor.rewindableexception : RewindableException;

/// Builder for configuring and creating a `BatchEventProcessor`.
class BatchEventProcessorBuilder
{
private:
    int _maxBatchSize = int.max;

public:
    /// Set the maximum number of events that will be processed in a batch before updating the sequence.
    BatchEventProcessorBuilder setMaxBatchSize(int maxBatchSize) @safe nothrow @nogc
    {
        _maxBatchSize = maxBatchSize;
        return this;
    }

    /// Construct a `BatchEventProcessor` without batch rewind support.
    shared(BatchEventProcessor!T) build(T)(
            shared DataProvider!T dataProvider,
            shared SequenceBarrier sequenceBarrier,
            shared EventHandler!T eventHandler)
    {
        auto processor = BatchEventProcessor!T.newInstance(
                dataProvider,
                sequenceBarrier,
                eventHandler,
                _maxBatchSize);
        eventHandler.setSequenceCallback(processor.getSequence());
        return processor;
    }

    /// Construct a `BatchEventProcessor` with batch rewind support.
    shared(BatchEventProcessor!T) build(T)(
            shared DataProvider!T dataProvider,
            shared SequenceBarrier sequenceBarrier,
            shared RewindableEventHandler!T rewindableEventHandler,
            shared BatchRewindStrategy batchRewindStrategy)
    {
        if (batchRewindStrategy is null)
        {
            throw new Exception("batchRewindStrategy cannot be null when building a BatchEventProcessor", __FILE__, __LINE__);
        }
        return BatchEventProcessor!T.newInstance(
                dataProvider,
                sequenceBarrier,
                rewindableEventHandler,
                _maxBatchSize,
                batchRewindStrategy);
    }
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import core.thread : Thread;
    import core.time : msecs;
    import disruptor.eventfactory : makeEventFactory;

    enum MAX_BATCH_SIZE = 3;
    enum PUBLISH_COUNT = 5;

    class StubEvent { int value; }

    class BatchLimitRecordingHandler : EventHandler!StubEvent
    {
        this() shared {}
        long[][] batchedSequences;
        long[] announcedBatchSizes;
        long[] announcedQueueDepths;
        long[] current;

        override void onEvent(StubEvent evt, long seq, bool endOfBatch) shared
        {
            current ~= seq;
            if (endOfBatch)
            {
                batchedSequences ~= current;
                current = null;
            }
        }

        override void onBatchStart(long batchSize, long queueDepth) shared @safe nothrow
        {
            current = [];
            announcedBatchSizes ~= batchSize;
            announcedQueueDepths ~= queueDepth;
        }
    }

    auto rb = RingBuffer!StubEvent.createSingleProducer(
        makeEventFactory!StubEvent(() => new shared StubEvent()),
        16,
        new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto handler = new shared BatchLimitRecordingHandler();
    auto processor = (new BatchEventProcessorBuilder())
            .setMaxBatchSize(MAX_BATCH_SIZE)
            .build(cast(shared DataProvider!StubEvent)rb,
                   barrier,
                   handler);
    rb.addGatingSequences(processor.getSequence());

    foreach(i; 0 .. PUBLISH_COUNT)
        rb.publish(rb.next());

    auto t = new Thread({ processor.run(); });
    t.start();
    Thread.sleep(100.msecs);
    processor.halt();
    t.join();

    auto h = cast(BatchLimitRecordingHandler)handler;
    assert(h.batchedSequences.length == 2);
    assert(h.batchedSequences[0] == [0L, 1L, 2L]);
    assert(h.batchedSequences[1] == [3L, 4L]);
    assert(h.announcedBatchSizes == [3L, 2L]);
    assert(h.announcedQueueDepths == [5L, 2L]);
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import core.thread : Thread;
    import disruptor.eventfactory : makeEventFactory;

    class StubEvent { int value; }

    class RewindingHandler : RewindableEventHandler!StubEvent
    {
        this() shared {}
        shared BatchEventProcessor!StubEvent processor;
        shared int calls;

        override void onEvent(StubEvent evt, long seq, bool endOfBatch) shared
        {
            import core.atomic : atomicOp;
            if (atomicOp!"+="(calls, 1) == 1)
                throw new RewindableException();
            processor.halt();
        }
    }

    auto rb = RingBuffer!StubEvent.createSingleProducer(
        makeEventFactory!StubEvent(() => new shared StubEvent()),
        4,
        new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto handler = new shared RewindingHandler();
    auto processor = (new BatchEventProcessorBuilder())
            .build(cast(shared DataProvider!StubEvent)rb,
                   barrier,
                   handler,
                   new shared SimpleBatchRewindStrategy());
    handler.processor = processor;
    rb.addGatingSequences(processor.getSequence());
    rb.publish(rb.next());

    auto t = new Thread({ processor.run(); });
    t.start();
    t.join();

    assert(handler.calls == 2);
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import disruptor.eventfactory : makeEventFactory;

    class StubEvent { int value; }

    class DummyHandler : RewindableEventHandler!StubEvent
    {
        override void onEvent(StubEvent evt, long seq, bool endOfBatch) shared {}
    }

    auto rb = RingBuffer!StubEvent.createSingleProducer(
        makeEventFactory!StubEvent(() => new shared StubEvent()),
        4,
        new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto handler = new shared DummyHandler();
    auto builder = new BatchEventProcessorBuilder();
    bool threw = false;
    try
    {
        auto p = builder.build(cast(shared DataProvider!StubEvent)rb,
                               barrier,
                               handler,
                               null);
    }
    catch (Exception)
    {
        threw = true;
    }
    assert(threw);
}

