;;; vcupp-batch.el --- Shared batch helpers for vcupp -*- lexical-binding: t -*-

;; Author: Michael Olson
;; SPDX-License-Identifier: GPL-3.0-or-later
;; URL: https://github.com/mwolson/vcupp

;;; Commentary:

;; Shared infrastructure for `vcupp-install-packages' and `vcupp-native-comp'
;; batch entry points.  See the vcupp README for usage.

;;; Code:

(require 'cl-lib)
(require 'package)
(require 'subr-x)

(defconst vcupp-batch-default-load-files '("early-init.el" "init.el")
  "Default config files loaded by the batch helpers.")

(defvar vcupp-batch-args nil
  "Default plist of arguments consumed by the batch entry points.")

(defvar vcupp-batch-root
  (expand-file-name user-emacs-directory)
  "Root directory of the Emacs config being processed.")

(defvar vcupp-batch-load-files nil
  "Files to load before deferred tasks or package operations.
Entries may be absolute or relative to `vcupp-batch-root'.")

(defvar vcupp-batch-compile-files nil
  "Files to `native-compile' after loading the config.
Defaults to the value of variable `vcupp-batch-load-files'.")

(defvar vcupp-batch-setup-forms nil
  "Forms evaluated before the config files are loaded.")

(defvar vcupp-batch-preload-features nil
  "Features to `require' before the config files are loaded.")

(defvar vcupp-batch-delete-elc-globs nil
  "Glob patterns whose matching `.elc' files are deleted before load.
Patterns are resolved relative to `vcupp-batch-root'.")

(defvar vcupp-batch-post-load-forms nil
  "Forms run after the config files finish loading.")

(defvar vcupp-batch-post-install-forms nil
  "Forms run after install or upgrade completes.")

(defvar vcupp-batch-refresh-contents t
  "Whether to run `package-refresh-contents' before loading the config.")

(defvar vcupp-batch-package-native-compile t
  "Value to assign to `package-native-compile' during installs.")

(defun vcupp-batch--plist-value (args prop fallback)
  "Return PROP from ARGS if present, otherwise FALLBACK."
  (if (plist-member args prop)
      (plist-get args prop)
    fallback))

(defun vcupp-batch-effective-args (&optional args)
  "Return effective ARGS for batch entry points."
  (let* ((args (or args vcupp-batch-args))
         (root (expand-file-name
                (vcupp-batch--plist-value args :root vcupp-batch-root)))
         (load-files (or (vcupp-batch--plist-value args :load-files
                                                   vcupp-batch-load-files)
                         vcupp-batch-default-load-files))
         (compile-files (or (vcupp-batch--plist-value args :compile-files
                                                      vcupp-batch-compile-files)
                            load-files)))
    (list :root root
          :load-files load-files
          :compile-files compile-files
          :setup-forms (vcupp-batch--plist-value args :setup-forms
                                                 vcupp-batch-setup-forms)
          :preload-features (vcupp-batch--plist-value args :preload-features
                                                      vcupp-batch-preload-features)
          :delete-elc-globs (vcupp-batch--plist-value args :delete-elc-globs
                                                      vcupp-batch-delete-elc-globs)
          :post-load-forms (vcupp-batch--plist-value args :post-load-forms
                                                     vcupp-batch-post-load-forms)
          :post-install-forms (vcupp-batch--plist-value args :post-install-forms
                                                        vcupp-batch-post-install-forms)
          :refresh-contents (vcupp-batch--plist-value args :refresh-contents
                                                      vcupp-batch-refresh-contents)
          :package-native-compile (vcupp-batch--plist-value args :package-native-compile
                                                           vcupp-batch-package-native-compile))))

(defmacro vcupp-batch-with-effective-args (args &rest body)
  "Bind batch variables from ARGS, then run BODY."
  (declare (indent 1) (debug t))
  `(let* ((effective-args (vcupp-batch-effective-args ,args))
          (vcupp-batch-root (plist-get effective-args :root))
          (vcupp-batch-load-files (plist-get effective-args :load-files))
          (vcupp-batch-compile-files (plist-get effective-args :compile-files))
          (vcupp-batch-setup-forms (plist-get effective-args :setup-forms))
          (vcupp-batch-preload-features (plist-get effective-args :preload-features))
          (vcupp-batch-delete-elc-globs (plist-get effective-args :delete-elc-globs))
          (vcupp-batch-post-load-forms (plist-get effective-args :post-load-forms))
          (vcupp-batch-post-install-forms
           (plist-get effective-args :post-install-forms))
          (vcupp-batch-refresh-contents (plist-get effective-args :refresh-contents))
          (vcupp-batch-package-native-compile
           (plist-get effective-args :package-native-compile)))
     ,@body))

(defun vcupp-batch-expand-file (path)
  "Expand PATH relative to `vcupp-batch-root' when needed."
  (if (file-name-absolute-p path)
      path
    (expand-file-name path vcupp-batch-root)))

(defun vcupp-batch-load-files ()
  "Return config files to load for the active batch invocation."
  (or vcupp-batch-load-files
      (user-error "Set :load-files or `vcupp-batch-load-files' before loading this script")))

(defun vcupp-batch-compile-files ()
  "Return config files to `native-compile' for the active batch invocation."
  (or vcupp-batch-compile-files
      (vcupp-batch-load-files)))

(defun vcupp-batch-run-setup ()
  "Run preload features, setup forms, and cleanup."
  (setq load-prefer-newer t)
  (dolist (feature vcupp-batch-preload-features)
    (require feature))
  (dolist (form vcupp-batch-setup-forms)
    (eval form t))
  (dolist (pattern vcupp-batch-delete-elc-globs)
    (dolist (elc (file-expand-wildcards
                  (vcupp-batch-expand-file pattern) t))
      (delete-file elc))))

(defun vcupp-batch-load-config ()
  "Load config files and run optional post-load forms."
  (dolist (file (vcupp-batch-load-files))
    (load-file (vcupp-batch-expand-file file)))
  (dolist (entry vcupp-batch-post-load-forms)
    (if (functionp entry)
        (funcall entry)
      (eval entry t))))

(defun vcupp-batch-run-post-install ()
  "Run `vcupp-batch-post-install-forms' after install completes.
Each entry may be a function designator or a form to evaluate."
  (dolist (entry vcupp-batch-post-install-forms)
    (if (functionp entry)
        (funcall entry)
      (eval entry t))))

(provide 'vcupp-batch)
;;; vcupp-batch.el ends here
