;;; vcupp-native-comp.el --- Native-compile an Emacs config -*- lexical-binding: t -*-

;; Author: Michael Olson
;; SPDX-License-Identifier: GPL-3.0-or-later
;; URL: https://github.com/mwolson/vcupp

;;; Commentary:

;; Batch native-compilation with optional compile-angel integration.
;; See the vcupp README for usage.

;;; Code:

(require 'vcupp-batch)

(declare-function compile-angel-on-load-mode "compile-angel" (&optional arg))

(defvar vcupp-native-comp-active-p nil
  "Non-nil while `vcupp-native-comp-all' is running.
User configs can check this with `bound-and-true-p' to skip their own
compile-angel or native-comp settings during batch compilation.")

(defvar vcupp-native-comp-use-compile-angel t
  "When non-nil, try enabling `compile-angel-on-load-mode' during batch runs.")

(defconst vcupp-native-comp--compile-angel-spec
  '(compile-angel :url "https://github.com/jamescherti/compile-angel.el"
                  :main-file "compile-angel.el")
  "VC spec used to install `compile-angel' on demand.")

(defun vcupp-native-comp--use-compile-angel-p (args)
  "Return non-nil if compile-angel should be used per ARGS."
  (vcupp-batch--plist-value args :use-compile-angel
                            vcupp-native-comp-use-compile-angel))

(defun vcupp-native-comp--ensure-compile-angel (args)
  "Install and load compile-angel if requested by ARGS."
  (when (vcupp-native-comp--use-compile-angel-p args)
    (or (require 'compile-angel nil t)
        (progn
          (message "Installing compile-angel via package-vc...")
          (package-vc-install vcupp-native-comp--compile-angel-spec)
          (require 'compile-angel nil t))
        (progn
          (message "Unable to install compile-angel; falling back to explicit native compilation only")
          nil))))

(defun vcupp-native-comp--enable-compile-angel (compile-angel-available)
  "Enable `compile-angel-on-load-mode' if COMPILE-ANGEL-AVAILABLE is non-nil.
Returns state needed by `vcupp-native-comp--disable-compile-angel'."
  (when compile-angel-available
    (let ((previous-load-prefer-newer load-prefer-newer))
      (setq load-prefer-newer t)
      (compile-angel-on-load-mode 1)
      (list :enabled t :load-prefer-newer previous-load-prefer-newer))))

(defun vcupp-native-comp--disable-compile-angel (state)
  "Disable `compile-angel-on-load-mode' and restore settings from STATE."
  (when (plist-get state :enabled)
    (compile-angel-on-load-mode -1)
    (setq load-prefer-newer (plist-get state :load-prefer-newer))))

(defun vcupp-native-comp-all (&optional args)
  "Native-compile the configured Emacs files.

ARGS is an optional plist.  Supported keys are `:root', `:load-files',
`:compile-files', `:setup-forms', `:preload-features',
`:delete-elc-globs', `:post-load-function', and `:use-compile-angel'.

When `:use-compile-angel' is non-nil (the default),
`compile-angel-on-load-mode' is enabled before the config files are
loaded so that libraries loaded during init are byte-compiled and
native-compiled automatically.  `vcupp-native-comp-active-p' is set
to t before the config load; user configs can check this variable
with `bound-and-true-p', or call `vcupp-suppress-native-comp-jit'
which is a no-op when it is set."
  (vcupp-batch-with-effective-args args
    (unless (native-comp-available-p)
      (user-error "Native compilation is not available in this Emacs"))
    (vcupp-batch-run-setup)
    (package-initialize)
    (let ((compile-angel-available
           (vcupp-native-comp--ensure-compile-angel args)))
      (advice-add 'package-vc-install :override #'ignore)
      (setq vcupp-native-comp-active-p t)
      (let ((compile-angel-state
             (vcupp-native-comp--enable-compile-angel compile-angel-available)))
        (unwind-protect
            (progn
              (vcupp-batch-load-config)
              (message "Native-compiling files...")
              (dolist (file (vcupp-batch-compile-files))
                (native-compile (vcupp-batch-expand-file file))))
          (vcupp-native-comp--disable-compile-angel compile-angel-state)
          (setq vcupp-native-comp-active-p nil))))))

(provide 'vcupp-native-comp)
;;; vcupp-native-comp.el ends here
