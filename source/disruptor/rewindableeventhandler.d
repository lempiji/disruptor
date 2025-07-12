module disruptor.rewindableeventhandler;

import disruptor.eventhandler : EventHandlerBase;

/// Specialised event handler that may request a batch to be replayed.
abstract class RewindableEventHandler(T) : EventHandlerBase!T
{
    /// Called when a publisher has published an event. Implementations may throw
    /// RewindableException to signal that the batch should be retried.
    override abstract void onEvent(T event, long sequence, bool endOfBatch) shared;
}

unittest
{
    class MyEvent { int value; }

    class MyHandler : RewindableEventHandler!MyEvent
    {
        override void onEvent(MyEvent evt, long seq, bool endOfBatch) shared
        {
            evt.value = 1;
        }
    }

    auto handler = new shared MyHandler();
    handler.onStart();
    handler.onBatchStart(1, 0);
    auto e = new MyEvent();
    handler.onEvent(e, 0, true);
    handler.onTimeout(0);
    handler.onShutdown();
    assert(e.value == 1);
}

