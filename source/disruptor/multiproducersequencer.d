module disruptor.multiproducersequencer;

import core.atomic : MemoryOrder, atomicLoad, atomicStore, pause;
import core.thread : Thread;
import disruptor.sequence : Sequence;
import disruptor.waitstrategy : WaitStrategy;
import disruptor.sequencer : Sequencer;
import disruptor.abstractsequencer : AbstractSequencer;
import disruptor.util : utilGetMinimumSequence = getMinimumSequence, log2;
import disruptor.insufficientcapacityexception : InsufficientCapacityException;

/// Coordinator for claiming sequences suitable for multiple publisher threads.
final class MultiProducerSequencer : AbstractSequencer
{
private:
    shared Sequence gatingSequenceCache;
    shared int[] availableBuffer;
    int indexMask;
    int indexShift;

public:
    this(int bufferSize, shared WaitStrategy waitStrategy) shared
    {
        super(bufferSize, waitStrategy);
        gatingSequenceCache = new shared Sequence(Sequencer.INITIAL_CURSOR_VALUE);
        availableBuffer = new shared int[](bufferSize);
        foreach (i; 0 .. bufferSize)
            availableBuffer[i] = -1;
        indexMask = bufferSize - 1;
        indexShift = log2(bufferSize);
    }

    override bool hasAvailableCapacity(int requiredCapacity) shared @safe nothrow @nogc
    {
        return hasAvailableCapacity(gatingSequences, requiredCapacity, cursor.get());
    }

private:
    bool hasAvailableCapacity(shared Sequence[] gatingSequences, int requiredCapacity, long cursorValue) shared @safe nothrow @nogc
    {
        long wrapPoint = (cursorValue + requiredCapacity) - bufferSize;
        long cachedGatingSequence = gatingSequenceCache.get();

        if (wrapPoint > cachedGatingSequence || cachedGatingSequence > cursorValue)
        {
            long minSequence = utilGetMinimumSequence(gatingSequences, cursorValue);
            gatingSequenceCache.set(minSequence);

            if (wrapPoint > minSequence)
            {
                return false;
            }
        }
        return true;
    }

public:
    override void claim(long sequence) shared @safe nothrow @nogc
    {
        cursor.set(sequence);
    }

    override long next() shared
    {
        return next(1);
    }

    override long next(int n) shared
    {
        if (n < 1 || n > bufferSize)
            throw new Exception("n must be > 0 and < bufferSize", __FILE__, __LINE__);

        long current = cursor.getAndAdd(n);
        long nextSequence = current + n;
        long wrapPoint = nextSequence - bufferSize;
        long cachedGatingSequence = gatingSequenceCache.get();

        if (wrapPoint > cachedGatingSequence || cachedGatingSequence > current)
        {
            long gatingSequence;
            while (wrapPoint > (gatingSequence = utilGetMinimumSequence(gatingSequences, current)))
            {
                pause();
            }
            gatingSequenceCache.set(gatingSequence);
        }
        return nextSequence;
    }

    override long tryNext() shared
    {
        return tryNext(1);
    }

    override long tryNext(int n) shared
    {
        if (n < 1)
            throw new Exception("n must be > 0", __FILE__, __LINE__);

        long current;
        long next;
        do
        {
            current = cursor.get();
            next = current + n;

            if (!hasAvailableCapacity(gatingSequences, n, current))
                throw InsufficientCapacityException.INSTANCE;
        }
        while (!cursor.compareAndSet(current, next));

        return next;
    }

    override long remainingCapacity() shared @safe nothrow @nogc
    {
        long consumed = utilGetMinimumSequence(gatingSequences, cursor.get());
        long produced = cursor.get();
        return bufferSize - (produced - consumed);
    }

    override void publish(long sequence) shared
    {
        setAvailable(sequence);
        waitStrategy.signalAllWhenBlocking();
    }

    override void publish(long lo, long hi) shared
    {
        for (long l = lo; l <= hi; l++)
        {
            setAvailable(l);
        }
        waitStrategy.signalAllWhenBlocking();
    }

private:
    void setAvailable(long sequence) shared @safe nothrow @nogc
    {
        setAvailableBufferValue(calculateIndex(sequence), calculateAvailabilityFlag(sequence));
    }

    void setAvailableBufferValue(int index, int flag) shared @safe nothrow @nogc
    {
        atomicStore!(MemoryOrder.rel)(availableBuffer[index], flag);
    }

public:
    override bool isAvailable(long sequence) shared @safe nothrow @nogc
    {
        int index = calculateIndex(sequence);
        int flag = calculateAvailabilityFlag(sequence);
        return atomicLoad!(MemoryOrder.acq)(availableBuffer[index]) == flag;
    }

    override long getHighestPublishedSequence(long lowerBound, long availableSequence) shared @safe nothrow @nogc
    {
        for (long sequence = lowerBound; sequence <= availableSequence; sequence++)
        {
            if (!isAvailable(sequence))
                return sequence - 1;
        }
        return availableSequence;
    }

private:
    int calculateAvailabilityFlag(long sequence) const shared @safe nothrow @nogc
    {
        return cast(int)(sequence >>> indexShift);
    }

    int calculateIndex(long sequence) const shared @safe nothrow @nogc
    {
        return cast(int)sequence & indexMask;
    }
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;

    shared MultiProducerSequencer sequencer =
        new shared MultiProducerSequencer(1024, new shared BlockingWaitStrategy());

    sequencer.publish(3);
    sequencer.publish(5);

    auto sharedSeq = sequencer;
    assert(!sharedSeq.isAvailable(0));
    assert(!sharedSeq.isAvailable(1));
    assert(!sharedSeq.isAvailable(2));
    assert(sharedSeq.isAvailable(3));
    assert(!sharedSeq.isAvailable(4));
    assert(sharedSeq.isAvailable(5));
    assert(!sharedSeq.isAvailable(6));
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;

    enum int size = 8;
    shared MultiProducerSequencer seq =
        new shared MultiProducerSequencer(size, new shared BlockingWaitStrategy());

    auto s = seq.next();
    assert(!seq.isAvailable(s));
    seq.publish(s);
    assert(seq.isAvailable(s));
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;

    enum int size = 8;
    shared MultiProducerSequencer seq =
        new shared MultiProducerSequencer(size, new shared BlockingWaitStrategy());

    auto s = seq.next();
    seq.publish(s);
    assert(seq.isAvailable(s));

    foreach (i; 0 .. size)
        seq.publish(seq.next());

    assert(!seq.isAvailable(s));
}
