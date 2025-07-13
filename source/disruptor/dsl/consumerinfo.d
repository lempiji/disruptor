module disruptor.dsl.consumerinfo;

import disruptor.sequence : Sequence;
import disruptor.sequencer : SequenceBarrier;
import disruptor.threadfactory : ThreadFactory;

/// Metadata interface for components consuming events from a RingBuffer.
interface ConsumerInfo
{
    /// Sequences tracked by this consumer.
    shared(Sequence)[] getSequences() shared;

    /// The barrier this consumer is waiting on, if any.
    shared(SequenceBarrier) getBarrier() shared;

    /// Whether this consumer is currently at the end of the dependency chain.
    bool isEndOfChain() shared;

    /// Start processing using a thread from the given factory.
    void start(ThreadFactory threadFactory) shared;

    /// Signal the consumer to halt when safe.
    void halt() shared;

    /// Mark this consumer as part of a barrier dependency chain.
    void markAsUsedInBarrier() shared;

    /// Whether the consumer is currently running.
    bool isRunning() shared;
}
