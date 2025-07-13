module disruptor.sequencer;

import disruptor.sequence;
public import disruptor.eventpoller;

interface Cursored
{
    long getCursor() shared;
}

interface Sequenced
{
    int getBufferSize();
    bool hasAvailableCapacity(int requiredCapacity) shared;
    long remainingCapacity() shared;
    long next() shared;
    long next(int n) shared;
    long tryNext() shared;
    long tryNext(int n) shared;
    void publish(long sequence) shared;
    void publish(long lo, long hi) shared;
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
    shared(T) get(long sequence) shared;
}


interface Sequencer : Cursored, Sequenced
{
    enum long INITIAL_CURSOR_VALUE = -1;

    void claim(long sequence) shared;
    bool isAvailable(long sequence) shared;
    void addGatingSequences(shared Sequence[] gatingSequences...) shared;
    bool removeGatingSequence(shared Sequence sequence) shared;
    shared(SequenceBarrier) newBarrier(shared Sequence[] sequencesToTrack...) shared;
    long getMinimumSequence() shared;
    long getHighestPublishedSequence(long nextSequence, long availableSequence) shared;
    /// Create a new {@link EventPoller} bound to this sequencer.
    shared(EventPoller!T) newPoller(T)(shared DataProvider!T provider,
                                        shared Sequence[] gatingSequences...) shared;
}
