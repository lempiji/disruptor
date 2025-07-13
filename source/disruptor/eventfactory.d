module disruptor.eventfactory;

/// Factory interface for pre-populating events in the RingBuffer.
interface EventFactory(T)
{
    /// Create a new instance of the event.
    shared(T) newInstance() @safe;
}

unittest
{
    class MyEvent { int value; }

    class MyFactory : EventFactory!MyEvent
    {
        override shared(MyEvent) newInstance() @safe { return new shared MyEvent(); }
    }

    auto factory = new MyFactory();
    auto evt = factory.newInstance();
    assert(evt !is null);
}
