module disruptor.eventsequencer;

/// Pulls together low-level data access and sequencing operations.
interface EventSequencer(T)
{
    /// Get the event for a given sequence.
    T get(long sequence);
}

unittest
{
    class DummySequencer : EventSequencer!int
    {
        override int get(long sequence) { return cast(int)sequence; }
    }

    auto seq = new DummySequencer();
    assert(seq.get(5) == 5);
}
