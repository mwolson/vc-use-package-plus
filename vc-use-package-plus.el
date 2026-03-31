;;; vc-use-package-plus.el --- Better use-package :vc support -*- lexical-binding: t -*-

;; Author: Michael Olson
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (use-package "2.4"))
;; Keywords: convenience, lisp
;; URL: https://github.com/mwolson/vc-use-package-plus

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

(defgroup vc-use-package-plus nil
  "Extensions for `use-package :vc'."
  :group 'convenience)

(defun vc-use-package-plus--generated-el-file-p (path)
  (string-match-p "-\\(?:autoloads\\|pkg\\)\\.el\\'" path))

(defun vc-use-package-plus--expand-el-file-specs (base-dir files)
  (delete-dups
   (delq nil
         (apply #'append
                (mapcar
                 (lambda (file)
                   (mapcar (lambda (path)
                             (and (file-regular-p path)
                                  (not (vc-use-package-plus--generated-el-file-p path))
                                  path))
                           (file-expand-wildcards
                            (expand-file-name file base-dir) t)))
                 files)))))

(with-eval-after-load 'package-vc
  (defun vc-use-package-plus--selected-el-files (pkg-desc)
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
            (vc-use-package-plus--expand-el-file-specs base-dir selected-files))))))

  (defun vc-use-package-plus--compile-targets (pkg-desc)
    (let* ((pkg-spec (and (package-vc-p pkg-desc)
                          (package-vc--desc->spec pkg-desc))))
      (when pkg-spec
        (let* ((dir (package-desc-dir pkg-desc))
               (lisp-dir (plist-get pkg-spec :lisp-dir))
               (full-dir (if lisp-dir (expand-file-name lisp-dir dir) dir))
               (selected-files (vc-use-package-plus--selected-el-files pkg-desc)))
          (cond
           (selected-files
            (list :type 'files :paths selected-files))
           (lisp-dir
            (and (file-directory-p full-dir)
                 (list :type 'dir :path full-dir))))))))

  (define-advice package-vc--unpack (:before (pkg-desc pkg-spec &optional _rev) save-spec-early)
    (when-let* ((name (package-desc-name pkg-desc))
                ((not (alist-get name package-vc-selected-packages nil nil #'string=))))
      (push (cons name pkg-spec) package-vc-selected-packages)))

  (define-advice package-vc--unpack-1 (:around (orig-fn pkg-desc pkg-dir) selected-file-deps)
    (let ((selected-files (vc-use-package-plus--selected-el-files pkg-desc)))
      (if (not selected-files)
          (funcall orig-fn pkg-desc pkg-dir)
        (cl-letf* ((orig-directory-files (symbol-function 'directory-files))
                   ((symbol-function 'directory-files)
                    (lambda (dir &optional full match nosort count)
                      (if (and full (equal match "\\.el\\'"))
                          selected-files
                        (funcall orig-directory-files dir full match nosort count)))))
          (funcall orig-fn pkg-desc pkg-dir)))))

  (define-advice project-remember-projects-under (:around (orig-fn dir &rest args) skip-elpa)
    (unless (string-prefix-p (expand-file-name package-user-dir)
                             (expand-file-name dir))
      (apply orig-fn dir args)))

  (define-advice package-strip-rcs-id (:around (orig-fn str) handle-pre-release)
    (or (condition-case nil (funcall orig-fn str) (error nil))
        (when str
          (condition-case nil
              (funcall orig-fn (replace-regexp-in-string
                                "-\\(?:DEV\\|SNAPSHOT\\|alpha\\|beta\\|rc\\)[^.]*\\'" "" str))
            (error nil)))))

  (define-advice package--compile (:around (orig-fn pkg-desc) vc-compile-targets)
    (let ((target (vc-use-package-plus--compile-targets pkg-desc)))
      (if (not target)
          (funcall orig-fn pkg-desc)
        (let ((warning-minimum-level :error))
          (pcase (plist-get target :type)
            ('files
             (dolist (path (plist-get target :paths))
               (byte-compile-file path)))
            ('dir
             (byte-recompile-directory (plist-get target :path) 0 'force)))))))

  (define-advice package--native-compile-async (:around (orig-fn pkg-desc) vc-compile-targets)
    (when (native-comp-available-p)
      (let ((target (vc-use-package-plus--compile-targets pkg-desc)))
        (if (not target)
            (funcall orig-fn pkg-desc)
          (let ((warning-minimum-level :error))
            (pcase (plist-get target :type)
              ('files
               (native-compile-async (plist-get target :paths)))
              ('dir
               (native-compile-async
                (directory-files-recursively (plist-get target :path) "\\.el\\'"))))))))))

(unless (memq :compile-files use-package-vc-valid-keywords)
  (add-to-list 'use-package-vc-valid-keywords :compile-files))

(define-advice use-package-normalize--vc-arg (:around (orig-fn arg) compile-files)
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

(provide 'vc-use-package-plus)
;;; vc-use-package-plus.el ends here
