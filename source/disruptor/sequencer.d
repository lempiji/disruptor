module disruptor.sequencer;

import disruptor.sequence;

interface Cursored
{
    long getCursor();
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
    long waitFor(long sequence);
    long getCursor();
    bool isAlerted();
    void alert();
    void clearAlert();
    void checkAlert();
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
    bool isAvailable(long sequence);
    void addGatingSequences(Sequence[] gatingSequences...);
    bool removeGatingSequence(Sequence sequence);
    SequenceBarrier newBarrier(Sequence[] sequencesToTrack...);
    long getMinimumSequence();
    long getHighestPublishedSequence(long nextSequence, long availableSequence);
    EventPoller!T newPoller(T)(DataProvider!T provider, Sequence[] gatingSequences...);
}
