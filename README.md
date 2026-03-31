# vc-use-package-plus

`vc-use-package-plus` extends Emacs's built-in `use-package :vc` support with a
few fixes that matter in real configs:

- Monorepo installs honor `:main-file`, `:lisp-dir`, and an added
  `:compile-files` keyword.
- `package-vc` only scans selected files for dependencies instead of walking an
  entire monorepo.
- VC installs do not pollute the user's project list with `elpa/` checkouts.
- Pre-release headers like `0.3.3-DEV` still produce a usable package version.
- Byte-compilation and native compilation respect the selected files instead of
  compiling an entire checkout.

If you want a smaller starting point for `use-package :vc`, also see
[slotThe/vc-use-package](https://github.com/slotThe/vc-use-package).

## Easy Install Flow

Load this package before the rest of your `use-package :vc` declarations:

```elisp
(require 'package)
(package-initialize)
(require 'use-package)

(setq use-package-vc-prefer-newest t)

(use-package vc-use-package-plus
  :vc (:url "https://github.com/mwolson/vc-use-package-plus")
  :demand t)

(use-package prescient
  :vc (:url "https://github.com/radian-software/prescient.el"
       :main-file "prescient.el"
       :compile-files ("prescient*.el"))
  :demand t)
```

`vc-use-package-plus` adds `:compile-files` for packages that live in a
monorepo or otherwise need an explicit compile set.

## Bootstrap Flow

If you want a command-line bootstrap that installs, upgrades, and byte-compiles
packages before your first real Emacs session, keep a checkout of this repo
somewhere on disk and create tiny wrapper scripts in your own config repo.

Install and upgrade everything:

```elisp
;; scripts/bootstrap-install.el
(setq vc-use-package-plus-batch-root user-emacs-directory
      vc-use-package-plus-batch-load-files '("early-init.el" "init.el")
      vc-use-package-plus-batch-setup-forms
      '((setq use-package-always-ensure t)
        (setq package-native-compile t)))

(load "/path/to/vc-use-package-plus/scripts/install-packages.el")
```

Run it with:

```sh
emacs -Q --batch -l scripts/bootstrap-install.el
```

Native-compile your config files after package updates:

```elisp
;; scripts/bootstrap-native-comp.el
(setq vc-use-package-plus-batch-root user-emacs-directory
      vc-use-package-plus-batch-load-files '("early-init.el" "init.el")
      vc-use-package-plus-batch-compile-files '("early-init.el" "init.el"))

(load "/path/to/vc-use-package-plus/scripts/native-comp-all.el")
```

Run it with:

```sh
emacs -Q --batch -l scripts/bootstrap-native-comp.el
```

The batch helper also supports config-specific toggles and post-install hooks:

```elisp
(setq vc-use-package-plus-batch-setup-forms
      '((setq my-install-packages t)
        (setq my-native-comp-enable nil))
      vc-use-package-plus-batch-post-load-function #'my-run-deferred-tasks
      vc-use-package-plus-batch-post-install-functions
      '(kind-icon-reset-cache kind-icon-preview-all))
```

See [`vc-use-package-plus-batch.el`](vc-use-package-plus-batch.el),
[`scripts/install-packages.el`](scripts/install-packages.el), and
[`scripts/native-comp-all.el`](scripts/native-comp-all.el) for the variables
the wrappers can set.

## License

Unless stated otherwise, the files in this repo may be used, distributed, and
modified without restriction.
