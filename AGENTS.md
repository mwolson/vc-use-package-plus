# AGENTS.md

This repository is for an Emacs library (`vcupp`) that extends `use-package :vc`
support. It requires Emacs 30.1 or newer.

## Tips

- When making changes to data in existing code, try to keep things in
  alphabetical order when it's reasonable to do so.

## Planning

Prefer to write plans in the `plans/` directory.

## Dev loop tools

### Running tests

Run unit tests with:

```sh
npm run test
```

This executes the default ERT suite found in `test/test.el`.

### Checking for byte-compile warnings

Run the byte-compile check with:

```sh
npm run check
```

This byte-compiles all `.el` files and fails if there are any warnings. Fix all
warnings before committing.

### Checking for checkdoc warnings

Run checkdoc on each source file:

```sh
./scripts/checkdoc.sh vcupp.el
./scripts/checkdoc.sh vcupp-batch.el
./scripts/checkdoc.sh vcupp-native-comp.el
./scripts/checkdoc.sh vcupp-install-packages.el
```

All public and private functions must have docstrings.

### Quick Elisp sanity check

Check parentheses balance after edits:

```sh
emacs -Q --batch --eval '(progn (with-temp-buffer (insert-file-contents "vcupp.el") (check-parens)))'
```

### One-off batch harnesses

When iterating on a small part of the code, prefer writing a tiny one-off `.el`
file under `tmp/` and running it via `emacs -Q --batch`.

### MELPA recipe

The local source of truth for the MELPA recipe is `vcupp.recipe` at the
repository root. The Melpazoid CI workflow reads from that file.

## Gotchas

### Emacs version requirements

vcupp requires Emacs 30.1. Several features it depends on (`use-package :vc`,
`package-vc`, `use-package-vc-valid-keywords`, `comp-run`) are not present in
earlier versions. The GitHub Actions CI workflow uses `purcell/setup-emacs` to
install Emacs 30.1 instead of the system Emacs package.

### Deprecated macros

- `when-let` and `if-let` are deprecated in favor of `when-let*` and `if-let*`.
  Always use the starred versions.

### Compile-time vs runtime evaluation

When silencing byte-compilation warnings about unknown functions or variables,
prefer `eval-when-compile` with `require` over `declare-function` or `defvar`.
Use forward `defvar` declarations (without a value) for variables defined in
packages that vcupp does not `require` at top level.
