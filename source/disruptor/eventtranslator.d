module disruptor.eventtranslator;

/// Interfaces for translating data representations into events.

interface EventTranslator(T)
{
    /// Translate data into the given event for the specified sequence.
    void translateTo(T event, long sequence);
}

interface EventTranslatorOneArg(T, A)
{
    void translateTo(T event, long sequence, A arg0);
}

interface EventTranslatorTwoArg(T, A, B)
{
    void translateTo(T event, long sequence, A arg0, B arg1);
}

interface EventTranslatorThreeArg(T, A, B, C)
{
    void translateTo(T event, long sequence, A arg0, B arg1, C arg2);
}

/// Vararg translator accepting an arbitrary list of arguments.
interface EventTranslatorVararg(T)
{
    void translateTo(Args...)(T event, long sequence, Args args);
}

unittest
{
    class MyEvent { int value; }

    class MyTranslator : EventTranslator!MyEvent
    {
        override void translateTo(MyEvent event, long sequence)
        {
            event.value = cast(int)sequence;
        }
    }

    auto e = new MyEvent();
    auto t = new MyTranslator();
    t.translateTo(e, 7);
    assert(e.value == 7);

    class MyOneArg : EventTranslatorOneArg!(MyEvent, int)
    {
        override void translateTo(MyEvent event, long sequence, int arg0)
        {
            event.value = arg0;
        }
    }

    auto t1 = new MyOneArg();
    t1.translateTo(e, 1, 42);
    assert(e.value == 42);

    class MyVararg : EventTranslatorVararg!MyEvent
    {
        void translateTo(Args...)(MyEvent event, long sequence, Args args)
        {
            static if (Args.length > 0 && is(typeof(args[0]) == int))
                event.value = args[0];
        }
    }

    auto tv = new MyVararg();
    tv.translateTo(e, 2, 5);
    assert(e.value == 5);
}
