module disruptor.eventhandler;

import disruptor.sequence : Sequence;

/// Marker interface for identifying event handlers.
interface EventHandlerIdentity
{
}

/// Base class for event handlers providing default no-op methods.
abstract class EventHandlerBase(T) : EventHandlerIdentity
{
    /// Called when a publisher has published an event.
    abstract void onEvent(T event, long sequence, bool endOfBatch) shared;

    /// Invoked by a BatchEventProcessor prior to processing a batch of events.
    void onBatchStart(long batchSize, long queueDepth) shared @safe nothrow
    {
    }

    /// Called once on thread start before first event is available.
    void onStart() shared @safe nothrow
    {
    }

    /// Called once just before the event processing thread is shutdown.
    void onShutdown() shared @safe nothrow
    {
    }

    /// Invoked when a WaitStrategy times out.
    void onTimeout(long sequence) shared @safe nothrow
    {
    }
}

/// Event handler implementation with optional sequence callback.
abstract class EventHandler(T) : EventHandlerBase!T
{
    /// Called when a publisher has published an event.
    override abstract void onEvent(T event, long sequence, bool endOfBatch) shared;

    /// Callback allowing the handler to notify when it has finished consuming an event.
    void setSequenceCallback(shared Sequence sequenceCallback) shared @safe nothrow
    {
    }
}

unittest
{
    class MyEvent { int value; }

    class MyHandler : EventHandler!MyEvent
    {
        shared int handled;
        override void onEvent(MyEvent evt, long seq, bool endOfBatch) shared
        {
            import core.atomic : atomicOp;
            atomicOp!"+="(handled, 1);
        }
    }

    auto handler = new shared MyHandler();
    handler.onStart();
    handler.onBatchStart(1, 0);
    auto e = new MyEvent();
    handler.onEvent(e, 0, true);
    handler.onTimeout(0);
    handler.onShutdown();
    assert(handler.handled == 1);
}

