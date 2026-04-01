;;; vcupp.el --- Better use-package :vc support -*- lexical-binding: t -*-

;; Author: Michael Olson
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (use-package "2.4"))
;; Keywords: convenience, lisp
;; URL: https://github.com/mwolson/vcupp

;;; Commentary:

;; This package extends Emacs's built-in `package-vc' and `use-package :vc'
;; behavior for monorepos and explicit compile targets.

;;; Code:

(eval-when-compile
  (require 'package-vc)
  (require 'project))

(require 'cl-lib)
(require 'package)
(require 'package-vc nil t)
(require 'seq)
(require 'use-package)

(defvar package-vc-selected-packages)
(defvar warning-minimum-level)

(defgroup vcupp nil
  "Extensions for `use-package :vc'."
  :group 'convenience)

(defun vcupp--generated-el-file-p (path)
  "Return non-nil if PATH names a generated `-autoloads' or `-pkg' file."
  (string-match-p "-\\(?:autoloads\\|pkg\\)\\.el\\'" path))

(defun vcupp--expand-el-file-specs (base-dir files)
  "Expand glob patterns in FILES relative to BASE-DIR.
Returns a deduplicated list of existing `.el' paths, excluding
generated files."
  (delete-dups
   (delq nil
         (apply #'append
                (mapcar
                 (lambda (file)
                   (mapcar (lambda (path)
                             (and (file-regular-p path)
                                  (not (vcupp--generated-el-file-p path))
                                  path))
                           (file-expand-wildcards
                            (expand-file-name file base-dir) t)))
                 files)))))

(defun vcupp--selected-el-files (pkg-desc)
  "Return the selected `.el' file paths for PKG-DESC, or nil."
  (let* ((pkg-spec (and (package-vc-p pkg-desc)
                        (package-vc--desc->spec pkg-desc))))
    (when pkg-spec
      (let* ((dir (package-desc-dir pkg-desc))
             (lisp-dir (plist-get pkg-spec :lisp-dir))
             (base-dir (if lisp-dir (expand-file-name lisp-dir dir) dir))
             (main-file (plist-get pkg-spec :main-file))
             (compile-files (plist-get pkg-spec :compile-files))
             (selected-files
              (cond
               (compile-files
                (append (and main-file (list main-file))
                        compile-files))
               (main-file
                (list main-file)))))
        (when selected-files
          (vcupp--expand-el-file-specs base-dir selected-files))))))

