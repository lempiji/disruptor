module disruptor.eventfactory;

/// Factory interface for pre-populating events in the RingBuffer.
interface EventFactory(T)
{
    /// Create a new instance of the event.
    T newInstance();
}

unittest
{
    class MyEvent { int value; }

    class MyFactory : EventFactory!MyEvent
    {
        override MyEvent newInstance() { return new MyEvent(); }
    }

    auto factory = new MyFactory();
    assert(factory.newInstance() !is null);
}
