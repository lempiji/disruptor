module disruptor.eventprocessorinfo;

import std.conv : text;
import core.thread : Thread;
import disruptor.eventprocessor : EventProcessor;
import disruptor.sequence : Sequence;
import disruptor.sequencer : SequenceBarrier;
import disruptor.consumerinfo : ConsumerInfo, ThreadFactory;

/// Wrapper tying an `EventProcessor` to its `SequenceBarrier`.
class EventProcessorInfo : ConsumerInfo
{
private:
    shared(EventProcessor) _eventProcessor;
    shared SequenceBarrier _barrier;
    shared bool _endOfChain = true;

public:
    this(shared EventProcessor eventProcessor, shared SequenceBarrier barrier) shared @safe nothrow
    {
        _eventProcessor = eventProcessor;
        _barrier = barrier;
    }

    shared(EventProcessor) getEventProcessor() shared @safe nothrow
    {
        return _eventProcessor;
    }

    override shared(Sequence)[] getSequences() shared
    {
        return [_eventProcessor.getSequence()];
    }

    override shared(SequenceBarrier) getBarrier() shared
    {
        return _barrier;
    }

    override bool isEndOfChain() shared
    {
        return _endOfChain;
    }

    override void start(shared ThreadFactory threadFactory) shared
    {
        auto thread = threadFactory.newThread({ _eventProcessor.run(); });
        if (thread is null)
            throw new Exception("Failed to create thread to run", __FILE__, __LINE__);
        thread.start();
    }

    override void halt() shared
    {
        _eventProcessor.halt();
    }

    override void markAsUsedInBarrier() shared
    {
        _endOfChain = false;
    }

    override bool isRunning() shared
    {
        return _eventProcessor.isRunning();
    }
}

