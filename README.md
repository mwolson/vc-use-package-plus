# vcupp (vc-use-package-plus)

![Made for GNU Emacs](assets/badges/made-for-gnu-emacs.svg)

`vcupp` extends Emacs's built-in `use-package :vc` support with a
few fixes that matter in real configs:

- Requires Emacs 30.1 or newer.
- Monorepo installs honor `:main-file`, `:lisp-dir`, and an added
  `:compile-files` keyword, which accepts glob patterns such as
  `"extensions/*.el"`.
- `package-vc` only scans selected files for dependencies instead of walking an
  entire monorepo.
- VC installs do not pollute the user's project list with `elpa/` checkouts.
- Pre-release version headers like `0.3.3-DEV` no longer break installation.
- Byte-compilation and native compilation respect the selected files instead of
  compiling an entire checkout.

## Easy Install Flow

Load this package before the rest of your `use-package :vc` declarations:

```elisp
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
packages before your first real Emacs session, the wrapper examples below
bootstrap `vcupp` themselves before calling its batch helpers. If you customize
`package-user-dir`, do that before the `use-package vcupp` form.

Install and upgrade everything:

```elisp
;; scripts/bootstrap-install.el
;; If you use an XDG init dir instead of `~/.emacs.d`:
;; (setq package-user-dir (expand-file-name "elpa" "~/.config/emacs/"))
(require 'package)
(package-initialize)
(require 'use-package)
(setq use-package-vc-prefer-newest t)

(use-package vcupp
  :vc (:url "https://github.com/mwolson/vcupp")
  :demand t)

(require 'vcupp-install-packages)

(setq vcupp-batch-args
      '(:load-files ("early-init.el" "init.el")
        :setup-forms ((setq use-package-always-ensure t)
                      (setq package-native-compile t))))

(vcupp-install-packages vcupp-batch-args)
```

Run it with:

```sh
emacs -Q --batch -l scripts/bootstrap-install.el
```

Native-compile your config files after package updates.

Recommended: use `compile-angel` for broader coverage:

```elisp
;; scripts/bootstrap-native-comp.el
;; If you use an XDG init dir instead of `~/.emacs.d`:
;; (setq package-user-dir (expand-file-name "elpa" "~/.config/emacs/"))
(require 'package)
(package-initialize)
(require 'use-package)
(setq use-package-vc-prefer-newest t)

(use-package vcupp
  :vc (:url "https://github.com/mwolson/vcupp")
  :demand t)

(require 'vcupp-native-comp)

(setq vcupp-batch-args
      '(:load-files ("early-init.el" "init.el")))

(vcupp-native-comp-all vcupp-batch-args)
```

Run it with:

```sh
emacs -Q --batch -l scripts/bootstrap-native-comp.el
```

This path installs `compile-angel` with `package-vc-install` if needed, then
enables `compile-angel-on-load-mode` *before* loading the config so that
packages and other libraries loaded during init are byte-compiled and
native-compiled automatically.  It still explicitly calls `native-compile` on
the configured entry files afterward, but in most configs `early-init.el` and
`init.el` are enough to exercise nearly everything you care about.

### Coordinating with your init's native-comp settings

During batch runs, `vcupp-native-comp-all` manages `compile-angel`,
`load-prefer-newer`, and related settings.  For interactive Emacs,
call `vcupp-suppress-native-comp-jit` from your early-init to silence
async native-comp warnings and disable JIT (since the batch flow
handles compilation ahead of time).  It is a no-op when
`vcupp-native-comp-active-p` is non-nil, so the two flows do not
conflict:

```elisp
;; In early-init.el -- after loading vcupp
(use-package vcupp
  :vc (:url "https://github.com/mwolson/vcupp")
  :demand t)

(eval-and-compile
  (vcupp-suppress-native-comp-jit))
```

Alternative: disable `compile-angel` and compile an explicit file list:

```elisp
;; scripts/bootstrap-native-comp.el
;; If you use an XDG init dir instead of `~/.emacs.d`:
;; (setq package-user-dir (expand-file-name "elpa" "~/.config/emacs/"))
(require 'package)
(package-initialize)
(require 'use-package)
(setq use-package-vc-prefer-newest t)

(use-package vcupp
  :vc (:url "https://github.com/mwolson/vcupp")
  :demand t)

(require 'vcupp-native-comp)

(setq vcupp-batch-args
      '(:load-files ("early-init.el" "init.el")
        :compile-files ("settings.el" "early-init.el" "init.el")
        :use-compile-angel nil))

(vcupp-native-comp-all vcupp-batch-args)
```

The batch helper also accepts a single plist when you need custom paths,
config-specific toggles, or post-install hooks.  Here is a real-world
install script for a config whose files live under `init/`:

```elisp
;; scripts/install-packages.el
(require 'package)
(setq package-user-dir (locate-user-emacs-file "elpa"))
(package-initialize)

(require 'use-package)
(setq use-package-vc-prefer-newest t)

(use-package vcupp
  :vc (:url "https://github.com/mwolson/vcupp")
  :demand t)
(require 'vcupp-install-packages)

(setq vcupp-batch-args
      `(:root ,(expand-file-name
                (concat (file-name-directory load-file-name) "../"))
        :load-files ("init/early-shared-init.el" "init/shared-init.el")
        :setup-forms ((setq my-install-packages t)
                      (setq my-server-start-p nil))
        :post-load-function my-run-deferred-tasks
        :post-install-functions (kind-icon-reset-cache)))

(vcupp-install-packages vcupp-batch-args)
```

All batch entry points set `load-prefer-newer` to `t`, so stale `.elc` files
are silently bypassed without needing to delete them.  The `:delete-elc-globs`
key is still available for cases where stale `.elc` files are so broken that
they cause load errors even when Emacs prefers `.el`.

See [`vcupp-batch.el`](vcupp-batch.el),
[`vcupp-install-packages.el`](vcupp-install-packages.el),
[`vcupp-native-comp.el`](vcupp-native-comp.el),
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

This project is licensed under the GNU General Public License, version 3 or any
later version. See [LICENSE](LICENSE).
