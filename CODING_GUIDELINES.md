# D Porting Conventions

This repository includes a D port of the Disruptor. When migrating Java code to D, follow these conventions to maintain consistency with the existing code base.

- **Propagate context in exceptions** – include `__FILE__` and `__LINE__` in exception constructors, mirroring the D standard library behavior.
- **Run tests during migration** – execute `dub test` (or equivalent) whenever migrating code.
- **Migrate incrementally** – port code one class at a time and keep tests alongside each migrated class.
- **Expose modules** – add new modules to `package.d` so they are easily importable.
- **Organize imports** – group all `public import` statements together at the start of each file.
- **Use selective imports** – prefer `import module : symbol;` to remove unnecessary imports.
- **Apply attributes** – mark functions and variables with attributes such as `shared`, `nothrow`, `@safe`, `in`, and others where appropriate.

Following these practices will help maintain clarity and quality as the code base evolves.
