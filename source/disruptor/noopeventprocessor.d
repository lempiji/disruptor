module disruptor.noopeventprocessor;

import core.atomic : MemoryOrder, atomicLoad, atomicStore, cas;
import disruptor.eventprocessor : EventProcessor;
import disruptor.sequence : Sequence;
import disruptor.sequencer : Cursored, Sequencer;

/**
 * No operation EventProcessor that simply tracks a Sequencer's cursor.
 * Useful for tests or filling a RingBuffer from a publisher.
 */
class NoOpEventProcessor : EventProcessor
{
private:
    shared SequencerFollowingSequence _sequence;
    shared bool _running = false;

public:
    /// Create a new NoOpEventProcessor that follows the given cursored object.
    this(shared Cursored cursor) shared
    {
        _sequence = new shared SequencerFollowingSequence(cursor);
    }

    override shared(Sequence) getSequence() shared
    {
        return _sequence;
    }

    override void halt() shared
    {
        atomicStore!(MemoryOrder.rel)(_running, false);
    }

    override bool isRunning() shared
    {
        return atomicLoad!(MemoryOrder.acq)(_running);
    }

    override void run() shared
    {
        bool expected = false;
        if (!cas(&_running, expected, true))
            throw new Exception("Thread is already running", __FILE__, __LINE__);
    }

private:
    /// Sequence that mirrors another cursor's position.
    final class SequencerFollowingSequence : Sequence
    {
    private:
        shared Cursored _cursor;

    public:
        this(shared Cursored cursor) shared
        {
            super(Sequencer.INITIAL_CURSOR_VALUE);
            _cursor = cursor;
        }

        override long get() const shared @nogc nothrow @trusted
        {
            auto dg = &(cast(shared Cursored)_cursor).getCursor;
            auto safeDg = cast(long delegate() shared nothrow @nogc) dg;
            return safeDg();
        }
    }
}

unittest
{
    import disruptor.ringbuffer : RingBuffer;
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import disruptor.eventfactory : makeEventFactory;
    import std.exception : assertThrown;

    class StubEvent { int value; }

    auto rb = RingBuffer!StubEvent.createSingleProducer(
        makeEventFactory!StubEvent(() => new shared StubEvent()),
        4,
        new shared BlockingWaitStrategy());

    auto p = new shared NoOpEventProcessor(rb);
    assert(!p.isRunning());
    p.run();
    assert(p.isRunning());
    assertThrown!Exception(p.run());
    p.halt();
    assert(!p.isRunning());

    assert(p.getSequence().get() == rb.getCursor());
    auto seq = rb.next();
    rb.publish(seq);
    assert(p.getSequence().get() == rb.getCursor());
}
