# vcupp (vc-use-package-plus)

![Made for GNU Emacs](assets/badges/made-for-gnu-emacs.svg)

`vcupp` extends Emacs's built-in `use-package :vc` support with bug fixes and
batch tooling for package installation and native compilation. Requires Emacs
30.1 or newer.

WARNING: This project is still in alpha phase and contracts may change.

## Why use this library

Emacs 30 added `use-package :vc`, which installs packages directly from Git
repositories. This is a powerful alternative to MELPA:

- You can install packages that are not on MELPA yet.
- You can fork a package, add your own improvements, and point `:vc` at your
  fork.
- Updates are available immediately when the upstream repo is pushed, rather
  than waiting for MELPA to rebuild.

vcupp fixes several rough edges in the built-in `:vc` support:

- Installs from larger repos honor `:main-file`, `:lisp-dir`, and an added
  `:compile-files` keyword (supporting glob patterns like `"extensions/*.el"`),
  so dependency scanning, byte-compilation, and native compilation are limited
  to the files you actually use.
- `package-vc` only scans selected files for dependencies instead of walking an
  entire checkout.
- VC installs do not pollute the user's project list with `elpa/` checkouts.
- Pre-release version headers like `0.3.3-DEV` produce a usable package version
  instead of breaking installation.
- Changing the `use-package` form to a forked repo is expected to work.

vcupp also provides batch helpers (`vcupp-install-packages` and
`vcupp-native-comp-all`) that let you set up a bootstrap process to install,
upgrade, and native-compile all your packages from the command line. This means
normal Emacs startup never triggers package installation or native compilation,
so you choose when to update and every startup is consistently fast.

## Why not to use it

- All your dependencies are on MELPA, MELPA is working well for you, and you
  don't need packages from Git, and/or `package-vc` is already working well
  enough.
- The slowdown on upgrading packages compared to MELPA is too much (negligible
  if you're using the bootstrap approach, but still can be upwards of 10+
  seconds).
- You prefer not to manually manage transitive dependencies of your packages.
  (If this is only an issue for some packages, you can mix and match: use MELPA
  for packages with deep dependency trees and `:vc` for the rest.)
- You don't want to deal with native compilation or set up a bootstrap script.
  Without bootstrapping, Emacs native-compiles packages on-the-fly via JIT,
  which causes a one-time slowdown after every update. If that tradeoff is fine
  for your workflow, the batch helpers here add complexity for little benefit.

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

`vcupp` adds `:compile-files` for packages that live in a larger repo or
otherwise need an explicit compile set, such as excluding tests or other
dev-only Elisp files.

### Preloading package autoloads

`vcupp-preload-package` loads the autoloads for a single package from
`package-user-dir` without running a full `package-initialize`. This is useful
in early-init files where you need a few packages available for `:init` or
`eval-and-compile` blocks without the startup cost of activating every installed
package:

```elisp
;; In early-init.el -- vcupp itself needs a manual bootstrap since
;; vcupp-preload-package is not yet available at that point.
(use-package vcupp
  :vc (:url "https://github.com/mwolson/vcupp")
  :init
  (when-let* ((dir (expand-file-name "vcupp" package-user-dir))
              ((file-directory-p dir))
              (al-file (expand-file-name "vcupp-autoloads" dir)))
    (load al-file nil t))
  :demand t)

;; After vcupp is loaded, use vcupp-preload-package for other packages.
(use-package compile-angel
  :vc (:url "https://github.com/jamescherti/compile-angel.el"
       :main-file "compile-angel.el")
  :init (vcupp-preload-package 'compile-angel)
  :defer t)
```

## Bootstrap - Install Packages

`vcupp-install-packages` provides a command-line bootstrap that installs,
upgrades, and byte-compiles packages. Two things are needed:

1. Call `vcupp-ensure-packages-on-install` from your `init.el` (or from
   `early-init.el` if you have `use-package` forms there) after loading vcupp.
   During batch installs this sets `use-package-always-ensure` to `t`, which
   tells every `use-package` form to install its package if missing. During
   normal interactive startup it is a no-op (packages are already installed, so
   there is nothing to do):

   ```elisp
   ;; After loading vcupp (see Easy Install Flow above)
   (vcupp-ensure-packages-on-install)
   ```