(defun vcupp--compile-targets (pkg-desc)
  "Return a compile target plist for PKG-DESC, or nil."
  (let* ((pkg-spec (and (package-vc-p pkg-desc)
                        (package-vc--desc->spec pkg-desc))))
    (when pkg-spec
      (let* ((dir (package-desc-dir pkg-desc))
             (lisp-dir (plist-get pkg-spec :lisp-dir))
             (full-dir (if lisp-dir (expand-file-name lisp-dir dir) dir))
             (selected-files (vcupp--selected-el-files pkg-desc)))
        (cond
         (selected-files
          (list :type 'files :paths selected-files))
         (lisp-dir
          (and (file-directory-p full-dir)
               (list :type 'dir :path full-dir))))))))

(defun vcupp--save-spec-early (pkg-desc pkg-spec &optional _rev)
  "Save PKG-SPEC for PKG-DESC before unpack so upgrades can find it."
  (when-let* ((name (package-desc-name pkg-desc))
              ((not (alist-get name package-vc-selected-packages nil nil #'string=))))
    (push (cons name pkg-spec) package-vc-selected-packages)))

(defun vcupp--selected-file-deps (orig-fn pkg-desc pkg-dir)
  "Limit dependency scanning for PKG-DESC in PKG-DIR to selected files.
ORIG-FN is the original `package-vc--unpack-1' function."
  (let ((selected-files (vcupp--selected-el-files pkg-desc)))
    (if (not selected-files)
        (funcall orig-fn pkg-desc pkg-dir)
      (cl-letf* ((orig-directory-files (symbol-function 'directory-files))
                 ((symbol-function 'directory-files)
                  (lambda (dir &optional full match nosort count)
                    (if (and full (equal match "\\.el\\'"))
                        selected-files
                      (funcall orig-directory-files dir full match nosort count)))))
        (funcall orig-fn pkg-desc pkg-dir)))))

(defun vcupp--skip-elpa (orig-fn dir &rest args)
  "Prevent `project-remember-projects-under' from indexing `elpa/' checkouts.
ORIG-FN is called with DIR and ARGS only when DIR is outside `package-user-dir'."
  (unless (string-prefix-p (expand-file-name package-user-dir)
                           (expand-file-name dir))
    (apply orig-fn dir args)))

(defun vcupp--handle-pre-release (orig-fn str)
  "Ignore version headers that `package-strip-rcs-id' cannot parse.
ORIG-FN is the original function, STR is the version string.
Returns nil for unparseable versions so `package-vc' assigns a
default instead of signaling an error."
  (condition-case nil (funcall orig-fn str) (error nil)))

(defun vcupp--byte-compile-targets (orig-fn pkg-desc)
  "Byte-compile only selected files for PKG-DESC.
ORIG-FN is the original `package--compile' function."
  (let ((target (vcupp--compile-targets pkg-desc)))
    (if (not target)
        (funcall orig-fn pkg-desc)
      (let ((warning-minimum-level :error))
        (pcase (plist-get target :type)
          ('files
           (dolist (path (plist-get target :paths))
             (byte-compile-file path)))
          ('dir
           (byte-recompile-directory (plist-get target :path) 0 'force)))))))

(defun vcupp--native-compile-targets (orig-fn pkg-desc)
  "Native-compile only selected files for PKG-DESC.
ORIG-FN is the original `package--native-compile-async' function."
  (when (native-comp-available-p)
    (let ((target (vcupp--compile-targets pkg-desc)))
      (if (not target)
          (funcall orig-fn pkg-desc)
        (let ((warning-minimum-level :error))
          (pcase (plist-get target :type)
            ('files
             (native-compile-async (plist-get target :paths)))
            ('dir
             (native-compile-async
              (directory-files-recursively (plist-get target :path) "\\.el\\'")))))))))

(with-eval-after-load 'package-vc
  (advice-add 'package-vc--unpack :before #'vcupp--save-spec-early)
  (advice-add 'package-vc--unpack-1 :around #'vcupp--selected-file-deps)
  (advice-add 'project-remember-projects-under :around #'vcupp--skip-elpa)
  (advice-add 'package-strip-rcs-id :around #'vcupp--handle-pre-release)
  (advice-add 'package--compile :around #'vcupp--byte-compile-targets)
  (advice-add 'package--native-compile-async :around #'vcupp--native-compile-targets))

(unless (memq :compile-files use-package-vc-valid-keywords)
  (add-to-list 'use-package-vc-valid-keywords :compile-files))

(defun vcupp--normalize-vc-arg (orig-fn arg)
  "Normalize a `use-package :vc' ARG that may contain `:compile-files'.
ORIG-FN is the original `use-package-normalize--vc-arg' function."
  (if (not (member :compile-files arg))
      (funcall orig-fn arg)
    (cl-flet* ((ensure-string (s)
                              (if (and s (stringp s)) s (symbol-name s)))
               (ensure-symbol (s)
                              (if (and s (stringp s)) (intern s) s))
               (ensure-list (value)
                            (pcase value
                              (`(quote ,items) items)
                              ((pred listp) value)
                              (_ (list value))))
               (normalize (k v)
                          (pcase k
                            (:rev (pcase v
                                    ('nil (if use-package-vc-prefer-newest
                                              nil
                                            :last-release))
                                    (:last-release :last-release)
                                    (:newest nil)
                                    (_ (ensure-string v))))
                            (:vc-backend (ensure-symbol v))
                            ((or :compile-files :ignored-files)
                             (ensure-list v))
                            (_ (ensure-string v)))))
      (pcase-let* ((`(,name . ,opts) arg))
        (if (stringp opts)
            (list name opts)
          (let ((opts (use-package-split-when
                       (lambda (el)
                         (seq-contains-p use-package-vc-valid-keywords el))
                       opts)))
            (cl-loop for (k . _) in opts
                     if (not (member k use-package-vc-valid-keywords))
                     do (use-package-error
                         (format "Keyword :vc received unknown argument: %s. Supported keywords are: %s"
                                 k use-package-vc-valid-keywords)))
            (list name
                  (cl-loop for (k . v) in opts
                           if (not (eq k :rev))
                           nconc (list k (normalize k (if (length= v 1)
                                                          (car v)
                                                        v))))
                  (normalize :rev (car (alist-get :rev opts))))))))))

(advice-add 'use-package-normalize--vc-arg :around #'vcupp--normalize-vc-arg)

(defun vcupp-suppress-native-comp-jit ()
  "Configure native-comp for configs that use `vcupp-native-comp-all'.
Silences async native-comp warnings and disables JIT compilation,
since the batch native-comp flow handles compilation ahead of time.
Has no effect when `vcupp-native-comp-active-p' is non-nil."
  (unless (bound-and-true-p vcupp-native-comp-active-p)
    (eval-when-compile (require 'comp-run))
    (require 'comp-run)
    (setq native-comp-async-report-warnings-errors 'silent
          native-comp-jit-compilation nil)))

(provide 'vcupp)
;;; vcupp.el ends here
