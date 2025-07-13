module disruptor.batcheventprocessor;

import core.atomic : MemoryOrder, atomicLoad, atomicStore, cas, atomicOp;
import std.algorithm : min;
import disruptor.sequence : Sequence;
import disruptor.sequencer : DataProvider, SequenceBarrier;
import disruptor.eventprocessor : EventProcessor;
import disruptor.timeoutexception : TimeoutException;
import disruptor.processingsequencebarrier : AlertException;
import disruptor.ringbuffer : RingBuffer; // for unittests
import disruptor.rewindableexception : RewindableException;
import disruptor.rewindhandler : RewindHandler;
import disruptor.batchrewindstrategy : BatchRewindStrategy;
import disruptor.simplebatchrewindstrategy : SimpleBatchRewindStrategy;
import disruptor.rewindaction : RewindAction;
import disruptor.rewindableeventhandler : RewindableEventHandler;
import disruptor.eventhandler : EventHandler, EventHandlerBase;
import disruptor.exceptionhandlers : ExceptionHandlers;

/// Callback handler for uncaught exceptions in the event loop.
interface ExceptionHandler(T)
{
    void handleEventException(Throwable ex, long sequence, shared(T) event) shared;
    void handleOnStartException(Throwable ex) shared;
    void handleOnShutdownException(Throwable ex) shared;
}

/// Default exception handler that simply ignores all exceptions.
class IgnoreExceptionHandler(T) : ExceptionHandler!T
{
    override void handleEventException(Throwable ex, long sequence, shared(T) event) shared {}
    override void handleOnStartException(Throwable ex) shared {}
    override void handleOnShutdownException(Throwable ex) shared {}
}

/// States the processor can be in.
enum RunningState : int
{
    IDLE = 0,
    HALTED = 1,
    RUNNING = 2
}

/**
 * Convenience class for handling the batching semantics of consuming entries
 * from a RingBuffer and delegating to an EventHandler.
 */
class BatchEventProcessor(T) : EventProcessor
{
private:
    shared(DataProvider!T) _dataProvider;
    shared SequenceBarrier _sequenceBarrier;
    shared(EventHandlerBase!T) _eventHandler;
    shared Sequence _sequence;
    shared(ExceptionHandler!T) _exceptionHandler;
    shared int _running = RunningState.IDLE;
    shared int _batchLimitOffset;
    shared(RewindHandler) _rewindHandler;
    shared int _retriesAttempted = 0;

public:
    this(shared DataProvider!T dataProvider,
         shared SequenceBarrier sequenceBarrier,
         shared EventHandlerBase!T eventHandler,
         int maxBatchSize,
         shared BatchRewindStrategy rewindStrategy = null)
    {
        this._dataProvider = dataProvider;
        this._sequenceBarrier = sequenceBarrier;
        this._eventHandler = eventHandler;
        this._sequence = new shared Sequence(Sequence.INITIAL_VALUE);
        this._exceptionHandler = null;
        if (maxBatchSize < 1)
            throw new Exception("maxBatchSize must be greater than 0", __FILE__, __LINE__);
        this._batchLimitOffset = maxBatchSize - 1;
        if (cast(RewindableEventHandler!T)eventHandler !is null)
        {
            if (rewindStrategy is null)
                rewindStrategy = new shared SimpleBatchRewindStrategy();
            this._rewindHandler = new shared TryRewindHandler(cast(shared) this, rewindStrategy);
        }
        else
        {
            this._rewindHandler = new shared NoRewindHandler();
        }
    }

    this(shared DataProvider!T dataProvider,
         shared SequenceBarrier sequenceBarrier,
         shared EventHandlerBase!T eventHandler,
         int maxBatchSize,
         shared BatchRewindStrategy rewindStrategy = null) shared
    {
        this._dataProvider = dataProvider;
        this._sequenceBarrier = sequenceBarrier;
        this._eventHandler = eventHandler;
        this._sequence = new shared Sequence(Sequence.INITIAL_VALUE);
        this._exceptionHandler = null;
        if (maxBatchSize < 1)
            throw new Exception("maxBatchSize must be greater than 0", __FILE__, __LINE__);
        this._batchLimitOffset = maxBatchSize - 1;
        if (cast(RewindableEventHandler!T)eventHandler !is null)
        {
            if (rewindStrategy is null)
                rewindStrategy = new shared SimpleBatchRewindStrategy();
            this._rewindHandler = new shared TryRewindHandler(this, rewindStrategy);
        }
        else
        {
            this._rewindHandler = new shared NoRewindHandler();
        }
    }

    override shared(Sequence) getSequence() shared
    {
        return _sequence;
    }

    override void halt() shared
    {
        atomicStore!(MemoryOrder.rel)(_running, RunningState.HALTED);
        _sequenceBarrier.alert();
    }

    override bool isRunning() shared
    {
        return atomicLoad!(MemoryOrder.acq)(_running) != RunningState.IDLE;
    }

