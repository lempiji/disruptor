module disruptor.singleproducersequencer;

import core.thread : Thread;
import disruptor.sequence : Sequence;
import disruptor.waitstrategy : WaitStrategy;
import disruptor.sequencer : Sequencer, SequenceBarrier, Cursored, DataProvider, EventPoller;
import disruptor.abstractsequencer : AbstractSequencer;
import disruptor.util : utilGetMinimumSequence = getMinimumSequence;

/// Exception thrown when the ring buffer doesn't have sufficient capacity.
class InsufficientCapacityException : Exception
{
    this(string msg = "Insufficient capacity", string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Sequencer for single producer scenarios.
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
                cursor.setVolatile(nextValue);
            }

            long minSequence = utilGetMinimumSequence(cast(shared const Sequence[]) gatingSequences, nextValue);
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
        assert(n > 0 && n <= bufferSize, "n must be > 0 and < bufferSize");

        long nextValue = this.nextValue;
        long nextSequence = nextValue + n;
        long wrapPoint = nextSequence - bufferSize;
        long cachedGatingSequence = this.cachedValue;

        if (wrapPoint > cachedGatingSequence || cachedGatingSequence > nextValue)
        {
            cursor.setVolatile(nextValue);
            long minSequence;
            while (wrapPoint > (minSequence = utilGetMinimumSequence(cast(shared const Sequence[]) gatingSequences, nextValue)))
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
        assert(n > 0, "n must be > 0");

        if (!hasAvailableCapacity(n, true))
        {
            throw new InsufficientCapacityException();
        }

        long nextSequence = this.nextValue += n;
        return nextSequence;
    }

    override long remainingCapacity()
    {
        long nextValue = this.nextValue;
        long consumed = utilGetMinimumSequence(cast(shared const Sequence[]) gatingSequences, nextValue);
        long produced = nextValue;
        return bufferSize - (produced - consumed);
    }

    override void claim(long sequence)
    {
        this.nextValue = sequence;
    }

    override void publish(long sequence)
    {
        cursor.set(sequence);
        waitStrategy.signalAllWhenBlocking();
    }

    override void publish(long lo, long hi)
    {
        publish(hi);
    }

    override bool isAvailable(long sequence)
    {
        long currentSequence = cursor.get();
        return sequence <= currentSequence && sequence > currentSequence - bufferSize;
    }

    override long getHighestPublishedSequence(long nextSequence, long availableSequence)
    {
        return availableSequence;
    }

    EventPoller!T newPoller(T)(DataProvider!T provider, shared Sequence[] gatingSequences...)
    {
        return null;
    }
}

unittest
{
    import disruptor.waitstrategy : BusySpinWaitStrategy;

    auto sequencer = new SingleProducerSequencer(16, new shared BusySpinWaitStrategy());

    foreach (i; 0 .. 32)
    {
        auto next = sequencer.next();
        assert((cast(shared SingleProducerSequencer)sequencer).getCursor() != next);

        sequencer.hasAvailableCapacity(13);
        assert((cast(shared SingleProducerSequencer)sequencer).getCursor() != next);

        sequencer.publish(next);
    }
}
