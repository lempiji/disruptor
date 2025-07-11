module disruptor.sequencer;

import disruptor.sequence;

interface Cursored
{
    long getCursor() shared;
}

interface Sequenced
{
    int getBufferSize();
    bool hasAvailableCapacity(int requiredCapacity);
    long remainingCapacity();
    long next();
    long next(int n);
    long tryNext();
    long tryNext(int n);
    void publish(long sequence);
    void publish(long lo, long hi);
}

interface SequenceBarrier
{
    long waitFor(long sequence) shared;
    long getCursor() shared;
    bool isAlerted() shared;
    void alert() shared;
    void clearAlert() shared;
    void checkAlert() shared;
}

interface DataProvider(T)
{
    T get(long sequence);
}

class EventPoller(T)
{
    // placeholder class
}

interface Sequencer : Cursored, Sequenced
{
    enum long INITIAL_CURSOR_VALUE = -1;

    void claim(long sequence);
    bool isAvailable(long sequence) shared;
    void addGatingSequences(shared Sequence[] gatingSequences...) shared;
    bool removeGatingSequence(shared Sequence sequence) shared;
    SequenceBarrier newBarrier(shared Sequence[] sequencesToTrack...) shared;
    long getMinimumSequence();
    long getHighestPublishedSequence(long nextSequence, long availableSequence) shared;
    EventPoller!T newPoller(T)(DataProvider!T provider, shared Sequence[] gatingSequences...);
}
