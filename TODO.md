# Porting Disruptor from Java to D

This repository contains both the original Java implementation and a nascent D port. The long term goal is to replace the Java code with a fully featured D version while keeping feature parity.

## Migration goals
- Port the core Disruptor library from Java to D.
- Maintain API parity so existing examples and documentation remain useful.
- Provide D unit tests that mirror the current Java tests.
- Establish continuous integration running `dub test` on GitHub Actions.

## Java modules to port
The Java sources under `src/main/java/com/lmax/disruptor` form the reference implementation. Key areas to translate include:

1. **Ring buffer and sequencing**
   - `RingBuffer`
   - `Sequence`, `Sequencer`, `SingleProducerSequencer`, `MultiProducerSequencer`
   - `SequenceBarrier`, `SequenceGroup`
2. **Event processing infrastructure**
   - `EventProcessor`, `BatchEventProcessor`, `EventHandler` and related translator interfaces
   - Exception handlers and rewind logic
3. **Wait strategies**
   - `BusySpinWaitStrategy`, `SleepingWaitStrategy`, `BlockingWaitStrategy`, etc.
4. **DSL and support classes**
   - Classes under `dsl` such as `Disruptor`, `EventHandlerGroup`, `ProducerType`
5. **Utilities**
   - Threading helpers and `Util` classes under `util`

## Tasks
- [ ] Translate the modules listed above to D, starting with the ring buffer and sequencing logic.
- [ ] Write D unit tests mirroring the Java tests in `src/test/java`.
- [ ] Configure GitHub Actions to run `dub test` for the D build.
