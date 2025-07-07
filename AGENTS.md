## Project Contribution Guide

### Build and Test

1. **Java**: Use the Gradle wrapper. From the repository root run
   
   ```bash
   ./gradlew test
   ```
   This compiles the Java sources and runs the unit tests.

2. **D** (requires `dub` and a D compiler such as DMD or LDC):
   
   ```bash
   dub build
   dub test
   ```
   The build step creates the library, while `dub test` executes the D unit tests.

### Recommended Tools

- Java 11 or newer. The bundled Gradle wrapper will download an appropriate JDK if needed.
- A D compiler such as **DMD** or **LDC**.
- `dfmt` is recommended for formatting D source files.

### Commit Messages and Branching

- Work on a separate feature branch for each change.
- Use concise commit messages in the imperative mood (e.g., "Add feature" rather than "Added feature").
- Prefer squash merges when merging feature branches to keep history clean.


