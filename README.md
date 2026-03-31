# vcupp (vc-use-package-plus)

`vcupp` extends Emacs's built-in `use-package :vc` support with a
few fixes that matter in real configs:

- Requires Emacs 30.1 or newer.
- Monorepo installs honor `:main-file`, `:lisp-dir`, and an added
  `:compile-files` keyword, which accepts glob patterns such as
  `"extensions/*.el"`.
- `package-vc` only scans selected files for dependencies instead of walking an
  entire monorepo.
- VC installs do not pollute the user's project list with `elpa/` checkouts.
- Pre-release headers like `0.3.3-DEV` still produce a usable package version.
- Byte-compilation and native compilation respect the selected files instead of
  compiling an entire checkout.

## Easy Install Flow

Load this package before the rest of your `use-package :vc` declarations:

```elisp
(require 'package)
(package-initialize)
(require 'use-package)

(setq use-package-vc-prefer-newest t)

(use-package vcupp
  :vc (:url "https://github.com/mwolson/vcupp")
  :demand t)

;; Your own `use-package' forms start here.
(use-package prescient
  :vc (:url "https://github.com/radian-software/prescient.el"
       :main-file "prescient.el"
       :compile-files ("prescient*.el"))
  :demand t)
```

`vcupp` adds `:compile-files` for packages that live in a
monorepo or otherwise need an explicit compile set.

## Bootstrap Flow

If you want a command-line bootstrap that installs, upgrades, and byte-compiles
packages before your first real Emacs session, keep a checkout of this repo
somewhere on disk and create a tiny wrapper script in your own config repo.

Install and upgrade everything:

```elisp
;; scripts/bootstrap-install.el
(setq vcupp-batch-args
      '(:load-files ("early-init.el" "init.el")
        :setup-forms ((setq use-package-always-ensure t)
                      (setq package-native-compile t))))

(load "/path/to/vcupp/scripts/install-packages.el")
```

Run it with:

```sh
emacs -Q --batch -l scripts/bootstrap-install.el
```

Native-compile your config files after package updates:

```elisp
;; scripts/bootstrap-native-comp.el
(setq vcupp-batch-args
      '(:load-files ("early-init.el" "init.el")))

(load "/path/to/vcupp/scripts/native-comp-all.el")
```

Run it with:

```sh
emacs -Q --batch -l scripts/bootstrap-native-comp.el
```

The batch helper also accepts a single plist when you need custom paths,
config-specific toggles, or post-install hooks:

```elisp
(setq vcupp-batch-args
      '(:root "~/src/my-emacs-config/"
        :load-files ("init/early-shared-init.el" "init/shared-init.el")
        :compile-files ("init/settings.el"
                        "init/early-shared-init.el"
                        "init/shared-init.el")
        :setup-forms ((setq my-install-packages t)
                      (setq my-native-comp-enable nil))
        :post-load-function my-run-deferred-tasks
        :post-install-functions (kind-icon-reset-cache kind-icon-preview-all)))
```

See [`vcupp-batch.el`](vcupp-batch.el),
[`scripts/install-packages.el`](scripts/install-packages.el), and
[`scripts/native-comp-all.el`](scripts/native-comp-all.el) for the supported
plist keys and defaults.

## Keywords

`vcupp` keeps the existing `use-package :vc` keyword set and adds one new
keyword for compile target selection.

Built-in `use-package :vc` keywords:

- `:url`: Repository URL.
- `:branch`: Branch name to check out.
- `:lisp-dir`: Subdirectory containing the package's elisp.
- `:main-file`: Main entry file for the package.
- `:vc-backend`: VCS backend symbol.
- `:rev`: Revision selector. `use-package-vc-prefer-newest` controls the
  default behavior for `nil`.
- `:shell-command`: Shell command run after checkout.
- `:make`: Build command run after checkout.
- `:ignored-files`: Files to exclude from packaging.

Added by `vcupp`:

- `:compile-files`: Explicit set of `.el` files to scan and compile. This may
  be a single file or a list of MELPA-style glob patterns such as `"*.el"` or
  `"extensions/*.el"`. `vcupp` combines these with `:main-file`, respects
  `:lisp-dir`, and limits dependency scanning, byte-compilation, and native
  compilation to the selected files.

## License

Unless stated otherwise, the files in this repo may be used, distributed, and
modified without restriction.
