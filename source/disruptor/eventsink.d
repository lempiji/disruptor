module disruptor.eventsink;

public import disruptor.eventtranslator;

/// Write interface for a ring buffer.
interface EventSink(E)
{
    void publishEvent(EventTranslator!E translator);
    bool tryPublishEvent(EventTranslator!E translator);

    void publishEvent(A)(EventTranslatorOneArg!(E, A) translator, A arg0);
    bool tryPublishEvent(A)(EventTranslatorOneArg!(E, A) translator, A arg0);

    void publishEvent(A, B)(EventTranslatorTwoArg!(E, A, B) translator, A arg0, B arg1);
    bool tryPublishEvent(A, B)(EventTranslatorTwoArg!(E, A, B) translator, A arg0, B arg1);

    void publishEvent(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, A arg0, B arg1, C arg2);
    bool tryPublishEvent(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, A arg0, B arg1, C arg2);

    void publishEvent(Args...)(EventTranslatorVararg!E translator, Args args);
    bool tryPublishEvent(Args...)(EventTranslatorVararg!E translator, Args args);

    void publishEvents(EventTranslator!E[] translators);
    void publishEvents(EventTranslator!E[] translators, int batchStartsAt, int batchSize);
    bool tryPublishEvents(EventTranslator!E[] translators);
    bool tryPublishEvents(EventTranslator!E[] translators, int batchStartsAt, int batchSize);

    void publishEvents(A)(EventTranslatorOneArg!(E, A) translator, A[] arg0);
    void publishEvents(A)(EventTranslatorOneArg!(E, A) translator, int batchStartsAt, int batchSize, A[] arg0);
    bool tryPublishEvents(A)(EventTranslatorOneArg!(E, A) translator, A[] arg0);
    bool tryPublishEvents(A)(EventTranslatorOneArg!(E, A) translator, int batchStartsAt, int batchSize, A[] arg0);

    void publishEvents(A, B)(EventTranslatorTwoArg!(E, A, B) translator, A[] arg0, B[] arg1);
    void publishEvents(A, B)(EventTranslatorTwoArg!(E, A, B) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1);
    bool tryPublishEvents(A, B)(EventTranslatorTwoArg!(E, A, B) translator, A[] arg0, B[] arg1);
    bool tryPublishEvents(A, B)(EventTranslatorTwoArg!(E, A, B) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1);

    void publishEvents(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, A[] arg0, B[] arg1, C[] arg2);
    void publishEvents(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1, C[] arg2);
    bool tryPublishEvents(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, A[] arg0, B[] arg1, C[] arg2);
    bool tryPublishEvents(A, B, C)(EventTranslatorThreeArg!(E, A, B, C) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1, C[] arg2);

    void publishEvents(Args...)(EventTranslatorVararg!E translator, Args[] args);
    void publishEvents(Args...)(EventTranslatorVararg!E translator, int batchStartsAt, int batchSize, Args[] args);
    bool tryPublishEvents(Args...)(EventTranslatorVararg!E translator, Args[] args);
    bool tryPublishEvents(Args...)(EventTranslatorVararg!E translator, int batchStartsAt, int batchSize, Args[] args);
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
        override void publishEvent(EventTranslator!MyEvent translator) {}
        override bool tryPublishEvent(EventTranslator!MyEvent translator) { return true; }
        void publishEvent(A)(EventTranslatorOneArg!(MyEvent, A) translator, A arg0) {}
        bool tryPublishEvent(A)(EventTranslatorOneArg!(MyEvent, A) translator, A arg0) { return true; }
        void publishEvent(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, A arg0, B arg1) {}
        bool tryPublishEvent(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, A arg0, B arg1) { return true; }
        void publishEvent(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, A arg0, B arg1, C arg2) {}
        bool tryPublishEvent(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, A arg0, B arg1, C arg2) { return true; }
        void publishEvent(Args...)(EventTranslatorVararg!MyEvent translator, Args args) {}
        bool tryPublishEvent(Args...)(EventTranslatorVararg!MyEvent translator, Args args) { return true; }
        override void publishEvents(EventTranslator!MyEvent[] translators) {}
        override void publishEvents(EventTranslator!MyEvent[] translators, int batchStartsAt, int batchSize) {}
        override bool tryPublishEvents(EventTranslator!MyEvent[] translators) { return true; }
        override bool tryPublishEvents(EventTranslator!MyEvent[] translators, int batchStartsAt, int batchSize) { return true; }
        void publishEvents(A)(EventTranslatorOneArg!(MyEvent, A) translator, A[] arg0) {}
        void publishEvents(A)(EventTranslatorOneArg!(MyEvent, A) translator, int batchStartsAt, int batchSize, A[] arg0) {}
        bool tryPublishEvents(A)(EventTranslatorOneArg!(MyEvent, A) translator, A[] arg0) { return true; }
        bool tryPublishEvents(A)(EventTranslatorOneArg!(MyEvent, A) translator, int batchStartsAt, int batchSize, A[] arg0) { return true; }
        void publishEvents(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, A[] arg0, B[] arg1) {}
        void publishEvents(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1) {}
        bool tryPublishEvents(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, A[] arg0, B[] arg1) { return true; }
        bool tryPublishEvents(A,B)(EventTranslatorTwoArg!(MyEvent, A, B) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1) { return true; }
        void publishEvents(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, A[] arg0, B[] arg1, C[] arg2) {}
        void publishEvents(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1, C[] arg2) {}
        bool tryPublishEvents(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, A[] arg0, B[] arg1, C[] arg2) { return true; }
        bool tryPublishEvents(A,B,C)(EventTranslatorThreeArg!(MyEvent, A, B, C) translator, int batchStartsAt, int batchSize, A[] arg0, B[] arg1, C[] arg2) { return true; }
        void publishEvents(Args...)(EventTranslatorVararg!MyEvent translator, Args[] args) {}
        void publishEvents(Args...)(EventTranslatorVararg!MyEvent translator, int batchStartsAt, int batchSize, Args[] args) {}
        bool tryPublishEvents(Args...)(EventTranslatorVararg!MyEvent translator, Args[] args) { return true; }
        bool tryPublishEvents(Args...)(EventTranslatorVararg!MyEvent translator, int batchStartsAt, int batchSize, Args[] args) { return true; }
    }

    auto sink = new DummySink();
    sink.publishEvent(new NoopTranslator());
}
