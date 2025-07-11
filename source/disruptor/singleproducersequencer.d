module disruptor.singleproducersequencer;

import core.thread : Thread;
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
    long nextValue = Sequence.INITIAL_VALUE;
    long cachedValue = Sequence.INITIAL_VALUE;

public:
    this(int bufferSize, shared WaitStrategy waitStrategy)
    {
        super(bufferSize, waitStrategy);
    }

    override bool hasAvailableCapacity(int requiredCapacity)
    {
        return hasAvailableCapacity(requiredCapacity, false);
    }

private:
    bool hasAvailableCapacity(int requiredCapacity, bool doStore)
    {
        long nextValue = this.nextValue;
        long wrapPoint = (nextValue + requiredCapacity) - bufferSize;
        long cachedGatingSequence = this.cachedValue;

        if (wrapPoint > cachedGatingSequence || cachedGatingSequence > nextValue)
        {
            if (doStore)
            {
                cursor.setVolatile(nextValue); // StoreLoad fence
            }

            long minSequence = utilGetMinimumSequence(gatingSequences, nextValue);
            this.cachedValue = minSequence;

            if (wrapPoint > minSequence)
            {
                return false;
            }
        }

        return true;
    }

public:
    override long next()
    {
        return next(1);
    }

    override long next(int n)
    {
        if (n < 1 || n > bufferSize)
            throw new Exception("n must be > 0 and < bufferSize", __FILE__, __LINE__);

        long nextValue = this.nextValue;
        long nextSequence = nextValue + n;
        long wrapPoint = nextSequence - bufferSize;
        long cachedGatingSequence = this.cachedValue;

        if (wrapPoint > cachedGatingSequence || cachedGatingSequence > nextValue)
        {
            cursor.setVolatile(nextValue); // StoreLoad fence

            long minSequence;
            while (wrapPoint > (minSequence = utilGetMinimumSequence(gatingSequences, nextValue)))
            {
                Thread.yield();
            }
            this.cachedValue = minSequence;
        }

        this.nextValue = nextSequence;
        return nextSequence;
    }

    override long tryNext()
    {
        return tryNext(1);
    }

    override long tryNext(int n)
    {
        if (n < 1)
            throw new Exception("n must be > 0", __FILE__, __LINE__);

        if (!hasAvailableCapacity(n, true))
            throw InsufficientCapacityException.INSTANCE;

        long nextSequence = this.nextValue += n;
        return nextSequence;
    }

    override long remainingCapacity()
    {
        long nextValue = this.nextValue;
        long consumed = utilGetMinimumSequence(gatingSequences, nextValue);
        long produced = nextValue;
        return bufferSize - (produced - consumed);
    }

    override void claim(long sequence)
    {
        this.nextValue = sequence;
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
        cast(shared) new SingleProducerSequencer(16, new shared YieldingWaitStrategy());

    foreach (i; 0 .. 32)
    {
        auto next = (cast(SingleProducerSequencer)sequencer).next();
        assert(sequencer.getCursor() != next);

        (cast(SingleProducerSequencer)sequencer).hasAvailableCapacity(13);
        assert(sequencer.getCursor() != next);

        sequencer.publish(next);
    }
}

