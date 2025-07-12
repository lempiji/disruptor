module disruptor.multiproducersequencer;

import core.atomic;
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
    this(int bufferSize, shared WaitStrategy waitStrategy)
    {
        super(bufferSize, waitStrategy);
        gatingSequenceCache = new shared Sequence(Sequencer.INITIAL_CURSOR_VALUE);
        availableBuffer = new shared int[](bufferSize);
        foreach (i; 0 .. bufferSize)
            availableBuffer[i] = -1;
        indexMask = bufferSize - 1;
        indexShift = log2(bufferSize);
    }

    this(int bufferSize, shared WaitStrategy waitStrategy) shared
    {
        this(bufferSize, waitStrategy);
    }

    override bool hasAvailableCapacity(int requiredCapacity) shared
    {
        return (cast(MultiProducerSequencer)this)
            .hasAvailableCapacity(gatingSequences, requiredCapacity, cursor.get());
    }

private:
    bool hasAvailableCapacity(shared Sequence[] gatingSequences, int requiredCapacity, long cursorValue)
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
    override void claim(long sequence)
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
                Thread.yield();
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

            if (!(cast(MultiProducerSequencer)this)
                    .hasAvailableCapacity(gatingSequences, n, current))
                throw InsufficientCapacityException.INSTANCE;
        }
        while (!cursor.compareAndSet(current, next));

        return next;
    }

    override long remainingCapacity() shared
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
    void setAvailable(long sequence) shared
    {
        setAvailableBufferValue(calculateIndex(sequence), calculateAvailabilityFlag(sequence));
    }

    void setAvailableBufferValue(int index, int flag) shared
    {
        atomicStore!(MemoryOrder.rel)(availableBuffer[index], flag);
    }

public:
    override bool isAvailable(long sequence) shared
    {
        int index = calculateIndex(sequence);
        int flag = calculateAvailabilityFlag(sequence);
        return atomicLoad!(MemoryOrder.acq)(availableBuffer[index]) == flag;
    }

    override long getHighestPublishedSequence(long lowerBound, long availableSequence) shared
    {
        for (long sequence = lowerBound; sequence <= availableSequence; sequence++)
        {
            if (!isAvailable(sequence))
                return sequence - 1;
        }
        return availableSequence;
    }

private:
    int calculateAvailabilityFlag(long sequence) const shared
    {
        return cast(int)(sequence >>> indexShift);
    }

    int calculateIndex(long sequence) const shared
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
