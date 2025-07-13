module disruptor.fatalexceptionhandler;

import std.stdio : stderr, writefln;
import disruptor.batcheventprocessor : ExceptionHandler;

/// Exception handler that logs and rethrows fatal exceptions.
class FatalExceptionHandler(T) : ExceptionHandler!T
{
    override void handleEventException(Throwable ex, long sequence, shared(T) event) shared
    {
        stderr.writefln("Exception processing: %s %s", sequence, event);
        stderr.writefln("%s", ex.toString());
        throw new Exception("Fatal exception", __FILE__, __LINE__, ex);
    }

    override void handleOnStartException(Throwable ex) shared
    {
        stderr.writefln("Exception during onStart()");
        stderr.writefln("%s", ex.toString());
    }

    override void handleOnShutdownException(Throwable ex) shared
    {
        stderr.writefln("Exception during onShutdown()");
        stderr.writefln("%s", ex.toString());
    }
}

unittest
{
    static struct TestEvent { int value; }
    auto handler = new shared FatalExceptionHandler!TestEvent();
    auto cause = new Exception("boom");
    shared(TestEvent) ev = TestEvent();
    bool thrown;
    try
    {
        handler.handleEventException(cause, 1, ev);
    }
    catch (Exception e)
    {
        assert(e.next is cause);
        thrown = true;
    }
    assert(thrown);
}
