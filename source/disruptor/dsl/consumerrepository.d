module disruptor.dsl.consumerrepository;

import disruptor.eventprocessor : EventProcessor;
import disruptor.eventhandler : EventHandlerIdentity;
import disruptor.sequence : Sequence;
import disruptor.sequencer : SequenceBarrier;
import disruptor.threadfactory : ThreadFactory;
import disruptor.dsl.consumerinfo : ConsumerInfo;
import std.conv : to;

/// Repository associating event handlers with their processors and gating sequences.
/// Internal wrapper tying a processor to its barrier and running state.
class EventProcessorInfo : ConsumerInfo
{
    shared(EventProcessor) _processor;
    shared(SequenceBarrier) _barrier;
    bool _endOfChain = true;

    this(shared(EventProcessor) processor, shared(SequenceBarrier) barrier)
    {
        _processor = processor;
        _barrier = barrier;
    }

    this(shared(EventProcessor) processor, shared(SequenceBarrier) barrier) shared
    {
        _processor = processor;
        _barrier = barrier;
    }

    shared(EventProcessor) getEventProcessor() shared { return _processor; }

    override shared(Sequence)[] getSequences() shared
    {
        return [_processor.getSequence()];
    }

    override shared(SequenceBarrier) getBarrier() shared
    {
        return _barrier;
    }

    override bool isEndOfChain() shared { return _endOfChain; }

    override void start(ThreadFactory threadFactory) shared
    {
        auto t = threadFactory({ _processor.run(); });
        if (t is null)
            throw new Exception("Failed to create thread to run processor", __FILE__, __LINE__);
        t.start();
    }

    override void halt() shared { _processor.halt(); }

    override void markAsUsedInBarrier() shared { _endOfChain = false; }

    override bool isRunning() shared { return _processor.isRunning(); }
}

class ConsumerRepository
{
private:
    shared(EventProcessorInfo)[EventHandlerIdentity] _infoByHandler;
    shared(ConsumerInfo)[shared Sequence] _infoBySequence;
    shared(ConsumerInfo)[] _infos;


public:
    /// Register a processor and its handler/barrier with the repository.
    void add(shared(EventProcessor) processor, EventHandlerIdentity handlerIdentity, shared(SequenceBarrier) barrier)
    {
        auto info = new shared EventProcessorInfo(processor, barrier);
        _infoByHandler[handlerIdentity] = info;
        _infoBySequence[processor.getSequence()] = info;
        _infos ~= info;
    }

    /// Register a processor that has no associated handler.
    void add(shared(EventProcessor) processor)
    {
        auto info = new shared EventProcessorInfo(processor, null);
        _infoBySequence[processor.getSequence()] = info;
        _infos ~= info;
    }

    /// Start all processors using threads from the factory.
    void startAll(ThreadFactory threadFactory)
    {
        foreach (c; _infos)
            c.start(threadFactory);
    }

    /// Signal all processors to halt.
    void haltAll()
    {
        foreach (c; _infos)
            c.halt();
    }

    /// Check if any end-of-chain consumers are lagging behind the given cursor.
    bool hasBacklog(long cursor, bool includeStopped)
    {
        foreach (c; _infos)
        {
            if ((includeStopped || c.isRunning()) && c.isEndOfChain())
            {
                foreach (seq; c.getSequences())
                {
                    if (cursor > seq.get())
                        return true;
                }
            }
        }
        return false;
    }

    /// Retrieve the processor associated with the given handler.
    shared(EventProcessor) getEventProcessorFor(EventHandlerIdentity handlerIdentity)
    {
        auto ptr = handlerIdentity in _infoByHandler;
        if (ptr is null)
            throw new Exception("The event handler " ~ to!string(cast(void*)handlerIdentity) ~ " is not processing events.");
        return (*ptr).getEventProcessor();
    }

    /// Get the sequence tracked by the processor for the given handler.
    shared(Sequence) getSequenceFor(EventHandlerIdentity handlerIdentity)
    {
        return getEventProcessorFor(handlerIdentity).getSequence();
    }

    /// Mark the given processors as no longer being at the end of the chain.
    void unMarkEventProcessorsAsEndOfChain(shared Sequence[] barrierEventProcessors...)
    {
        foreach (seq; barrierEventProcessors)
        {
            auto ptr = seq in _infoBySequence;
            if (ptr !is null)
                (*ptr).markAsUsedInBarrier();
        }
    }

    /// Get the barrier used by the handler, if registered.
    shared(SequenceBarrier) getBarrierFor(EventHandlerIdentity handlerIdentity)
    {
        auto ptr = handlerIdentity in _infoByHandler;
        return ptr ? (*ptr).getBarrier() : null;
    }
}

unittest
{
    import core.thread : Thread;
    import disruptor.sequence : Sequence;
    import disruptor.sequencer : SequenceBarrier;
    import disruptor.eventprocessor : EventProcessor;
    import disruptor.eventhandler : EventHandlerIdentity;

    class StubProcessor : EventProcessor
    {
        shared Sequence seq;
        shared bool running = false;
        this() shared { seq = new shared Sequence(); }
        override void run() shared { running = true; }
        override shared(Sequence) getSequence() shared { return seq; }
        override void halt() shared { running = false; }
        override bool isRunning() shared { return running; }
    }

    class DummyBarrier : SequenceBarrier
    {
        override long waitFor(long sequence) shared { return sequence; }
        override long getCursor() shared { return 0; }
        override bool isAlerted() shared { return false; }
        override void alert() shared {}
        override void clearAlert() shared {}
        override void checkAlert() shared {}
    }

    class DummyHandler : EventHandlerIdentity { }

    auto repo = new ConsumerRepository();
    auto p1 = new shared StubProcessor();
    auto p2 = new shared StubProcessor();
    auto h1 = new DummyHandler();
    auto b1 = new shared DummyBarrier();

    repo.add(p1, h1, b1);
    repo.add(p2);

    assert(repo.getBarrierFor(h1) is b1);
    assert(repo.getEventProcessorFor(h1) is p1);

    alias Factory = ThreadFactory;
    Factory factory = (void delegate() runnable){ return new Thread(runnable); };
    repo.startAll(factory);
    import core.thread : Thread;
    import core.time : msecs;
    Thread.sleep(10.msecs);
    assert(p1.isRunning && p2.isRunning);

    repo.haltAll();
    assert(!p1.isRunning && !p2.isRunning);

    p1.getSequence().set(5);
    p2.getSequence().set(10);
    assert(repo.hasBacklog(10, true));
    repo.unMarkEventProcessorsAsEndOfChain(p1.getSequence());
    assert(!repo.hasBacklog(10, true));
}
