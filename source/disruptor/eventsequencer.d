module disruptor.eventsequencer;

/// Pulls together low-level data access and sequencing operations.
interface EventSequencer(T)
{
    /// Get the event for a given sequence.
    shared(T) get(long sequence) shared;
}

unittest
{
    class DummySequencer : EventSequencer!int
    {
        override shared(int) get(long sequence) shared
        {
            shared int value = cast(int)sequence;
            return value;
        }
    }

    auto seq = new shared DummySequencer();
    assert(seq.get(5) == 5);
}
