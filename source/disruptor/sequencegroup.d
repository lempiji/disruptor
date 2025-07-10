module disruptor.sequencegroup;

import core.atomic;
import core.internal.atomic : atomicLoad;
import disruptor.sequence;
import disruptor.sequencer : Cursored;
import disruptor.util : getMinimumSequence;


private int countMatching(shared const(Sequence)[] values, shared const(Sequence) toMatch) @nogc nothrow
{
    int count = 0;
    foreach (v; values)
    {
        if (v is toMatch)
            ++count;
    }
    return count;
}

void addSequences(shared Sequence[]* field, shared Cursored cursor, shared Sequence[] sequencesToAdd...)
{
    long cursorSequence;
    shared Sequence[] updated;
    shared Sequence[] current;
    do
    {
        current = atomicLoad!(MemoryOrder.acq)(field);
        updated = new shared Sequence[](current.length + sequencesToAdd.length);
        updated[0 .. current.length] = current[];
        cursorSequence = cursor.getCursor();
        size_t index = current.length;
        foreach (seq; sequencesToAdd)
        {
            seq.set(cursorSequence);
            updated[index++] = seq;
        }
    }
    while (!cas(field, current, updated));

    cursorSequence = cursor.getCursor();
    foreach (seq; sequencesToAdd)
    {
        seq.set(cursorSequence);
    }
}

bool removeSequence(shared Sequence[]* field, shared Sequence sequence)
{
    int toRemove;
    shared Sequence[] oldSeqs;
    shared Sequence[] newSeqs;
    do
    {
        oldSeqs = atomicLoad!(MemoryOrder.acq)(field);
        toRemove = countMatching(oldSeqs, sequence);
        if (toRemove == 0)
            break;
        newSeqs = new shared Sequence[](oldSeqs.length - toRemove);
        size_t pos = 0;
        foreach (s; oldSeqs)
        {
            if (s !is sequence)
                newSeqs[pos++] = s;
        }
    }
    while (!cas(field, oldSeqs, newSeqs));
    return toRemove != 0;
}

class SequenceGroup : Sequence
{
private:
    align(16) shared Sequence[] sequences = [];

public:
    this() shared
    {
        super(Sequence.INITIAL_VALUE);
    }

    override long get() const shared @nogc nothrow
    {
        auto seqs = atomicLoad!(MemoryOrder.acq)(&sequences);
        return getMinimumSequence(seqs);
    }

    override void set(long value) shared @nogc nothrow
    {
        auto seqs = atomicLoad!(MemoryOrder.acq)(&sequences);
        foreach (s; seqs)
            s.set(value);
    }

    void add(shared Sequence sequence) shared
    {
        shared Sequence[] oldSeqs;
        shared Sequence[] newSeqs;
        do
        {
            oldSeqs = atomicLoad!(MemoryOrder.acq)(&sequences);
            auto oldSize = oldSeqs.length;
            newSeqs = new shared Sequence[](oldSize + 1);
            newSeqs[0 .. oldSize] = oldSeqs[];
            newSeqs[oldSize] = sequence;
        }
        while (!cas(&sequences, oldSeqs, newSeqs));
    }

    bool remove(shared Sequence sequence) shared
    {
        return removeSequence(&sequences, sequence);
    }

    int size() const shared @nogc nothrow
    {
        return cast(int) atomicLoad!(MemoryOrder.acq)(&sequences).length;
    }

    void addWhileRunning(shared Cursored cursor, shared Sequence sequence) shared
    {
        addSequences(&sequences, cursor, sequence);
    }
}

unittest
{
    auto group = new shared SequenceGroup();
    assert(group.get == long.max);
    auto seq1 = new shared Sequence();
    auto seq2 = new shared Sequence();
    group.add(seq1);
    group.add(seq2);
    assert(group.size == 2);
    group.set(5);
    assert(seq1.get == 5 && seq2.get == 5);
    assert(group.remove(seq1));
    assert(group.size == 1);
}

unittest
{
    // A new group should report no sequences and a maximum cursor value.
    auto group = new shared SequenceGroup();
    assert(group.size == 0);
    assert(group.get == long.max);
}

unittest
{
    // Verify adding and removing sequences updates state correctly.
    auto group = new shared SequenceGroup();
    auto seq1 = new shared Sequence();
    auto seq2 = new shared Sequence();
    group.add(seq1);
    group.add(seq2);
    assert(group.size == 2);
    assert(group.get == Sequence.INITIAL_VALUE);
    seq1.set(3);
    seq2.set(7);
    assert(group.get == 3);
    assert(group.remove(seq1));
    assert(!group.remove(seq1));
    assert(group.size == 1);
}

unittest
{
    import core.atomic : atomicOp;
    // addWhileRunning should set new sequences to the cursor value at the time
    // they are added.
    class StubCursor : Cursored
    {
        long cursor = 0;
        override long getCursor() shared { return cursor; }
        void advance(long value) shared { atomicOp!("+=")(cursor, value); }
    }

    auto cursor = new shared StubCursor();
    auto group = new shared SequenceGroup();

    cursor.advance(5);
    auto seq1 = new shared Sequence();
    group.addWhileRunning(cursor, seq1);
    assert(seq1.get == 5);

    cursor.advance(3);
    auto seq2 = new shared Sequence();
    group.addWhileRunning(cursor, seq2);
    assert(seq2.get == 8);

    assert(group.size == 2);
    assert(group.get == 5);
}
