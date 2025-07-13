module disruptor.rewindbatcheventprocessor;

import disruptor.batcheventprocessor : BatchEventProcessor;
import disruptor.batchrewindstrategy : BatchRewindStrategy;
import disruptor.simplebatchrewindstrategy : SimpleBatchRewindStrategy;
import disruptor.rewindableeventhandler : RewindableEventHandler;
import core.atomic : atomicOp;
import disruptor.sequencer : DataProvider, SequenceBarrier;
import disruptor.sequence : Sequence;
import disruptor.ringbuffer : RingBuffer; // for unittests
import disruptor.rewindableexception : RewindableException;
import disruptor.rewindaction : RewindAction;

/// Processor specialised for use with a `RewindableEventHandler`.
class RewindBatchEventProcessor(T) : BatchEventProcessor!T
{
    this(shared DataProvider!T dataProvider,
         shared SequenceBarrier sequenceBarrier,
         shared RewindableEventHandler!T eventHandler,
         int maxBatchSize,
         shared BatchRewindStrategy rewindStrategy = null) shared
    {
        super(dataProvider,
              sequenceBarrier,
              eventHandler,
              maxBatchSize,
              rewindStrategy is null ? new shared SimpleBatchRewindStrategy() : rewindStrategy);
    }

    /// Create a new shared RewindBatchEventProcessor instance.
    static shared(RewindBatchEventProcessor!T) newInstance(shared DataProvider!T dataProvider,
                                                          shared SequenceBarrier sequenceBarrier,
                                                          shared RewindableEventHandler!T eventHandler,
                                                          int maxBatchSize,
                                                          shared BatchRewindStrategy rewindStrategy = null)
    {
        return new shared RewindBatchEventProcessor!T(dataProvider,
                                                     sequenceBarrier,
                                                     eventHandler,
                                                     maxBatchSize,
                                                     rewindStrategy);
    }
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import core.thread : Thread;
    import core.time : msecs;
    import disruptor.eventfactory : makeEventFactory;

    class LongEvent { long value; }

    class TestHandler : RewindableEventHandler!LongEvent
    {
        this(long rewindSequence, long timesToRewind, long exitSequence) shared
        {
            this.rewindSequence = rewindSequence;
            this.timesToRewind = timesToRewind;
            this.exitSequence = exitSequence;
        }

        RewindBatchEventProcessor!LongEvent processor;
        long rewindSequence;
        long timesToRewind;
        long exitSequence;
        long rewound;
        long[] processed;

        override void onEvent(LongEvent evt, long seq, bool endOfBatch) shared
        {
            if (seq == rewindSequence && rewound < timesToRewind)
            {
                atomicOp!"+="(rewound, 1);
                throw new RewindableException();
            }
            (cast(TestHandler)this).processed ~= seq;
            if (seq == exitSequence)
            {
                processor.halt();
            }
        }
    }

    auto rb = RingBuffer!LongEvent.createSingleProducer(
        makeEventFactory!LongEvent(() => new shared LongEvent()),
        4,
        new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto handler = new shared TestHandler(0, 1, 0);
    auto processor = RewindBatchEventProcessor!LongEvent.newInstance(rb,
                                                                    barrier,
                                                                    handler,
                                                                    16,
                                                                    new shared SimpleBatchRewindStrategy());
    handler.processor = processor;
    rb.addGatingSequences(processor.getSequence());
    rb.publish(rb.next());

    auto t = new Thread({ processor.run(); });
    t.start();
    t.join();

    auto h = cast(TestHandler)handler;
    assert(h.rewound == 1);
    assert(h.processed == [0L]);
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import core.thread : Thread;
    import core.time : msecs;
    import disruptor.eventfactory : makeEventFactory;

    class LongEvent { long value; }

    class MidRewindHandler : RewindableEventHandler!LongEvent
    {
        this(long rewindSequence, long exitSequence) shared
        {
            this.rewindSequence = rewindSequence;
            this.exitSequence = exitSequence;
        }

        RewindBatchEventProcessor!LongEvent processor;
        long rewindSequence;
        long exitSequence;
        long rewound;
        long[] processed;

        override void onEvent(LongEvent evt, long seq, bool endOfBatch) shared
        {
            if (seq == rewindSequence && rewound == 0)
            {
                atomicOp!"+="(rewound, 1);
                throw new RewindableException();
            }
            (cast(MidRewindHandler)this).processed ~= seq;
            if (seq == exitSequence)
            {
                processor.halt();
            }
        }
    }

    enum ENTRIES = 10;
    auto rb = RingBuffer!LongEvent.createSingleProducer(
        makeEventFactory!LongEvent(() => new shared LongEvent()),
        16,
        new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto handler = new shared MidRewindHandler(2, ENTRIES - 1);
    auto processor = RewindBatchEventProcessor!LongEvent.newInstance(rb,
                                                                    barrier,
                                                                    handler,
                                                                    16,
                                                                    new shared SimpleBatchRewindStrategy());
    handler.processor = processor;
    rb.addGatingSequences(processor.getSequence());

    foreach(i; 0 .. ENTRIES)
        rb.publish(rb.next());

    auto t = new Thread({ processor.run(); });
    t.start();
    t.join();

    auto h = cast(MidRewindHandler)handler;
    assert(h.rewound == 1);
    assert(h.processed == [0L, 1L, 0L, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L, 9L]);
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import core.thread : Thread;
    import core.time : msecs;
    import disruptor.eventfactory : makeEventFactory;

    class LongEvent { long value; }

    class CountingStrategy : BatchRewindStrategy
    {
        int count;
        override RewindAction handleRewindException(RewindableException e, int attempts) shared
        {
            atomicOp!"+="(count, 1);
            return RewindAction.REWIND;
        }
    }

    class MultiRewindHandler : RewindableEventHandler!LongEvent
    {
        this(long rewindSequence, long timesToRewind, long exitSequence) shared
        {
            this.rewindSequence = rewindSequence;
            this.timesToRewind = timesToRewind;
            this.exitSequence = exitSequence;
        }

        RewindBatchEventProcessor!LongEvent processor;
        long rewindSequence;
        long timesToRewind;
        long exitSequence;
        long rewound;
        long[] processed;

        override void onEvent(LongEvent evt, long seq, bool endOfBatch) shared
        {
            if (seq == rewindSequence && rewound < timesToRewind)
            {
                atomicOp!"+="(rewound, 1);
                throw new RewindableException();
            }
            (cast(MultiRewindHandler)this).processed ~= seq;
            if (seq == exitSequence)
            {
                processor.halt();
            }
        }
    }

    enum ENTRIES = 6;
    auto rb = RingBuffer!LongEvent.createSingleProducer(
        makeEventFactory!LongEvent(() => new shared LongEvent()),
        16,
        new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto strategy = new shared CountingStrategy();
    auto handler = new shared MultiRewindHandler(4, 3, ENTRIES - 1);
    auto processor = RewindBatchEventProcessor!LongEvent.newInstance(rb,
                                                                    barrier,
                                                                    handler,
                                                                    16,
                                                                    strategy);
    handler.processor = processor;
    rb.addGatingSequences(processor.getSequence());

    foreach(i; 0 .. ENTRIES)
        rb.publish(rb.next());

    auto t = new Thread({ processor.run(); });
    t.start();
    t.join();

    auto h = cast(MultiRewindHandler)handler;
    assert(strategy.count == 3);
    assert(h.rewound == 3);
    assert(h.processed[$-1] == ENTRIES - 1);
}

