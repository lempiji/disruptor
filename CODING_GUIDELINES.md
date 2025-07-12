# D Porting Conventions

This repository includes a D port of the Disruptor. When migrating Java code to D, follow these conventions to maintain consistency with the existing code base.

- **Propagate context in exceptions** – include `__FILE__` and `__LINE__` in exception constructors, mirroring the D standard library behavior.
- **Run tests during migration** – execute `dub test` (or equivalent) whenever migrating code.
- **Migrate incrementally** – port code one class at a time and keep tests alongside each migrated class.
- **Expose modules** – add new modules to `package.d` so they are easily importable.
- **Organize imports** – group all `public import` statements together at the start of each file.
- **Use selective imports** – prefer `import module : symbol;` to remove unnecessary imports.
- **Apply attributes** – mark functions and variables with attributes such as `shared`, `nothrow`, `@safe`, `in`, and others where appropriate.
- **Use `shared` consistently** – apply the qualifier to methods and interface definitions that operate on shared instances (e.g., `long get() const shared`). Provide dedicated `this() shared` constructors or factory functions so objects can be created in a shared state without casts. Parameters and local variables referencing shared objects should also use the `shared` type qualifier (e.g., `shared Sequence[]`). Initialize shared objects with `new shared Type(...)`. See `sequence.d`, `sequencegroup.d`, `processingsequencebarrier.d`, `sequencer.d`, and `ringbuffer.d` for examples.
- **Avoid `cast(shared)`** – rather than casting, provide constructors or helper functions that return properly `shared` objects. For example, `ProcessingSequenceBarrier`'s constructors should initialize all shared fields without any casting.

Following these practices will help maintain clarity and quality as the code base evolves.
