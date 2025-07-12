module disruptor.eventhandler;

public import disruptor.sequence : Sequence;

/// Marker interface to allow identification of Disruptor event handlers.
interface EventHandlerIdentity
{
}

/// Base interface for handling events from the RingBuffer.
interface EventHandlerBase(T) : EventHandlerIdentity
{
    /// Called when a publisher has published an event.
    void onEvent(shared(T) event, long sequence, bool endOfBatch) shared;

    /// Invoked by a BatchEventProcessor prior to processing a batch of events.
    void onBatchStart(long batchSize, long queueDepth) shared;

    /// Called once on thread start before first event is available.
    void onStart() shared;

    /// Called once just before the event processing thread is shutdown.
    void onShutdown() shared;

    /// Invoked when a WaitStrategy times out waiting for an event.
    void onTimeout(long sequence) shared;
}

/// Extended interface used by EventProcessors to notify of sequence progress.
interface EventHandler(T) : EventHandlerBase!T
{
    /// Set a callback sequence to notify when events have been processed.
    void setSequenceCallback(shared Sequence sequenceCallback) shared;
}

/// Convenience base class providing default no-op implementations for the
/// optional lifecycle callbacks.
abstract class EventHandlerAdapter(T) : EventHandler!T
{
    override void onBatchStart(long batchSize, long queueDepth) shared {}
    override void onStart() shared {}
    override void onShutdown() shared {}
    override void onTimeout(long sequence) shared {}
    override void setSequenceCallback(shared Sequence sequenceCallback) shared {}
}

unittest
{
    class MyEvent { int value; }

    class MyHandler : EventHandlerAdapter!MyEvent
    {
        override void onEvent(shared(MyEvent) event, long sequence, bool endOfBatch) shared
        {
            event.value = cast(int)sequence;
        }
    }

    static assert(is(MyHandler : EventHandler!MyEvent));

    auto handler = new shared MyHandler();
    handler.onStart();
    handler.onBatchStart(1, 1);
    handler.onTimeout(0);
    handler.onShutdown();
    handler.onEvent(new shared MyEvent(), 1, true);
}
