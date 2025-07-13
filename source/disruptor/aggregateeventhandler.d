module disruptor.aggregateeventhandler;

import disruptor.eventhandler : EventHandler;

/// Aggregate collection of EventHandlers that are invoked in sequence.
final class AggregateEventHandler(T) : EventHandler!T
{
private:
    shared(EventHandler!T)[] _handlers;

public:
    /// Construct an AggregateEventHandler with the given handlers.
    this(shared EventHandler!T[] handlers...) shared
    {
        _handlers = handlers.dup;
    }

    override void onEvent(T event, long sequence, bool endOfBatch) shared
    {
        foreach (h; _handlers)
        {
            h.onEvent(event, sequence, endOfBatch);
        }
    }

    override void onStart() shared @safe nothrow
    {
        foreach (h; _handlers)
            h.onStart();
    }

    override void onShutdown() shared @safe nothrow
    {
        foreach (h; _handlers)
            h.onShutdown();
    }
}

unittest
{
    class DummyEvent { int value; }

    class DummyHandler : EventHandler!DummyEvent
    {
        shared DummyEvent lastEvent;
        shared long lastSequence;
        shared int startCalls;
        shared int shutdownCalls;

        override void onEvent(DummyEvent evt, long seq, bool endOfBatch) shared
        {
            lastEvent = cast(shared)evt;
            lastSequence = seq;
        }

        override void onStart() shared @safe nothrow
        {
            import core.atomic : atomicOp;
            atomicOp!"+="(startCalls, 1);
        }

        override void onShutdown() shared @safe nothrow
        {
            import core.atomic : atomicOp;
            atomicOp!"+="(shutdownCalls, 1);
        }
    }

    auto eh1 = new shared DummyHandler();
    auto eh2 = new shared DummyHandler();
    auto eh3 = new shared DummyHandler();

    auto agg = new shared AggregateEventHandler!DummyEvent(eh1, eh2, eh3);

    auto event = new DummyEvent();
    agg.onEvent(event, 3L, true);

    foreach(h; [eh1, eh2, eh3])
    {
        assert(cast(DummyEvent)h.lastEvent is event);
        assert(h.lastSequence == 3L);
    }

    agg.onStart();
    foreach(h; [eh1, eh2, eh3])
        assert(h.startCalls == 1);

    agg.onShutdown();
    foreach(h; [eh1, eh2, eh3])
        assert(h.shutdownCalls == 1);

    auto empty = new shared AggregateEventHandler!DummyEvent();
    empty.onEvent(event, 0L, true);
    empty.onStart();
    empty.onShutdown();
}
