module disruptor.eventpoller;

import disruptor.sequence : Sequence;
import disruptor.sequencer : DataProvider, Sequencer;
import disruptor.fixedsequencegroup : FixedSequenceGroup;

/// A callback used to process events.
interface Handler(T)
{
    /// Called for each event to consume it.
    bool onEvent(T event, long sequence, bool endOfBatch);
}

/// Indicates the result of a poll operation.
enum PollState
{
    /// The poller processed one or more events.
    PROCESSING,
    /// The poller is waiting for gated sequences to advance before events are available.
    GATING,
    /// No events were available to process.
    IDLE
}

/// Experimental poll-based interface for the Disruptor.
class EventPoller(T)
{
private:
    shared DataProvider!T dataProvider;
    shared Sequencer sequencer;
    shared Sequence sequence;
    shared Sequence gatingSequence;

public:
    this(shared DataProvider!T dataProvider,
         shared Sequencer sequencer,
         shared Sequence sequence,
         shared Sequence gatingSequence)
    {
        this.dataProvider = dataProvider;
        this.sequencer = sequencer;
        this.sequence = sequence;
        this.gatingSequence = gatingSequence;
    }

    this(shared DataProvider!T dataProvider,
         shared Sequencer sequencer,
         shared Sequence sequence,
         shared Sequence gatingSequence) shared
    {
        this.dataProvider = dataProvider;
        this.sequencer = sequencer;
        this.sequence = sequence;
        this.gatingSequence = gatingSequence;
    }

    PollState poll(Handler!T eventHandler) shared
    {
        long currentSequence = sequence.get();
        long nextSequence = currentSequence + 1;
        long availableSequence =
            sequencer.getHighestPublishedSequence(nextSequence, gatingSequence.get());

        if (nextSequence <= availableSequence)
        {
            bool processNextEvent;
            long processedSequence = currentSequence;

            try
            {
                do
                {
                    auto event = dataProvider.get(nextSequence);
                    processNextEvent = eventHandler.onEvent(cast(T)event,
                        nextSequence,
                        nextSequence == availableSequence);
                    processedSequence = nextSequence;
                    ++nextSequence;
                }
                while (nextSequence <= availableSequence && processNextEvent);
            }
            finally
            {
                sequence.set(processedSequence);
            }

            return PollState.PROCESSING;
        }
        else if (sequencer.getCursor() >= nextSequence)
        {
            return PollState.GATING;
        }
        else
        {
            return PollState.IDLE;
        }
    }

    static shared(EventPoller!T) newInstance(shared DataProvider!T dataProvider,
                                            shared Sequencer sequencer,
                                            shared Sequence sequence,
                                            shared Sequence cursorSequence,
                                            shared Sequence[] gatingSequences = [])
    {
        shared Sequence gate;
        if (gatingSequences.length == 0)
        {
            gate = cursorSequence;
        }
        else if (gatingSequences.length == 1)
        {
            gate = gatingSequences[0];
        }
        else
        {
            gate = new shared FixedSequenceGroup(gatingSequences);
        }

        return new shared EventPoller!T(dataProvider, sequencer, sequence, gate);
    }

    shared(Sequence) getSequence() shared
    {
        return sequence;
    }
}

unittest
{
    import disruptor.waitstrategy : BusySpinWaitStrategy, SleepingWaitStrategy;
    import disruptor.singleproducersequencer : SingleProducerSequencer;
    import disruptor.ringbuffer : RingBuffer;

    // Test polling directly from a sequencer
    {
        auto gatingSequence = new shared Sequence();
        auto sequencer = new shared SingleProducerSequencer(16, new shared BusySpinWaitStrategy());
        class TestHandler : Handler!Object
        {
            override bool onEvent(Object event, long seq, bool endOfBatch)
            {
                return false;
            }
        }
        auto handler = new TestHandler();

        shared Object[] data = new shared Object[](16);
        class Provider : DataProvider!Object
        {
            shared Object[] arr;
            this(shared Object[] arr) shared { this.arr = arr; }
            override shared(Object) get(long sequence) shared { return arr[cast(size_t)sequence]; }
        }
        auto provider = new shared Provider(data);

        auto poller = sequencer.newPoller!Object(provider, gatingSequence);
        auto obj = new Object();
        data[0] = cast(shared Object) obj;

        assert(poller.poll(handler) == PollState.IDLE);

        auto seq = sequencer.next();
        sequencer.publish(seq);
        assert(poller.poll(handler) == PollState.GATING);

        gatingSequence.incrementAndGet();
        assert(poller.poll(handler) == PollState.PROCESSING);
    }

    // Test polling from a ring buffer when full
    {
        import disruptor.eventfactory : EventFactory;

        byte[][] events;
        class ByteHandler : Handler!(byte[])
        {
            override bool onEvent(byte[] evt, long seq, bool endOfBatch)
            {
                events ~= evt.dup;
                return !endOfBatch;
            }
        }
        auto handler = new ByteHandler();

        auto ringBuffer = RingBuffer!(byte[]).createMultiProducer({ return new shared byte[](1); }, 4, new shared SleepingWaitStrategy());
        auto poller = ringBuffer.newPoller();
        ringBuffer.addGatingSequences(poller.getSequence());

        foreach (byte i; 1 .. 5)
        {
            auto n = ringBuffer.next();
            auto arr = cast(byte[]) ringBuffer.get(n);
            arr[0] = i;
            ringBuffer.publish(n);
        }

        poller.poll(handler);
        assert(events.length == 4);
    }
}

