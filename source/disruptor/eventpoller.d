module disruptor.eventpoller;

import disruptor.sequence : Sequence;
import disruptor.fixedsequencegroup : FixedSequenceGroup;
import disruptor.sequencer : DataProvider, Sequencer;

/**
 * Experimental poll-based interface similar to the Java version.
 */
class EventPoller(T)
{
    private shared(DataProvider!T) _dataProvider;
    private shared Sequencer _sequencer;
    private shared Sequence _sequence;
    private shared Sequence _gatingSequence;

    /// Callback used to consume events from the poller.
    interface Handler
    {
        bool onEvent(shared(T) event, long sequence, bool endOfBatch);
    }

    /// Result of a poll attempt.
    enum PollState
    {
        PROCESSING,
        GATING,
        IDLE
    }

    this(shared DataProvider!T dataProvider, shared Sequencer sequencer,
            shared Sequence sequence, shared Sequence gatingSequence)
    {
        _dataProvider = dataProvider;
        _sequencer = sequencer;
        _sequence = sequence;
        _gatingSequence = gatingSequence;
    }

    this(shared DataProvider!T dataProvider, shared Sequencer sequencer,
            shared Sequence sequence, shared Sequence gatingSequence) shared
    {
        _dataProvider = dataProvider;
        _sequencer = sequencer;
        _sequence = sequence;
        _gatingSequence = gatingSequence;
    }

    /// Poll for events using the supplied handler.
    PollState poll(Handler handler) shared
    {
        auto currentSequence = _sequence.get();
        auto nextSequence = currentSequence + 1;
        auto availableSequence =
            _sequencer.getHighestPublishedSequence(nextSequence, _gatingSequence.get());

        if (nextSequence <= availableSequence)
        {
            bool processNext;
            long processedSequence = currentSequence;
            try
            {
                do
                {
                    auto evt = _dataProvider.get(nextSequence);
                    processNext = handler.onEvent(evt, nextSequence, nextSequence == availableSequence);
                    processedSequence = nextSequence;
                    nextSequence++;
                }
                while (nextSequence <= availableSequence && processNext);
            }
            finally
            {
                _sequence.set(processedSequence);
            }
            return PollState.PROCESSING;
        }
        else if (_sequencer.getCursor() >= nextSequence)
        {
            return PollState.GATING;
        }
        else
        {
            return PollState.IDLE;
        }
    }

    /// Create a new EventPoller instance gating on the supplied sequences.
    static shared(EventPoller!T) newInstance(T)(shared DataProvider!T dataProvider,
            shared Sequencer sequencer, shared Sequence sequence,
            shared Sequence cursorSequence, shared Sequence[] gatingSequences...)
    {
        shared Sequence gating;
        if (gatingSequences.length == 0)
        {
            gating = cursorSequence;
        }
        else if (gatingSequences.length == 1)
        {
            gating = gatingSequences[0];
        }
        else
        {
            gating = new shared FixedSequenceGroup(gatingSequences);
        }
        return new shared EventPoller!T(dataProvider, sequencer, sequence, gating);
    }

    /// Get the sequence tracked by this poller.
    shared(Sequence) getSequence() shared
    {
        return _sequence;
    }
}

unittest
{
    import disruptor.singleproducersequencer : SingleProducerSequencer;
    import disruptor.waitstrategy : BusySpinWaitStrategy;

    shared int[] data = new shared int[](16);

    class IntProvider : DataProvider!int
    {
        override shared(int) get(long seq) shared { return data[cast(size_t) seq]; }
    }

    auto sequencer = new shared SingleProducerSequencer(16, new shared BusySpinWaitStrategy());
    auto gating = new shared Sequence();
    auto provider = new shared IntProvider();
    auto poller = sequencer.newPoller(provider, gating);

    class H : EventPoller!int.Handler
    {
        int count;
        override bool onEvent(shared(int) evt, long seq, bool end) { ++count; return false; }
    }

    auto h = new H();

    // Initially idle
    assert(poller.poll(h) == EventPoller!int.PollState.IDLE);

    // publish one event
    auto next = sequencer.next();
    data[next] = 7;
    sequencer.publish(next);

    // gating not advanced yet
    assert(poller.poll(h) == EventPoller!int.PollState.GATING);
    assert(h.count == 0);

    gating.incrementAndGet();
    assert(poller.poll(h) == EventPoller!int.PollState.PROCESSING);
    assert(h.count == 1);
    assert(poller.getSequence().get() == next);
}

