module disruptor.batcheventprocessor;

import core.atomic : MemoryOrder, atomicLoad, atomicStore, cas, atomicOp;
import std.algorithm : min;
import disruptor.sequencer : DataProvider, SequenceBarrier, Sequencer;
import disruptor.sequence : Sequence;
import disruptor.eventprocessor : EventProcessor;
import disruptor.processingsequencebarrier : AlertException;
import disruptor.timeoutexception : TimeoutException;

/// Exception type used to signal a batch should be rewound and reprocessed.
class RewindableException : Exception
{
    this(Throwable cause = null, string file = __FILE__, size_t line = __LINE__)
    {
        super("REWINDING BATCH", file, line, cause);
    }
}

/// Callback handler for uncaught exceptions in the event processing cycle.
interface ExceptionHandler(T)
{
    void handleEventException(Throwable ex, long sequence, shared(T) event) shared;
    void handleOnStartException(Throwable ex) shared;
    void handleOnShutdownException(Throwable ex) shared;
}

/// Basic exception handler that simply rethrows the exception.
class FatalExceptionHandler(T) : ExceptionHandler!T
{
    override void handleEventException(Throwable ex, long sequence, shared(T) event) shared
    {
        throw new Exception(ex.msg, __FILE__, __LINE__, ex);
    }

    override void handleOnStartException(Throwable ex) shared { }
    override void handleOnShutdownException(Throwable ex) shared { }
}

/// Event handler interface for consuming events from the ring buffer.
interface EventHandler(T)
{
    void onEvent(shared(T) event, long sequence, bool endOfBatch) shared; // may throw RewindableException
    void onStart() shared;
    void onShutdown() shared;
    void onTimeout(long sequence) shared;
    void onBatchStart(long batchSize, long queueDepth) shared;
}

/**
 * Convenience class for handling batches of events from a {@link RingBuffer}.
 */
class BatchEventProcessor(T) : EventProcessor
{
    enum int IDLE = 0;
    enum int HALTED = 1;
    enum int RUNNING = 2;

private:
    shared(DataProvider!T) _dataProvider;
    shared(SequenceBarrier) _sequenceBarrier;
    shared(EventHandler!T) _eventHandler;
    shared(ExceptionHandler!T) _exceptionHandler;
    shared Sequence _sequence;
    shared int _running = IDLE;

public:
    this(shared(DataProvider!T) dataProvider,
         shared SequenceBarrier barrier,
         shared(EventHandler!T) handler) shared
    {
        _dataProvider = dataProvider;
        _sequenceBarrier = barrier;
        _eventHandler = handler;
        _exceptionHandler = new shared FatalExceptionHandler!T();
        _sequence = new shared Sequence(Sequencer.INITIAL_CURSOR_VALUE);
    }

    /// Get the sequence being tracked by this processor.
    override shared(Sequence) getSequence() shared { return _sequence; }

    /// Signal the processor to stop when it reaches a safe point.
    override void halt() shared
    {
        atomicStore!(MemoryOrder.rel)(_running, HALTED);
        _sequenceBarrier.alert();
    }

    /// Whether the processor is currently running.
    override bool isRunning() shared
    {
        return atomicLoad!(MemoryOrder.acq)(_running) != IDLE;
    }

    /// Set a custom exception handler.
    void setExceptionHandler(shared(ExceptionHandler!T) handler) shared
    {
        _exceptionHandler = handler;
    }

    /// Main processing loop.
    override void run() shared
    {
        if (!cas(&_running, IDLE, RUNNING))
        {
            if (atomicLoad!(MemoryOrder.acq)(_running) == RUNNING)
                throw new Exception("Thread is already running");
            else
            {
                earlyExit();
                return;
            }
        }

        _sequenceBarrier.clearAlert();

        notifyStart();
        scope(exit)
        {
            notifyShutdown();
            atomicStore!(MemoryOrder.rel)(_running, IDLE);
        }

        if (atomicLoad!(MemoryOrder.acq)(_running) == RUNNING)
        {
            processEvents();
        }
    }

private:
    void processEvents() shared
    {
        long nextSequence = _sequence.get() + 1;

        while (true)
        {
            long startSequence = nextSequence;
            try
            {
                long availableSequence = _sequenceBarrier.waitFor(nextSequence);
                while (nextSequence <= availableSequence)
                {
                    auto evt = _dataProvider.get(nextSequence);
                    try
                    {
                        _eventHandler.onEvent(evt, nextSequence, nextSequence == availableSequence);
                        nextSequence++;
                    }
                    catch (RewindableException)
                    {
                        nextSequence = startSequence;
                        break;
                    }
                }
                if (nextSequence > availableSequence)
                {
                    _sequence.set(availableSequence);
                }
            }
            catch (TimeoutException)
            {
                notifyTimeout(_sequence.get());
            }
            catch (AlertException)
            {
                if (atomicLoad!(MemoryOrder.acq)(_running) != RUNNING)
                {
                    break;
                }
            }
            catch (Throwable ex)
            {
                auto evt = _dataProvider.get(nextSequence);
                handleEventException(ex, nextSequence, evt);
                _sequence.set(nextSequence);
                nextSequence++;
            }
        }
    }

