;;; vcupp-native-comp.el --- Native-compile an Emacs config -*- lexical-binding: t -*-

;; Author: Michael Olson
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; SPDX-License-Identifier: GPL-3.0-or-later
;; URL: https://github.com/mwolson/vcupp

;;; Code:

(require 'vcupp-batch)

(declare-function compile-angel-on-load-mode "compile-angel" (&optional arg))

(defvar vcupp-native-comp-use-compile-angel t
  "When non-nil, try enabling `compile-angel-on-load-mode' during batch runs.")

(defun vcupp-native-comp--use-compile-angel-p (args)
  (vcupp-batch--plist-value args :use-compile-angel
                            vcupp-native-comp-use-compile-angel))

(defun vcupp-native-comp--enable-compile-angel (args)
  (when (vcupp-native-comp--use-compile-angel-p args)
    (if (not (require 'compile-angel nil t))
        (message "compile-angel not installed; falling back to explicit native compilation only")
      (let ((previous-load-prefer-newer load-prefer-newer))
        (setq load-prefer-newer t)
        (compile-angel-on-load-mode 1)
        (list :enabled t :load-prefer-newer previous-load-prefer-newer)))))

(defun vcupp-native-comp--disable-compile-angel (state)
  (when (plist-get state :enabled)
    (compile-angel-on-load-mode -1)
    (setq load-prefer-newer (plist-get state :load-prefer-newer))))

(defun vcupp-native-comp-all (&optional args)
  "Native-compile the configured Emacs files.

ARGS is an optional plist. Supported keys are `:root', `:load-files',
`:compile-files', `:setup-forms', `:preload-features',
`:delete-elc-globs', `:post-load-function', and `:use-compile-angel'."
  (vcupp-batch-with-effective-args args
    (unless (native-comp-available-p)
      (user-error "Native compilation is not available in this Emacs"))
    (vcupp-batch-run-setup)
    (package-initialize)
    (advice-add 'package-vc-install :override #'ignore)
    (let (compile-angel-state)
      (unwind-protect
          (progn
            (vcupp-batch-load-config)
            (setq compile-angel-state
                  (vcupp-native-comp--enable-compile-angel args))
            (message "Native-compiling files...")
            (dolist (file (vcupp-batch-compile-files))
              (native-compile (vcupp-batch-expand-file file))))
        (vcupp-native-comp--disable-compile-angel compile-angel-state)))))

(provide 'vcupp-native-comp)
;;; vcupp-native-comp.el ends here
