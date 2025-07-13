module disruptor.eventfactory;

/// Factory interface for pre-populating events in the RingBuffer.
interface EventFactory(T)
{
    /// Create a new instance of the event.
    shared(T) newInstance() shared @safe;
}

/// Wrap a delegate to create an `EventFactory` implementation.
class DelegateEventFactory(T) : EventFactory!T
{
    shared(T) delegate() @safe _create;

    this(shared(T) delegate() @safe create) shared
    {
        _create = create;
    }

    override shared(T) newInstance() shared @safe
    {
        return _create();
    }
}

/// Convenience function to create a shared `EventFactory` from a delegate.
shared(EventFactory!T) makeEventFactory(T)(shared(T) delegate() @safe create)
{
    return new shared DelegateEventFactory!T(create);
}

unittest
{
    class MyEvent { int value; }

    class MyFactory : EventFactory!MyEvent
    {
        override shared(MyEvent) newInstance() shared @safe
        {
            return new shared MyEvent();
        }
    }

    auto factory = new shared MyFactory();
    auto evt = factory.newInstance();
    assert(evt !is null);
}
