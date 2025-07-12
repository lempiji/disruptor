module disruptor.eventsink;

public import disruptor.eventtranslator;

/// Write interface for a ring buffer.
interface EventSink(E)
{
    void publishEvent(EventTranslator!E translator) shared;
    bool tryPublishEvent(EventTranslator!E translator) shared;

    void publishEvent(A)(EventTranslatorOneArg!(E, A) translator, A arg0) shared;
    bool tryPublishEvent(A)(EventTranslatorOneArg!(E, A) translator, A arg0) shared;

    void publishEvent(A, B)(EventTranslatorTwoArg!(E, A, B) translator, A arg0, B arg1) shared;
    bool tryPublishEvent(A, B)(EventTranslatorTwoArg!(E, A, B) translator, A arg0, B arg1) shared;

    void publishEvent(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, A arg0, B arg1, C arg2) shared;
    bool tryPublishEvent(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, A arg0, B arg1, C arg2) shared;

    void publishEvent(Args...)(EventTranslatorVararg!E translator, Args args) shared;
    bool tryPublishEvent(Args...)(EventTranslatorVararg!E translator, Args args) shared;

    void publishEvents(EventTranslator!E[] translators) shared;
    void publishEvents(EventTranslator!E[] translators, int batchStartsAt, int batchSize) shared;
    bool tryPublishEvents(EventTranslator!E[] translators) shared;
    bool tryPublishEvents(EventTranslator!E[] translators, int batchStartsAt, int batchSize) shared;

    void publishEvents(A)(EventTranslatorOneArg!(E, A) translator, A[] arg0) shared;
    void publishEvents(A)(EventTranslatorOneArg!(E, A) translator, int batchStartsAt, int batchSize, A[] arg0) shared;
    bool tryPublishEvents(A)(EventTranslatorOneArg!(E, A) translator, A[] arg0) shared;
    bool tryPublishEvents(A)(EventTranslatorOneArg!(E, A) translator, int batchStartsAt, int batchSize, A[] arg0) shared;

    void publishEvents(A, B)(EventTranslatorTwoArg!(E, A, B) translator, A[] arg0, B[] arg1) shared;
    void publishEvents(A, B)(EventTranslatorTwoArg!(E, A, B) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1) shared;
    bool tryPublishEvents(A, B)(EventTranslatorTwoArg!(E, A, B) translator, A[] arg0, B[] arg1) shared;
    bool tryPublishEvents(A, B)(EventTranslatorTwoArg!(E, A, B) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1) shared;

    void publishEvents(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, A[] arg0, B[] arg1, C[] arg2) shared;
    void publishEvents(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1, C[] arg2) shared;
    bool tryPublishEvents(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, A[] arg0, B[] arg1, C[] arg2) shared;
    bool tryPublishEvents(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1, C[] arg2) shared;

    void publishEvents(Args...)(EventTranslatorVararg!E translator, Args[] args) shared;
    void publishEvents(Args...)(EventTranslatorVararg!E translator, int batchStartsAt, int batchSize, Args[] args) shared;
    bool tryPublishEvents(Args...)(EventTranslatorVararg!E translator, Args[] args) shared;
    bool tryPublishEvents(Args...)(EventTranslatorVararg!E translator, int batchStartsAt, int batchSize, Args[] args) shared;
}

unittest
{
    class MyEvent { int value; }

    class NoopTranslator : EventTranslator!MyEvent
    {
        override void translateTo(MyEvent event, long sequence) { event.value = 1; }
    }

    class DummySink : EventSink!MyEvent
    {
        override void publishEvent(EventTranslator!MyEvent translator) shared {}
        override bool tryPublishEvent(EventTranslator!MyEvent translator) shared { return true; }
        void publishEvent(A)(EventTranslatorOneArg!(MyEvent, A) translator, A arg0) shared {}
        bool tryPublishEvent(A)(EventTranslatorOneArg!(MyEvent, A) translator, A arg0) shared { return true; }
        void publishEvent(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, A arg0, B arg1) shared {}
        bool tryPublishEvent(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, A arg0, B arg1) shared { return true; }
        void publishEvent(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, A arg0, B arg1, C arg2) shared {}
        bool tryPublishEvent(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, A arg0, B arg1, C arg2) shared { return true; }
        void publishEvent(Args...)(EventTranslatorVararg!MyEvent translator, Args args) shared {}
        bool tryPublishEvent(Args...)(EventTranslatorVararg!MyEvent translator, Args args) shared { return true; }
        override void publishEvents(EventTranslator!MyEvent[] translators) shared {}
        override void publishEvents(EventTranslator!MyEvent[] translators, int batchStartsAt, int batchSize) shared {}
        override bool tryPublishEvents(EventTranslator!MyEvent[] translators) shared { return true; }
        override bool tryPublishEvents(EventTranslator!MyEvent[] translators, int batchStartsAt, int batchSize) shared { return true; }
        void publishEvents(A)(EventTranslatorOneArg!(MyEvent, A) translator, A[] arg0) shared {}
        void publishEvents(A)(EventTranslatorOneArg!(MyEvent, A) translator, int batchStartsAt, int batchSize, A[] arg0) shared {}
        bool tryPublishEvents(A)(EventTranslatorOneArg!(MyEvent, A) translator, A[] arg0) shared { return true; }
        bool tryPublishEvents(A)(EventTranslatorOneArg!(MyEvent, A) translator, int batchStartsAt, int batchSize, A[] arg0) shared { return true; }
        void publishEvents(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, A[] arg0, B[] arg1) shared {}
        void publishEvents(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1) shared {}
        bool tryPublishEvents(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, A[] arg0, B[] arg1) shared { return true; }
        bool tryPublishEvents(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1) shared { return true; }
        void publishEvents(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, A[] arg0, B[] arg1, C[] arg2) shared {}
        void publishEvents(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1, C[] arg2) shared {}
        bool tryPublishEvents(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, A[] arg0, B[] arg1, C[] arg2) shared { return true; }
        bool tryPublishEvents(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1, C[] arg2) shared { return true; }
        void publishEvents(Args...)(EventTranslatorVararg!MyEvent translator, Args[] args) shared {}
        void publishEvents(Args...)(EventTranslatorVararg!MyEvent translator, int batchStartsAt, int batchSize, Args[] args) shared {}
        bool tryPublishEvents(Args...)(EventTranslatorVararg!MyEvent translator, Args[] args) shared { return true; }
        bool tryPublishEvents(Args...)(EventTranslatorVararg!MyEvent translator, int batchStartsAt, int batchSize, Args[] args) shared { return true; }
    }

    auto sink = new shared DummySink();
    sink.publishEvent(new NoopTranslator());
}
