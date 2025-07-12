module disruptor.fixedsequencegroup;

import disruptor.sequence : Sequence;
import disruptor.util : getMinimumSequence;

/// Hides a group of Sequences behind a single Sequence.
final class FixedSequenceGroup : Sequence
{
private:
    shared Sequence[] sequences;

public:
    this(shared Sequence[] sequences) shared
    {
        super(Sequence.INITIAL_VALUE);
        // copy the array so callers cannot modify it
        this.sequences = sequences.dup;
    }

    override long get() const shared @nogc nothrow @safe
    {
        // The array is immutable so no atomic load needed
        return getMinimumSequence(sequences);
    }

    override void set(long value) shared @nogc nothrow @safe
    {
        assert(0, "unsupported");
    }

    override bool compareAndSet(long expectedValue, long newValue) shared @nogc nothrow @safe
    {
        assert(0, "unsupported");
    }

    override long incrementAndGet() shared @nogc nothrow @safe
    {
        assert(0, "unsupported");
    }

    override long addAndGet(long inc) shared @nogc nothrow @safe
    {
        assert(0, "unsupported");
    }

    override string toString() const shared @safe
    {
        import std.array : appender;
        import std.conv : to;

        auto app = appender!string();
        app.put("[");
        foreach (i, seq; sequences)
        {
            if (i != 0)
                app.put(", ");
            app.put(seq.get.to!string);
        }
        app.put("]");
        return app.data;
    }
}

unittest
{
    auto seq1 = new shared Sequence(34);
    auto seq2 = new shared Sequence(47);
    auto group = new shared FixedSequenceGroup([seq1, seq2]);

    assert(group.get == 34);
    seq1.set(35);
    assert(group.get == 35);
    seq1.set(48);
    assert(group.get == 47);
}