    /// Set a custom ExceptionHandler for handling uncaught exceptions.
    void setExceptionHandler(shared(ExceptionHandler!T) handler) shared
    {
        if (handler is null)
            throw new Exception("ExceptionHandler must not be null", __FILE__, __LINE__);
        _exceptionHandler = handler;
    }

    override void run() shared
    {
        int expected = RunningState.IDLE;
        if (!cas(&_running, expected, RunningState.RUNNING))
        {
            if (expected == RunningState.RUNNING)
                throw new Exception("Thread is already running", __FILE__, __LINE__);
            else
            {
                notifyStart();
                notifyShutdown();
                return;
            }
        }

        _sequenceBarrier.clearAlert();
        notifyStart();
        scope(exit)
        {
            notifyShutdown();
            atomicStore!(MemoryOrder.rel)(_running, RunningState.IDLE);
        }

        if (atomicLoad!(MemoryOrder.acq)(_running) == RunningState.RUNNING)
        {
            processEvents();
        }
    }

private:
    void processEvents() shared
    {
        shared(T) event;
        long nextSequence = _sequence.get() + 1;

        while (true)
        {
            long startOfBatchSequence = nextSequence;
            try
            {
                try
                {
                    long availableSequence = _sequenceBarrier.waitFor(nextSequence);
                    long endOfBatchSequence = min(nextSequence + _batchLimitOffset, availableSequence);

                    if (nextSequence <= endOfBatchSequence)
                    {
                        _eventHandler.onBatchStart(endOfBatchSequence - nextSequence + 1,
                                              availableSequence - nextSequence + 1);
                    }

                    while (nextSequence <= endOfBatchSequence)
                    {
                        event = _dataProvider.get(nextSequence);
                        _eventHandler.onEvent(cast(T)event, nextSequence, nextSequence == endOfBatchSequence);
                        nextSequence++;
                    }

                    _retriesAttempted = 0;
                    _sequence.set(endOfBatchSequence);
                }
                catch (RewindableException e)
                {
                    nextSequence = _rewindHandler.attemptRewindGetNextSequence(e, startOfBatchSequence);
                }
            }
            catch (TimeoutException)
            {
                notifyTimeout(_sequence.get());
            }
            catch (AlertException)
            {
                if (atomicLoad!(MemoryOrder.acq)(_running) != RunningState.RUNNING)
                    break;
            }
            catch (Throwable ex)
            {
                handleEventException(ex, nextSequence, event);
                _sequence.set(nextSequence);
                nextSequence++;
            }
        }
    }

    void notifyTimeout(long sequence) shared
    {
        try
        {
            _eventHandler.onTimeout(sequence);
        }
        catch (Throwable ex)
        {
            handleEventException(ex, sequence, null);
        }
    }

    void notifyStart() shared
    {
        try
        {
            _eventHandler.onStart();
        }
        catch (Throwable ex)
        {
            handleOnStartException(ex);
        }
    }

    void notifyShutdown() shared
    {
        try
        {
            _eventHandler.onShutdown();
        }
        catch (Throwable ex)
        {
            handleOnShutdownException(ex);
        }
    }

    void handleEventException(Throwable ex, long sequence, shared(T) event) shared
    {
        getExceptionHandler().handleEventException(ex, sequence, event);
    }

    void handleOnStartException(Throwable ex) shared
    {
        getExceptionHandler().handleOnStartException(ex);
    }

    void handleOnShutdownException(Throwable ex) shared
    {
        getExceptionHandler().handleOnShutdownException(ex);
    }

    shared(ExceptionHandler!T) getExceptionHandler() shared
    {
        auto handler = _exceptionHandler;
        return handler is null ? ExceptionHandlers.defaultHandler!T() : handler;
    }

    static class TryRewindHandler : RewindHandler
    {
        shared BatchEventProcessor!T _outer;
        shared BatchRewindStrategy _strategy;
        this(shared BatchEventProcessor!T outer, shared BatchRewindStrategy strategy) shared
        {
            _outer = outer;
            _strategy = strategy;
        }

        override long attemptRewindGetNextSequence(RewindableException e, long startOfBatchSequence) shared
        {
            if (_strategy.handleRewindException(e, atomicOp!"+="(_outer._retriesAttempted, 1)) == RewindAction.REWIND)
            {
                return startOfBatchSequence;
            }
            else
            {
                _outer._retriesAttempted = 0;
                throw e;
            }
        }
    }

    static class NoRewindHandler : RewindHandler
    {
        override long attemptRewindGetNextSequence(RewindableException e, long startOfBatchSequence) shared
        {
            throw new Exception("Rewindable Exception thrown from a non-rewindable event handler", __FILE__, __LINE__, e);
        }
    }
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import core.thread : Thread;
    import core.time : msecs;

    class StubEvent { int value; }

