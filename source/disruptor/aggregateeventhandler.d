module disruptor.aggregateeventhandler;

import disruptor.eventhandler : EventHandler;

/// Aggregate collection of `EventHandler`s to be called in sequence.
final class AggregateEventHandler(T) : EventHandler!T
{
    private shared(EventHandler!T)[] _eventHandlers;

    /// Construct an aggregate collection of `EventHandler`s to be called in sequence.
    this(shared(EventHandler!T)[] eventHandlers...) shared @safe
    {
        _eventHandlers = eventHandlers.dup;
    }

    override void onEvent(T event, long sequence, bool endOfBatch) shared
    {
        foreach (handler; _eventHandlers)
        {
            handler.onEvent(event, sequence, endOfBatch);
        }
    }

    override void onStart() shared
    {
        foreach (handler; _eventHandlers)
        {
            handler.onStart();
        }
    }

    override void onShutdown() shared
    {
        foreach (handler; _eventHandlers)
        {
            handler.onShutdown();
        }
    }
}

unittest
{
    class DummyEventHandler : EventHandler!(int[])
    {
        shared int startCalls;
        shared int shutdownCalls;
        int[] lastEvent;
        long lastSequence;

        override void onEvent(int[] event, long sequence, bool endOfBatch) shared
        {
            (cast(DummyEventHandler)this).lastEvent = event;
            (cast(DummyEventHandler)this).lastSequence = sequence;
        }

        override void onStart() shared
        {
            import core.atomic : atomicOp;
            atomicOp!"+="(startCalls, 1);
        }

        override void onShutdown() shared
        {
            import core.atomic : atomicOp;
            atomicOp!"+="(shutdownCalls, 1);
        }
    }

    auto eh1 = new shared DummyEventHandler();
    auto eh2 = new shared DummyEventHandler();
    auto eh3 = new shared DummyEventHandler();
    auto agg = new shared AggregateEventHandler!(int[])(eh1, eh2, eh3);

    int[] evt = [7];
    agg.onEvent(evt, 3, true);

    assert((cast(DummyEventHandler)eh1).lastEvent is evt &&
           (cast(DummyEventHandler)eh1).lastSequence == 3);
    assert((cast(DummyEventHandler)eh2).lastEvent is evt &&
           (cast(DummyEventHandler)eh2).lastSequence == 3);
    assert((cast(DummyEventHandler)eh3).lastEvent is evt &&
           (cast(DummyEventHandler)eh3).lastSequence == 3);
}

unittest
{
    class DummyEventHandler : EventHandler!(int[])
    {
        shared int startCalls;
        override void onEvent(int[] event, long sequence, bool endOfBatch) shared {}
        override void onStart() shared { import core.atomic : atomicOp; atomicOp!"+="(startCalls, 1); }
    }

    auto eh1 = new shared DummyEventHandler();
    auto eh2 = new shared DummyEventHandler();
    auto eh3 = new shared DummyEventHandler();
    auto agg = new shared AggregateEventHandler!(int[])(eh1, eh2, eh3);

    agg.onStart();

    assert(eh1.startCalls == 1);
    assert(eh2.startCalls == 1);
    assert(eh3.startCalls == 1);
}

unittest
{
    class DummyEventHandler : EventHandler!(int[])
    {
        shared int shutdownCalls;
        override void onEvent(int[] event, long sequence, bool endOfBatch) shared {}
        override void onShutdown() shared { import core.atomic : atomicOp; atomicOp!"+="(shutdownCalls, 1); }
    }

    auto eh1 = new shared DummyEventHandler();
    auto eh2 = new shared DummyEventHandler();
    auto eh3 = new shared DummyEventHandler();
    auto agg = new shared AggregateEventHandler!(int[])(eh1, eh2, eh3);

    agg.onShutdown();

    assert(eh1.shutdownCalls == 1);
    assert(eh2.shutdownCalls == 1);
    assert(eh3.shutdownCalls == 1);
}

unittest
{
    auto agg = new shared AggregateEventHandler!(int[])();
    agg.onEvent([7], 0, true);
    agg.onStart();
    agg.onShutdown();
}

