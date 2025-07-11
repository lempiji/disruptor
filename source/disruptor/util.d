module disruptor.util;

import core.time : MonoTime, nsecs;
import core.thread : Thread;
import core.bitop : bsr;
import core.sync.condition : Condition;
import disruptor.sequence : Sequence;

/// Calculate the next power of two greater than or equal to x.
int ceilingNextPowerOfTwo(int x) @safe
{
    if (x < 1)
        throw new Exception("x must be a positive number");
    x -= 1;
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
    return x + 1;
}

/// Get the minimum sequence from an array of sequences.
long getMinimumSequence(scope const(shared Sequence)[] sequences) @nogc nothrow @safe
{
    return getMinimumSequence(sequences, long.max);
}

/// Get the minimum sequence from an array of sequences with a default value.
long getMinimumSequence(scope const(shared Sequence)[] sequences, long minimum) @nogc nothrow @safe
{
    auto min = minimum;
    foreach (s; sequences)
    {
        auto value = s.get();
        if (value < min)
            min = value;
    }
    return min;
}

/// Extract sequences from a list of processors providing a getSequence method.
shared Sequence[] getSequencesFor(Processors...)(Processors processors) @safe
        if (Processors.length > 0 && is(typeof(processors[0].getSequence()) : Sequence))
{
    auto seqs = new shared Sequence[](processors.length);
    foreach (i, p; processors)
        seqs[i] = p.getSequence();
    return seqs;
}

/// Integer log base 2.
int log2(int value) @safe
{
    if (value < 1)
        throw new Exception("value must be a positive number");
    return bsr(cast(uint) value);
}

/// Wait on the calling thread for approximately the given nanoseconds.
long awaitNanos(shared Condition cond, long timeoutNanos)
{
    auto start = MonoTime.currTime;
    auto mtx = cond.mutex;
    mtx.lock();
    scope (exit)
        mtx.unlock();
    cond.wait(nsecs(timeoutNanos));
    auto waited = MonoTime.currTime - start;
    return timeoutNanos - cast(long) waited.total!"nsecs";
}

unittest
{
    import std.exception : assertThrown;

    assert(ceilingNextPowerOfTwo(1000) == 1024);
    assert(ceilingNextPowerOfTwo(1024) == 1024);
    assertThrown!Exception(ceilingNextPowerOfTwo(0));
    assertThrown!Exception(ceilingNextPowerOfTwo(-1));

    auto seq1 = new shared Sequence(7);
    auto seq2 = new shared Sequence(3);
    auto seq3 = new shared Sequence(12);
    shared Sequence[] seqs = [seq1, seq2, seq3];
    assert(getMinimumSequence(seqs) == 3);
    shared Sequence[] empty;
    assert(getMinimumSequence(empty) == long.max);

    assertThrown!Exception(log2(0));
    assertThrown!Exception(log2(-1));
    assertThrown!Exception(log2(int.min));

    assert(log2(1) == 0);
    assert(log2(2) == 1);
    assert(log2(3) == 1);
    assert(log2(1024) == 10);
    assert(log2(int.max) == 30);
}

unittest
{
    import core.sync.mutex : Mutex;
    import core.sync.condition : Condition;
    import core.thread : Thread;
    import core.time : msecs;

    auto mtx = new shared Mutex();
    auto cond = new shared Condition(mtx);

    auto t = new Thread({
        Thread.sleep(50.msecs);
        mtx.lock();
        scope(exit) mtx.unlock();
        cond.notify();
    });
    t.start();

    enum long timeout = 200_000_000; // 200ms
    auto remaining = awaitNanos(cond, timeout);
    assert(remaining > 0 && remaining <= timeout);
    t.join();
}