    class CountingHandler : EventHandlerBase!StubEvent
    {
        shared int count;
        override void onEvent(StubEvent evt, long seq, bool endOfBatch) shared
        {
            import core.atomic : atomicOp;
            atomicOp!"+="(count, 1);
        }
    }

    auto rb = RingBuffer!StubEvent.createSingleProducer(() => new shared StubEvent(), 4, new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto handler = new shared CountingHandler();
    auto processor = new shared BatchEventProcessor!StubEvent(rb, barrier, handler, 16);
    rb.addGatingSequences(processor.getSequence());

    // publish events
    foreach (i; 0 .. 3)
        rb.publish(rb.next());

    auto t = new Thread({ processor.run(); });
    t.start();
    Thread.sleep(100.msecs);
    processor.halt();
    t.join();

    assert(handler.count == 3);
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import core.thread : Thread;
    import core.time : msecs;

    class StubEvent { int value; }

    class ExceptionThrower : EventHandlerBase!StubEvent
    {
        override void onEvent(StubEvent evt, long seq, bool endOfBatch) shared
        {
            throw new Exception("boom");
        }
    }

    class LatchExceptionHandler : ExceptionHandler!StubEvent
    {
        shared int calls;
        override void handleEventException(Throwable ex, long sequence, shared(StubEvent) event) shared
        {
            import core.atomic : atomicOp;
            atomicOp!"+="(calls, 1);
        }
        override void handleOnStartException(Throwable ex) shared {}
        override void handleOnShutdownException(Throwable ex) shared {}
    }

    auto rb = RingBuffer!StubEvent.createSingleProducer(() => new shared StubEvent(), 4, new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto handler = new shared ExceptionThrower();
    auto processor = new shared BatchEventProcessor!StubEvent(rb, barrier, handler, 16);
    auto exc = new shared LatchExceptionHandler();
    processor.setExceptionHandler(exc);
    rb.addGatingSequences(processor.getSequence());
    rb.publish(rb.next());
    auto t = new Thread({ processor.run(); });
    t.start();
    Thread.sleep(50.msecs);
    processor.halt();
    t.join();
    assert(exc.calls == 1);
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import core.thread : Thread;
    import core.time : msecs;

    enum MAX_BATCH_SIZE = 3;
    enum PUBLISH_COUNT = 5;

    class StubEvent { int value; }

    class BatchLimitRecordingHandler : EventHandlerBase!StubEvent
    {
        long[][] batchedSequences;
        long[] announcedBatchSizes;
        long[] announcedQueueDepths;
        long[] current;

        override void onEvent(StubEvent evt, long seq, bool endOfBatch) shared
        {
            current ~= seq;
            if (endOfBatch)
            {
                batchedSequences ~= current;
                current = null;
            }
        }

        override void onBatchStart(long batchSize, long queueDepth) shared @safe nothrow
        {
            current = [];
            announcedBatchSizes ~= batchSize;
            announcedQueueDepths ~= queueDepth;
        }
    }

    auto rb = RingBuffer!StubEvent.createSingleProducer(() => new shared StubEvent(), 16, new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto handler = new BatchLimitRecordingHandler();
    auto processor = new shared BatchEventProcessor!StubEvent(rb, barrier, cast(shared)handler, MAX_BATCH_SIZE);
    rb.addGatingSequences(processor.getSequence());

    // publish events
    foreach(i; 0 .. PUBLISH_COUNT)
        rb.publish(rb.next());

    auto t = new Thread({ processor.run(); });
    t.start();
    Thread.sleep(100.msecs);
    processor.halt();
    t.join();

    assert(handler.batchedSequences.length == 2);
    assert(handler.batchedSequences[0] == [0L, 1L, 2L]);
    assert(handler.batchedSequences[1] == [3L, 4L]);
    assert(handler.announcedBatchSizes == [3L, 2L]);
    assert(handler.announcedQueueDepths == [5L, 2L]);
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import core.thread : Thread;
    import core.time : msecs;

    class StubEvent { int value; }

    class RewindingHandler : RewindableEventHandler!StubEvent
    {
        shared BatchEventProcessor!StubEvent processor;
        shared int calls;

        override void onEvent(StubEvent evt, long seq, bool endOfBatch) shared
        {
            import core.atomic : atomicOp;
            if (atomicOp!"+="(calls, 1) == 1)
                throw new RewindableException();
            processor.halt();
        }
    }

    auto rb = RingBuffer!StubEvent.createSingleProducer(() => new shared StubEvent(), 4, new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto handler = new shared RewindingHandler();
    auto processor = new shared BatchEventProcessor!StubEvent(cast(shared DataProvider!StubEvent)rb, barrier, cast(shared)handler, 16, new shared SimpleBatchRewindStrategy());
    handler.processor = processor;
    rb.addGatingSequences(processor.getSequence());
    rb.publish(rb.next());

    auto t = new Thread({ processor.run(); });
    t.start();
    t.join();

    assert(handler.calls == 2);
}
