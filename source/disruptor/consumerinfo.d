module disruptor.consumerinfo;

import disruptor.sequence : Sequence;
import disruptor.sequencer : SequenceBarrier;
import core.thread : Thread;

alias Runnable = void delegate();

/// Interface for creating threads.
interface ThreadFactory
{
    Thread newThread(Runnable r) shared;
}

/// Interface describing a consumer of events.
interface ConsumerInfo
{
    shared(Sequence)[] getSequences() shared;
    shared(SequenceBarrier) getBarrier() shared;
    bool isEndOfChain() shared;
    void start(shared ThreadFactory threadFactory) shared;
    void halt() shared;
    void markAsUsedInBarrier() shared;
    bool isRunning() shared;
}

