module disruptor.consumerrepository;

import std.exception : enforce;
import disruptor.eventprocessor : EventProcessor;
import disruptor.sequence : Sequence;
import disruptor.sequencer : SequenceBarrier;
import disruptor.eventhandler : EventHandlerIdentity;
import disruptor.consumerinfo : ConsumerInfo, ThreadFactory;
import disruptor.eventprocessorinfo : EventProcessorInfo;

/// Repository associating `EventHandler` instances with their `EventProcessor`s.
class ConsumerRepository
{
private:
    shared(EventProcessorInfo)[EventHandlerIdentity] _infoByHandler;
    shared(ConsumerInfo)[shared Sequence] _infoBySequence;
    shared ConsumerInfo[] _consumerInfos;

public:
    void add(shared EventProcessor processor,
             shared EventHandlerIdentity handlerIdentity,
             shared SequenceBarrier barrier)
    {
        auto info = new shared EventProcessorInfo(processor, barrier);
        _infoByHandler[cast(EventHandlerIdentity)handlerIdentity] = info;
        _infoBySequence[processor.getSequence()] = info;
        _consumerInfos ~= info;
    }

    void add(shared EventProcessor processor)
    {
        auto info = new shared EventProcessorInfo(processor, null);
        _infoBySequence[processor.getSequence()] = info;
        _consumerInfos ~= info;
    }

    void startAll(shared ThreadFactory threadFactory)
    {
        foreach (info; _consumerInfos)
            info.start(threadFactory);
    }

    void haltAll()
    {
        foreach (info; _consumerInfos)
            info.halt();
    }

    bool hasBacklog(long cursor, bool includeStopped)
    {
        foreach (info; _consumerInfos)
        {
            if ((includeStopped || info.isRunning()) && info.isEndOfChain())
            {
                foreach (seq; info.getSequences())
                {
                    if (cursor > seq.get())
                        return true;
                }
            }
        }
        return false;
    }

    shared(EventProcessor) getEventProcessorFor(shared EventHandlerIdentity handlerIdentity)
    {
        auto infoPtr = cast(EventHandlerIdentity)handlerIdentity in _infoByHandler;
        enforce(infoPtr !is null, "The event handler is not processing events.", __FILE__, __LINE__);
        return (*infoPtr).getEventProcessor();
    }

    shared(Sequence) getSequenceFor(shared EventHandlerIdentity handlerIdentity)
    {
        return getEventProcessorFor(handlerIdentity).getSequence();
    }

    void unMarkEventProcessorsAsEndOfChain(shared Sequence[] barrierEventProcessors)
    {
        foreach (seq; barrierEventProcessors)
        {
            auto infoPtr = seq in _infoBySequence;
            if (infoPtr !is null)
                (*infoPtr).markAsUsedInBarrier();
        }
    }

    shared(SequenceBarrier) getBarrierFor(shared EventHandlerIdentity handlerIdentity)
    {
        auto infoPtr = cast(EventHandlerIdentity)handlerIdentity in _infoByHandler;
        return infoPtr !is null ? (*infoPtr).getBarrier() : null;
    }
}


unittest
{
    import disruptor.eventhandler : EventHandler;
    import core.thread : Thread;

    class StubHandler : EventHandler!int
    {
        override void onEvent(int evt, long seq, bool endOfBatch) shared {}
    }

    class StubProcessor : EventProcessor
    {
        private shared Sequence seq;
        private shared bool running;

        this() shared
        {
            seq = new shared Sequence();
        }

        override void run() shared { running = true; }
        override shared(Sequence) getSequence() shared { return seq; }
        override void halt() shared { running = false; }
        override bool isRunning() shared { return running; }
    }

    class StubThreadFactory : ThreadFactory
    {
        shared Thread[] threads;
        override Thread newThread(void delegate() r) shared
        {
            auto t = new Thread(r);
            threads ~= cast(shared) t;
            return t;
        }
    }
    auto repo = new ConsumerRepository();
    auto handler = new shared StubHandler();
    auto processor = new shared StubProcessor();
    repo.add(processor, handler, null);

    assert(repo.getEventProcessorFor(handler) is processor);
    assert(repo.getSequenceFor(handler) is processor.getSequence());
}

unittest
{
    import disruptor.eventhandler : EventHandler;
    import core.thread : Thread;
    class StubHandler : EventHandler!int
    {
        override void onEvent(int evt, long seq, bool endOfBatch) shared {}
    }

    class StubProcessor : EventProcessor
    {
        private shared Sequence seq;
        private shared bool running;
        this() shared { seq = new shared Sequence(); }
        override void run() shared { running = true; }
        override shared(Sequence) getSequence() shared { return seq; }
        override void halt() shared { running = false; }
        override bool isRunning() shared { return running; }
    }

    class StubThreadFactory : ThreadFactory
    {
        shared Thread[] threads;
        override Thread newThread(void delegate() r) shared
        {
            auto t = new Thread(r);
            threads ~= cast(shared) t;
            return t;
        }
    }


    auto repo = new ConsumerRepository();
    auto handler = new shared StubHandler();
    auto processor = new shared StubProcessor();
    repo.add(processor, handler, null);

    auto factory = new shared StubThreadFactory();
    repo.startAll(factory);
    foreach (t; factory.threads) (cast(Thread)t).join();
    assert(processor.isRunning());
    repo.haltAll();
    assert(!processor.isRunning());
}

unittest
{
    import disruptor.eventhandler : EventHandler;
    import core.thread : Thread;
    class StubHandler : EventHandler!int
    {
        override void onEvent(int evt, long seq, bool endOfBatch) shared {}
    }

    class StubProcessor : EventProcessor
    {
        private shared Sequence seq;
        private shared bool running;
        this() shared { seq = new shared Sequence(); }
        override void run() shared { running = true; }
        override shared(Sequence) getSequence() shared { return seq; }
        override void halt() shared { running = false; }
        override bool isRunning() shared { return running; }
    }

    class StubThreadFactory : ThreadFactory
    {
        shared Thread[] threads;
        override Thread newThread(void delegate() r) shared
        {
            auto t = new Thread(r);
            threads ~= cast(shared) t;
            return t;
        }
    }

    auto repo = new ConsumerRepository();
    auto handler1 = new shared StubHandler();
    auto handler2 = new shared StubHandler();
    auto p1 = new shared StubProcessor();
    auto p2 = new shared StubProcessor();
    repo.add(p1, handler1, null);
    repo.add(p2, handler2, null);

    auto factory = new shared StubThreadFactory();
    repo.startAll(factory);
    foreach (t; factory.threads) (cast(Thread)t).join();

    p1.getSequence().set(8);
    p2.getSequence().set(10);
    long cursor = 10;

    assert(repo.hasBacklog(cursor, false));
    p1.halt();
    assert(!repo.hasBacklog(cursor, false));
    assert(repo.hasBacklog(cursor, true));
}

