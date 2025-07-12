module disruptor.eventprocessor;

import disruptor.sequence : Sequence;

/// An EventProcessor runs in a thread to poll events from the RingBuffer.
interface EventProcessor
{
    /// Main processing loop.
    void run() shared;

    /// Get the Sequence tracked by this processor.
    shared(Sequence) getSequence() shared;

    /// Signal the processor to stop when it reaches a safe point.
    void halt() shared;

    /// Whether the processor is currently running.
    bool isRunning() shared;
}

unittest
{
    class StubProcessor : EventProcessor
    {
        private shared Sequence seq;
        private shared bool running = false;

        this() shared
        {
            seq = new shared Sequence();
        }

        override void run() shared { running = true; }
        override shared(Sequence) getSequence() shared { return seq; }
        override void halt() shared { running = false; }
        override bool isRunning() shared { return running; }
    }

    auto p = new shared StubProcessor();
    p.run();
    assert(p.isRunning());
    p.halt();
    assert(!p.isRunning());
}
