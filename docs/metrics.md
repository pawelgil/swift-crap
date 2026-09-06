# crap-line-v1

For each authored callable, the score is `C² × (1 − L)³ + C`, where C is source cyclomatic complexity and L is measured function line coverage from 0 to 1. C starts at 1. An untested callable with complexity 5 scores 30; a fully executed callable with complexity 5 scores 5.

## Complexity

Each of these adds one decision:

- `if`, `guard`, `for`, `while`, `repeat`, and `catch`.
- Each non-default switch case clause.
- Each `&&`, `||`, `??`, and ternary expression.
- Each additional comma-separated condition in an `if`, `guard`, or `while`.
- A `for` loop's `where` clause.

Switch cases are counted even for exhaustive enum dispatch. Exhaustiveness does not verify that each case produces the correct result. `case a, b:` is one clause. `else` and `default` add no separate decision. `await` and `try` add no decision by themselves. This source-level convention is versioned; it is not claimed to reproduce every compiler-generated CFG edge.

Nested named functions and explicit closures own their decisions separately. Computed-property accessors, property observers, subscripts, initializers, and deinitializers are callable units. A parent's complexity excludes decisions belonging to nested callable bodies.

## Coverage

LLVM import consumes per-function source regions and execution counts. It does not apply file-wide percentages to each function. Same-line siblings and nested callables are reconciled independently. Complementary line observations combine by union, not by averaging percentages.

Xcode import consumes per-function line totals. A single aggregate can be scored; ambiguous function anchors or differing aggregate observations fail because aggregate counts cannot recover which individual lines ran.

Only measured executable lines form the denominator. An absent function record is not an executed or unexecuted function. Default behavior rejects missing coverage; the explicit zero policy records `assumedZero` with zero counts and a zero fraction. Compiler-generated functions absent from the authored inventory are not scored.

The score is an execution/complexity indicator. It does not prove useful assertions, mutation resistance, race freedom, or correctness. The [original CRAP proposal](https://testing.googleblog.com/2011/02/this-code-is-crap.html) specifies basis-path coverage; `crap-line-v1` names its line-coverage substitution explicitly.

## Gate and baseline

The default threshold is 30 and comparison is strict: 30 passes, greater than 30 fails. With a baseline, any score increase for an existing ID fails and a new callable must satisfy the absolute threshold. Duplicate identities, unsupported schemas/metrics, and invalid baseline values are errors.

Keep baseline generation and comparison on the same toolchain, platform, configuration, root, and source selection. A renamed callable is new. Anonymous closures use lexical identity and can shift when preceding closures are inserted. Test deletion can regress coverage even when source complexity is unchanged.