2. Create a batch script that bootstraps vcupp and calls
   `vcupp-install-packages` with an options plist (see
   [Batch Options](#batch-options-vcupp) for all supported keys).

   Minimal example using the default `~/.emacs.d` layout:

   ```elisp
   ;; scripts/install-packages.el
   (require 'package)
   ;; If your config lives under ~/.config/emacs/ instead of ~/.emacs.d:
   ;; (setq package-user-dir (expand-file-name "elpa" "~/.config/emacs/"))
   (package-initialize)
   (require 'use-package)
   (setq use-package-vc-prefer-newest t)

   ;; Prevent elpa/ checkouts from being added to the project list.
   ;; vcupp cleans up stale entries and blocks future ones on load,
   ;; but this line covers vcupp's own initial install.
   (advice-add 'project-remember-projects-under :override #'ignore)

   (use-package vcupp
     :vc (:url "https://github.com/mwolson/vcupp")
     :demand t)
   (require 'vcupp-install-packages)

   (vcupp-install-packages
    '(:load-files ("early-init.el" "init.el")))
   ```

   Run it with `emacs -Q --batch -l scripts/install-packages.el`.

   A real-world example for a config whose files live under `init/`:

   ```elisp
   ;; scripts/install-packages.el
   (require 'package)
   ;; If your config lives under ~/.config/emacs/ instead of ~/.emacs.d:
   ;; (setq package-user-dir (expand-file-name "elpa" "~/.config/emacs/"))
   (package-initialize)

   (require 'use-package)
   (setq use-package-vc-prefer-newest t)

   (advice-add 'project-remember-projects-under :override #'ignore)

   (use-package vcupp
     :vc (:url "https://github.com/mwolson/vcupp")
     :demand t)
   (require 'vcupp-install-packages)

   (vcupp-install-packages
    `(:root ,(expand-file-name
              (concat (file-name-directory load-file-name) "../"))
      :load-files ("init/early-shared-init.el" "init/shared-init.el")
      :setup-forms ((setq my-server-start-p nil))
      :post-install-forms
      ((vcupp-activate-package 'kind-icon)
       (require 'kind-icon)
       (kind-icon-reset-cache)
       (kind-icon-preview-all))))
   ```

## Bootstrap - Native Compilation

`vcupp-native-comp-all` native-compiles your config files after package
installation. By default it uses `compile-angel` for broader coverage:
`compile-angel-on-load-mode` is enabled before loading the config so that
libraries loaded during init are byte-compiled and native-compiled
automatically. It then explicitly native-compiles the configured entry files
afterward. In most configs `early-init.el` and `init.el` are enough to exercise
nearly everything you care about.

Two things are needed:

1. Call `vcupp-suppress-native-comp-jit` from your early-init to silence async
   native-comp warnings and disable JIT during interactive use (since the batch
   flow handles compilation ahead of time). It is a no-op during batch runs:

   ```elisp
   ;; In early-init.el -- after loading vcupp (see Easy Install Flow above)
   (eval-and-compile
     (vcupp-suppress-native-comp-jit))
   ```

2. Create a batch script that bootstraps vcupp and calls `vcupp-native-comp-all`
   with an options plist:

   ```elisp
   ;; scripts/native-comp-all.el
   (require 'package)
   ;; If your config lives under ~/.config/emacs/ instead of ~/.emacs.d:
   ;; (setq package-user-dir (expand-file-name "elpa" "~/.config/emacs/"))
   (package-initialize)
   (require 'use-package)
   (setq use-package-vc-prefer-newest t)

   (advice-add 'project-remember-projects-under :override #'ignore)

   (use-package vcupp
     :vc (:url "https://github.com/mwolson/vcupp")
     :demand t)
   (require 'vcupp-native-comp)

   (vcupp-native-comp-all
    '(:load-files ("early-init.el" "init.el")))
   ```

   Run it with `emacs -Q --batch -l scripts/native-comp-all.el`.

To disable `compile-angel` and compile an explicit file list instead, pass
`:use-compile-angel nil` and a separate `:compile-files`:

```elisp
(vcupp-native-comp-all
 '(:load-files ("early-init.el" "init.el")
   :compile-files ("settings.el" "early-init.el" "init.el")
   :use-compile-angel nil))
```

### Putting it all together in early-init.el

A complete early-init.el using both bootstrap features:

```elisp
(require 'use-package)
(setq use-package-vc-prefer-newest t)

(use-package vcupp
  :vc (:url "https://github.com/mwolson/vcupp")
  :demand t)

(eval-and-compile
  (vcupp-suppress-native-comp-jit))
(vcupp-ensure-packages-on-install)

;; The rest of your early-init...
```

## Keywords (use-package)

`vcupp` keeps the existing `use-package :vc` keyword set and adds one new
keyword for compile target selection.

Built-in `use-package :vc` keywords:

- `:url`: Repository URL.
- `:branch`: Branch name to check out.
- `:lisp-dir`: Subdirectory containing the package's elisp.
- `:main-file`: Main entry file for the package.
- `:vc-backend`: VCS backend symbol.
- `:rev`: Revision selector. `use-package-vc-prefer-newest` controls the default
  behavior for `nil`.
- `:shell-command`: Shell command run after checkout.
- `:make`: Build command run after checkout.
- `:ignored-files`: Files to exclude from packaging.

Added by `vcupp`:

- `:compile-files`: Explicit set of `.el` files to scan and compile. This may be
  a single file or a list of MELPA-style glob patterns such as `"*.el"` or
  `"extensions/*.el"`. `vcupp` combines these with `:main-file`, respects
  `:lisp-dir`, and limits dependency scanning, byte-compilation, and native
  compilation to the selected files.

## Batch Options (vcupp)

Both `vcupp-install-packages` and `vcupp-native-comp-all` accept an optional
plist as their first argument. All batch entry points set `load-prefer-newer` to
`t`, so stale `.elc` files are silently bypassed without needing to delete them.

Shared keys (used by both entry points):

| Key                 | Default                       | Description                                                                                                                 |
| ------------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `:root`             | `user-emacs-directory`        | Root directory for resolving relative paths.                                                                                |
| `:load-files`       | `("early-init.el" "init.el")` | Config files to load.                                                                                                       |
| `:setup-forms`      | `nil`                         | Forms evaluated before loading (e.g., setting variables).                                                                   |
| `:preload-features` | `nil`                         | Features to `require` before loading.                                                                                       |
| `:delete-elc-globs` | `nil`                         | Glob patterns whose `.elc` matches are deleted before load. Rarely needed since `load-prefer-newer` handles stale bytecode. |
| `:post-load-forms`  | `nil`                         | Forms evaluated after config files finish loading.                                                                          |

Additional keys for `vcupp-install-packages`:

| Key                       | Default | Description                                                                                        |
| ------------------------- | ------- | -------------------------------------------------------------------------------------------------- |
| `:upgrade`                | `t`     | Pull latest commits for all VC packages. Set to nil to install missing packages without upgrading. |
| `:post-install-forms`     | `nil`   | Forms evaluated after install/upgrade completes.                                                   |
| `:refresh-contents`       | `t`     | Whether to run `package-refresh-contents` first.                                                   |
| `:package-native-compile` | `t`     | Value assigned to `package-native-compile` during installs.                                        |

Additional keys for `vcupp-native-comp-all`:

| Key                  | Default               | Description                                                                                     |
| -------------------- | --------------------- | ----------------------------------------------------------------------------------------------- |
| `:compile-files`     | same as `:load-files` | Files to `native-compile` after loading.                                                        |
| `:use-compile-angel` | `t`                   | Enable `compile-angel-on-load-mode` before loading the config for broader compilation coverage. |

## License

This project is licensed under the GNU General Public License, version 3 or any
later version. See [LICENSE](LICENSE).
