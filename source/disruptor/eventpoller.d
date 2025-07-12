module disruptor.eventpoller;

import disruptor.sequence : Sequence;
import disruptor.sequencer : Sequencer, DataProvider;
import disruptor.fixedsequencegroup : FixedSequenceGroup;

/// Experimental poll-based interface for the Disruptor.
class EventPoller(T)
{
    /// Callback used to process events.
    interface Handler
    {
        /// Called for each available event.
        bool onEvent(shared(T) event, long sequence, bool endOfBatch);
    }

    /// Result of a poll operation.
    enum PollState
    {
        PROCESSING,
        GATING,
        IDLE
    }

private:
    shared DataProvider!T dataProvider;
    shared Sequencer sequencer;
    shared Sequence sequence;
    shared Sequence gatingSequence;

public:
    this(shared DataProvider!T dataProvider, shared Sequencer sequencer,
            shared Sequence sequence, shared Sequence gatingSequence)
    {
        this.dataProvider = dataProvider;
        this.sequencer = sequencer;
        this.sequence = sequence;
        this.gatingSequence = gatingSequence;
    }

    /// Poll for events using the supplied handler.
    PollState poll(Handler eventHandler)
    {
        long currentSequence = sequence.get();
        long nextSequence = currentSequence + 1;
        long availableSequence =
            sequencer.getHighestPublishedSequence(nextSequence,
                gatingSequence.get());

        if (nextSequence <= availableSequence)
        {
            bool processNextEvent;
            long processedSequence = currentSequence;
            try
            {
                do
                {
                    auto event = dataProvider.get(nextSequence);
                    processNextEvent =
                        eventHandler.onEvent(event, nextSequence,
                            nextSequence == availableSequence);
                    processedSequence = nextSequence;
                    nextSequence++;
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

    /// Create an EventPoller instance.
    static EventPoller!T newInstance(shared DataProvider!T dataProvider,
            shared Sequencer sequencer, shared Sequence sequence,
            shared Sequence cursorSequence,
            shared Sequence[] gatingSequences...)
    {
        shared Sequence gatingSequence;
        if (gatingSequences.length == 0)
        {
            gatingSequence = cursorSequence;
        }
        else if (gatingSequences.length == 1)
        {
            gatingSequence = gatingSequences[0];
        }
        else
        {
            gatingSequence = new shared FixedSequenceGroup(gatingSequences);
        }
        return new EventPoller!T(dataProvider, sequencer, sequence, gatingSequence);
    }

    /// Get the sequence used by this poller.
    shared(Sequence) getSequence()
    {
        return sequence;
    }
}

unittest
{
    import disruptor.singleproducersequencer : SingleProducerSequencer;
    import disruptor.waitstrategy : BusySpinWaitStrategy, SleepingWaitStrategy;
    import disruptor.ringbuffer : RingBuffer;
    import disruptor.sequence : Sequence;

    // Test similar to EventPollerTest.shouldPollForEvents
    {
        auto gating = new shared Sequence();
        auto sequencer = new shared SingleProducerSequencer(16, new shared BusySpinWaitStrategy());

        class ArrayProvider : DataProvider!Object
        {
            shared Object[] data;
            this(shared Object[] data) shared { this.data = data; }
            override shared(Object) get(long sequence) shared { return data[cast(size_t)sequence]; }
        }

        auto store = new shared Object[](16);
        auto provider = new shared ArrayProvider(store);
        auto poller = sequencer.newPoller!(Object)(provider, gating);
        auto evt = new shared Object();
        store[0] = evt;
        class DummyHandler : EventPoller!(Object).Handler
        {
            override bool onEvent(shared Object e, long s, bool endOfBatch) { return false; }
        }
        auto handler = new DummyHandler();

        assert(poller.poll(handler) == EventPoller!(Object).PollState.IDLE);

        long seq = sequencer.next();
        sequencer.publish(seq);
        assert(poller.poll(handler) == EventPoller!(Object).PollState.GATING);

        gating.incrementAndGet();
        assert(poller.poll(handler) == EventPoller!(Object).PollState.PROCESSING);
    }

    // Test similar to EventPollerTest.shouldSuccessfullyPollWhenBufferIsFull
    {
        byte[][] events;
        class ByteHandler : EventPoller!(byte[]).Handler
        {
            override bool onEvent(shared(byte[]) event, long sequence, bool endOfBatch)
            {
                events ~= cast(byte[])event[0 .. $];
                return !endOfBatch;
            }
        }
        auto handler = new ByteHandler();

        auto rb = RingBuffer!(byte[]).createMultiProducer(() => new shared byte[](1), 4,
                new shared SleepingWaitStrategy());
        auto poller = rb.newPoller();
        rb.addGatingSequences(poller.getSequence());

        foreach (byte i; 1 .. 5)
        {
            long n = rb.next();
            rb.get(n)[0] = i;
            rb.publish(n);
        }

        poller.poll(handler);
        assert(events.length == 4);
    }
}

