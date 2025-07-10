module disruptor.insufficientcapacityexception;

/// Exception thrown when the ring buffer lacks capacity.
class InsufficientCapacityException : Exception
{
    static __gshared InsufficientCapacityException INSTANCE;

    this(string msg = "Insufficient capacity", string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }

}

shared static this()
{
    InsufficientCapacityException.INSTANCE = new InsufficientCapacityException();
}
