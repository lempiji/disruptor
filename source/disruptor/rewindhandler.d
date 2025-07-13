module disruptor.rewindhandler;

import disruptor.rewindableexception : RewindableException;

/// Handler used to attempt rewinding when a RewindableException occurs.
interface RewindHandler
{
    long attemptRewindGetNextSequence(RewindableException e, long startOfBatchSequence) shared;
}

