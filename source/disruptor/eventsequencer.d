module disruptor.eventsequencer;

/// Pulls together low-level data access and sequencing operations.
interface EventSequencer(T)
{
    /// Get the event for a given sequence.
    T get(long sequence) const shared;
}

unittest
{
    class DummySequencer : EventSequencer!int
    {
        override int get(long sequence) const shared { return cast(int)sequence; }
    }

    shared DummySequencer seq = new shared DummySequencer();
    assert(seq.get(5) == 5);
}
