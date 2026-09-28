# Program design sketch

The shape of the code before anyone writes it. Architecture is too high for this level, and an agent will otherwise decide it implicitly during implementation, at the most expensive time to change. Light visualizations in pseudocode:

- **Types and method signatures** for the key new functions. The stuff too internal for architecture that an agent might still get wrong.
- **One line per new module** naming its data shape and the structure that organizes it (a state machine over scattered booleans, a table or registry over branching, a typed model over repeated shape assumptions).
- **Seams.** Where the tests will sit: the public interface each test exercises.
- **Call-stack trees** only for a control-flow change that prose leaves ambiguous. Diff syntax (`+` and `-` lines) when the interesting part is what's changing.

Sketch the interfaces; leave the wiring inside them to the implementer.