    void earlyExit() shared
    {
        notifyStart();
        notifyShutdown();
    }

    void notifyTimeout(long seq) shared
    {
        try
        {
            _eventHandler.onTimeout(seq);
        }
        catch (Throwable e)
        {
            handleEventException(e, seq, null);
        }
    }

    void notifyStart() shared
    {
        try
        {
            _eventHandler.onStart();
        }
        catch (Throwable e)
        {
            handleOnStartException(e);
        }
    }

    void notifyShutdown() shared
    {
        try
        {
            _eventHandler.onShutdown();
        }
        catch (Throwable e)
        {
            handleOnShutdownException(e);
        }
    }

    void handleEventException(Throwable ex, long sequence, shared(T) event) shared
    {
        _exceptionHandler.handleEventException(ex, sequence, event);
    }

    void handleOnStartException(Throwable ex) shared
    {
        _exceptionHandler.handleOnStartException(ex);
    }

    void handleOnShutdownException(Throwable ex) shared
    {
        _exceptionHandler.handleOnShutdownException(ex);
    }
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import disruptor.ringbuffer : RingBuffer;
    import core.thread : Thread;
    import core.time : msecs;

    class TestEvent
    {
        long value;
    }

    class RecordingHandler : EventHandler!TestEvent
    {
        shared long[] processed;
        shared int count = 0;

        this() shared
        {
            processed = new shared long[](16);
        }

        override void onEvent(shared(TestEvent) evt, long sequence, bool endOfBatch) shared
        {
            auto idx = atomicOp!"+="(count, 1) - 1;
            processed[idx] = sequence;
        }
        override void onStart() shared {}
        override void onShutdown() shared {}
        override void onTimeout(long) shared {}
        override void onBatchStart(long, long) shared {}
    }

    auto rb = RingBuffer!TestEvent.createSingleProducer(() => new shared TestEvent(), 16, new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto handler = new shared RecordingHandler();
    auto processor = new shared BatchEventProcessor!(TestEvent)(rb, barrier, handler);
    rb.addGatingSequences(processor.getSequence());

    foreach(i; 0 .. 5)
    {
        auto seq = rb.next();
        rb.publish(seq);
    }

    auto t = new Thread({ processor.run(); });
    t.start();
    while(atomicLoad!(MemoryOrder.acq)(handler.count) < 5) Thread.sleep(10.msecs);
    processor.halt();
    t.join();

    foreach(i; 0 .. 5)
        assert(handler.processed[i] == i);
}

unittest
{
    import disruptor.blockingwaitstrategy : BlockingWaitStrategy;
    import disruptor.ringbuffer : RingBuffer;
    import core.thread : Thread;
    import core.time : msecs;

    class TestEvent
    {
        long value;
    }

    class DummyHandler : EventHandler!TestEvent
    {
        shared int count = 0;

        override void onEvent(shared(TestEvent) evt, long sequence, bool endOfBatch) shared
        {
            atomicOp!"+="(count, 1);
        }
        override void onStart() shared {}
        override void onShutdown() shared {}
        override void onTimeout(long) shared {}
        override void onBatchStart(long, long) shared {}
    }

    auto rb = RingBuffer!TestEvent.createSingleProducer(() => new shared TestEvent(), 16, new shared BlockingWaitStrategy());
    auto barrier = rb.newBarrier();
    auto handler = new shared DummyHandler();
    auto processor = new shared BatchEventProcessor!(TestEvent)(rb, barrier, handler);
    rb.addGatingSequences(processor.getSequence());

    auto seq = rb.next();
    rb.publish(seq);

    auto t = new Thread({ processor.run(); });
    t.start();
    while(atomicLoad!(MemoryOrder.acq)(handler.count) == 0) Thread.sleep(10.msecs);
    processor.halt();
    t.join();

    assert(!processor.isRunning());
}

