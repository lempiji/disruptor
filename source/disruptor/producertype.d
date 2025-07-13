module disruptor.producertype;

/// Defines producer types for RingBuffer creation.
enum ProducerType
{
    /// Single publisher only.
    SINGLE,
    /// Supports multiple concurrent publishers.
    MULTI
}
