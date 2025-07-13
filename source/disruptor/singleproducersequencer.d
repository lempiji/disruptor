module disruptor.singleproducersequencer;

import core.thread : Thread;
import core.atomic : MemoryOrder, atomicLoad, atomicStore, atomicOp, pause;
import disruptor.sequence : Sequence;
import disruptor.waitstrategy : WaitStrategy;
import disruptor.sequencer : Sequencer;
import disruptor.abstractsequencer : AbstractSequencer;
import disruptor.util : utilGetMinimumSequence = getMinimumSequence;
import disruptor.insufficientcapacityexception : InsufficientCapacityException;

/// Coordinator for claiming sequences for a single publishing thread.
final class SingleProducerSequencer : AbstractSequencer
{
private:
    shared long nextValue = Sequence.INITIAL_VALUE;
    shared long cachedValue = Sequence.INITIAL_VALUE;

public:
    this(int bufferSize, shared WaitStrategy waitStrategy)
    {
        super(bufferSize, waitStrategy);
    }

    this(int bufferSize, shared WaitStrategy waitStrategy) shared
    {
        super(bufferSize, waitStrategy);
    }

    override bool hasAvailableCapacity(int requiredCapacity) shared
    {
        return hasAvailableCapacity(requiredCapacity, false);
    }

private:
    bool hasAvailableCapacity(int requiredCapacity, bool doStore) shared
    {
        long nextValue = atomicLoad!(MemoryOrder.acq)(this.nextValue);
        long wrapPoint = (nextValue + requiredCapacity) - bufferSize;
        long cachedGatingSequence = atomicLoad!(MemoryOrder.acq)(this.cachedValue);

        if (wrapPoint > cachedGatingSequence || cachedGatingSequence > nextValue)
        {
            if (doStore)
            {
                cursor.setVolatile(nextValue); // StoreLoad fence
            }

            long minSequence = utilGetMinimumSequence(gatingSequences, nextValue);
            atomicStore!(MemoryOrder.rel)(this.cachedValue, minSequence);

            if (wrapPoint > minSequence)
            {
                return false;
            }
        }

        return true;
    }

public:
    override long next() shared
    {
        return next(1);
    }

    override long next(int n) shared
    {
        if (n < 1 || n > bufferSize)
            throw new Exception("n must be > 0 and < bufferSize", __FILE__, __LINE__);

        long nextValue = atomicLoad!(MemoryOrder.acq)(this.nextValue);
        long nextSequence = nextValue + n;
        long wrapPoint = nextSequence - bufferSize;
        long cachedGatingSequence = atomicLoad!(MemoryOrder.acq)(this.cachedValue);

        if (wrapPoint > cachedGatingSequence || cachedGatingSequence > nextValue)
        {
            cursor.setVolatile(nextValue); // StoreLoad fence

            long minSequence;
            while (wrapPoint > (minSequence = utilGetMinimumSequence(gatingSequences, nextValue)))
            {
                pause();
            }
            atomicStore!(MemoryOrder.rel)(this.cachedValue, minSequence);
        }

        atomicStore!(MemoryOrder.rel)(this.nextValue, nextSequence);
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

        if (!hasAvailableCapacity(n, true))
            throw InsufficientCapacityException.INSTANCE;

        long nextSequence = atomicOp!"+="(this.nextValue, n);
        return nextSequence;
    }

    override long remainingCapacity() shared
    {
        long nextValue = atomicLoad!(MemoryOrder.acq)(this.nextValue);
        long consumed = utilGetMinimumSequence(gatingSequences, nextValue);
        long produced = nextValue;
        return bufferSize - (produced - consumed);
    }

    override void claim(long sequence) shared
    {
        atomicStore!(MemoryOrder.rel)(this.nextValue, sequence);
    }

    override void publish(long sequence) shared
    {
        cursor.set(sequence);
        waitStrategy.signalAllWhenBlocking();
    }

    override void publish(long lo, long hi) shared
    {
        publish(hi);
    }

    override bool isAvailable(long sequence) shared
    {
        long currentSequence = cursor.get();
        return sequence <= currentSequence && sequence > currentSequence - bufferSize;
    }

    override long getHighestPublishedSequence(long lowerBound, long availableSequence) shared
    {
        return availableSequence;
    }
}

unittest
{
    import disruptor.yieldingwaitstrategy : YieldingWaitStrategy;

    shared SingleProducerSequencer sequencer =
        new shared SingleProducerSequencer(16, new shared YieldingWaitStrategy());

    foreach (i; 0 .. 32)
    {
        auto next = sequencer.next();
        assert(sequencer.getCursor() != next);

        sequencer.hasAvailableCapacity(13);
        assert(sequencer.getCursor() != next);

        sequencer.publish(next);
    }
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;

    enum int size = 8;
    shared SingleProducerSequencer seq =
        new shared SingleProducerSequencer(size, new shared BlockingWaitStrategy());

    auto s = seq.next();
    assert(!seq.isAvailable(s));
    seq.publish(s);
    assert(seq.isAvailable(s));
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;

    enum int size = 8;
    shared SingleProducerSequencer seq =
        new shared SingleProducerSequencer(size, new shared BlockingWaitStrategy());

    auto s = seq.next();
    seq.publish(s);
    assert(seq.isAvailable(s));

    foreach (i; 0 .. size)
        seq.publish(seq.next());

    assert(!seq.isAvailable(s));
}

