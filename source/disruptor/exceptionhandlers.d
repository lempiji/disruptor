module disruptor.exceptionhandlers;

import disruptor.fatalexceptionhandler : FatalExceptionHandler;
import disruptor.batcheventprocessor : ExceptionHandler;

/// Provides access to a shared default ExceptionHandler instance.
struct ExceptionHandlers
{
    static shared(ExceptionHandler!T) defaultHandler(T)()
    {
        static shared FatalExceptionHandler!T handler;
        if (handler is null)
        {
            handler = new shared FatalExceptionHandler!T();
        }
        return handler;
    }
}

unittest
{
    static struct TestEvent { int value; }
    auto first = ExceptionHandlers.defaultHandler!TestEvent();
    auto second = ExceptionHandlers.defaultHandler!TestEvent();
    assert(first is second);
}
