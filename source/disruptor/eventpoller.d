module disruptor.eventpoller;

import disruptor.sequencer : Sequencer, DataProvider;
import disruptor.sequence : Sequence;
import disruptor.fixedsequencegroup : FixedSequenceGroup;

/// Experimental poll-based processor for events.
class EventPoller(T)
{
private:
    shared DataProvider!T _dataProvider;
    shared Sequencer _sequencer;
    shared Sequence _sequence;
    shared Sequence _gatingSequence;

public:
    /// Callback for consuming events.
    interface Handler(T)
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

    this(shared DataProvider!T dataProvider,
         shared Sequencer sequencer,
         shared Sequence sequence,
         shared Sequence gatingSequence) shared
    {
        _dataProvider = dataProvider;
        _sequencer = sequencer;
        _sequence = sequence;
        _gatingSequence = gatingSequence;
    }

    PollState poll(Handler!T eventHandler) shared
    {
        long currentSequence = _sequence.get();
        long nextSequence = currentSequence + 1;
        long availableSequence =
            _sequencer.getHighestPublishedSequence(nextSequence, _gatingSequence.get());

        if (nextSequence <= availableSequence)
        {
            bool processNextEvent;
            long processedSequence = currentSequence;

            try
            {
                do
                {
                    auto event = _dataProvider.get(nextSequence);
                    processNextEvent = eventHandler.onEvent(event, nextSequence,
                        nextSequence == availableSequence);
                    processedSequence = nextSequence;
                    nextSequence++;
                }
                while (nextSequence <= availableSequence && processNextEvent);
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

    static shared(EventPoller!T) newInstance(T)(shared DataProvider!T dataProvider,
                                                shared Sequencer sequencer,
                                                shared Sequence sequence,
                                                shared Sequence cursorSequence,
                                                shared Sequence[] gatingSequences = [])
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

        return new shared EventPoller!T(dataProvider, sequencer, sequence, gatingSequence);
    }

    shared(Sequence) getSequence() shared
    {
        return _sequence;
    }
}

