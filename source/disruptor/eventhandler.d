module disruptor.eventhandler;

import disruptor.sequence : Sequence;

interface EventHandlerIdentity
{
}

interface EventHandlerBase(T) : EventHandlerIdentity
{
    void onEvent(T event, long sequence, bool endOfBatch);

    final void onBatchStart(long batchSize, long queueDepth)
    {
    }

    final void onStart()
    {
    }

    final void onShutdown()
    {
    }

    final void onTimeout(long sequence)
    {
    }
}

interface EventHandler(T) : EventHandlerBase!T
{
    override void onEvent(T event, long sequence, bool endOfBatch);

    final void setSequenceCallback(shared Sequence sequenceCallback)
    {
    }
}

unittest
{
    class IntHandler : EventHandler!int
    {
        int last;
        override void onEvent(int event, long sequence, bool endOfBatch)
        {
            last = event;
        }
    }

    auto h = new IntHandler();
    h.onStart();
    h.onBatchStart(1, 1);
    h.onEvent(42, 0, true);
    assert(h.last == 42);
    h.onTimeout(0);
    h.onShutdown();
    h.setSequenceCallback(new shared Sequence());
}
