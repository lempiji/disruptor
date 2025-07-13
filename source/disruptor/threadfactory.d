module disruptor.threadfactory;

import core.thread : Thread;

/// Delegate used to create new threads for event processors.
alias ThreadFactory = Thread delegate(void delegate() runnable);
