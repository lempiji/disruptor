module disruptor.sequence;

import core.atomic : MemoryOrder, atomicLoad, atomicStore, atomicOp, cas;
import std.conv : to;

/// Concurrent sequence class similar to the Java version.
class Sequence
{
    /// Initial value used by sequencers
    enum long INITIAL_VALUE = -1;

private:
    // Padding on either side of the value to avoid false sharing.
    long[7] _pad1 = 0;
    shared long _value = INITIAL_VALUE;
    long[7] _pad2 = 0;

public:
    this(long initialValue = INITIAL_VALUE) shared @safe nothrow
    {
        atomicStore!(MemoryOrder.rel)(_value, initialValue);
    }

    long get() const shared @nogc nothrow @safe
    {
        return atomicLoad!(MemoryOrder.acq)(_value);
    }

    void set(long v) shared @nogc nothrow @safe
    {
        atomicStore!(MemoryOrder.rel)(_value, v);
    }

    void setVolatile(long v) shared @nogc nothrow @safe
    {
        atomicStore!()( _value, v );
    }

    bool compareAndSet(long expectedValue, long newValue) shared @nogc nothrow @safe
    {
        return cas(&_value, expectedValue, newValue);
    }

    long incrementAndGet() shared @nogc nothrow @safe
    {
        return atomicOp!"+="(_value, 1L);
    }

    long addAndGet(long inc) shared @nogc nothrow @safe
    {
        return atomicOp!"+="(_value, inc);
    }

    long getAndAdd(long inc) shared @nogc nothrow @safe
    {
        auto result = atomicOp!"+="(_value, inc);
        return result - inc;
    }

    string toString() const shared @safe
    {
        return get.to!string;
    }
}

unittest
{
    auto seq = new shared Sequence();
    assert(seq.get == Sequence.INITIAL_VALUE);
    assert(seq.incrementAndGet() == Sequence.INITIAL_VALUE + 1);
    assert(seq.addAndGet(5) == Sequence.INITIAL_VALUE + 6);
    assert(seq.getAndAdd(2) == Sequence.INITIAL_VALUE + 6);
    assert(seq.get == Sequence.INITIAL_VALUE + 8);
    assert(seq.compareAndSet(Sequence.INITIAL_VALUE + 8, 3));
    assert(seq.get == 3);
    assert(!seq.compareAndSet(0, 1));
}
