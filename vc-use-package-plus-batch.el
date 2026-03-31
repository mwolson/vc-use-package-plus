;;; vc-use-package-plus-batch.el --- Batch helpers for vc-use-package-plus -*- lexical-binding: t -*-

;; Author: Michael Olson
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; URL: https://github.com/mwolson/vc-use-package-plus

;;; Code:

(require 'cl-lib)
(require 'package)
(require 'subr-x)

(defvar vc-use-package-plus-batch-root
  (expand-file-name default-directory)
  "Root directory of the Emacs config being processed.")

(defvar vc-use-package-plus-batch-load-files nil
  "Files to load before deferred tasks or package operations.
Entries may be absolute or relative to `vc-use-package-plus-batch-root'.")

(defvar vc-use-package-plus-batch-compile-files nil
  "Files to native-compile after loading the config.
Defaults to `vc-use-package-plus-batch-load-files'.")

(defvar vc-use-package-plus-batch-setup-forms nil
  "Forms evaluated before the config files are loaded.")

(defvar vc-use-package-plus-batch-preload-features nil
  "Features to `require' before the config files are loaded.")

(defvar vc-use-package-plus-batch-delete-elc-globs nil
  "Glob patterns whose matching `.elc' files are deleted before load.
Patterns are resolved relative to `vc-use-package-plus-batch-root'.")

(defvar vc-use-package-plus-batch-post-load-function nil
  "Function called after the config files finish loading.")

(defvar vc-use-package-plus-batch-post-install-functions nil
  "Functions called after install or upgrade completes.")

(defvar vc-use-package-plus-batch-refresh-contents t
  "Whether to run `package-refresh-contents' before loading the config.")

(defvar vc-use-package-plus-batch-package-native-compile t
  "Value to assign to `package-native-compile' during installs.")

(defvar vc-use-package-plus-batch--desired-vc-specs nil
  "Normalized VC specs declared by `use-package' during this run.")

(defun vc-use-package-plus-batch--expand-file (path)
  (if (file-name-absolute-p path)
      path
    (expand-file-name path vc-use-package-plus-batch-root)))

(defun vc-use-package-plus-batch--load-files ()
  (or vc-use-package-plus-batch-load-files
      (user-error "Set vc-use-package-plus-batch-load-files before loading this script")))

(defun vc-use-package-plus-batch--compile-files ()
  (or vc-use-package-plus-batch-compile-files
      (vc-use-package-plus-batch--load-files)))

(defun vc-use-package-plus-batch--run-setup ()
  (dolist (feature vc-use-package-plus-batch-preload-features)
    (require feature))
  (dolist (form vc-use-package-plus-batch-setup-forms)
    (eval form t))
  (dolist (pattern vc-use-package-plus-batch-delete-elc-globs)
    (dolist (elc (file-expand-wildcards
                  (vc-use-package-plus-batch--expand-file pattern) t))
      (delete-file elc))))

(defun vc-use-package-plus-batch--load-config ()
  (dolist (file (vc-use-package-plus-batch--load-files))
    (load-file (vc-use-package-plus-batch--expand-file file)))
  (when vc-use-package-plus-batch-post-load-function
    (funcall vc-use-package-plus-batch-post-load-function)))

(defun vc-use-package-plus-batch--record-vc-spec (name _keyword arg _rest _state)
  (setf (alist-get name vc-use-package-plus-batch--desired-vc-specs nil nil #'eq)
        arg))

(defun vc-use-package-plus-batch--reinstall-changed-vc-urls ()
  (message "Checking VC packages for source URL changes...")
  (dolist (pkg-alist-entry package-alist)
    (dolist (pkg-desc (cdr pkg-alist-entry))
      (when-let* (((package-vc-p pkg-desc))
                  (desired-arg (alist-get (package-desc-name pkg-desc)
                                          vc-use-package-plus-batch--desired-vc-specs
                                          nil nil #'eq)))
        (let* ((desired-spec (nth 1 desired-arg))
               (desired-rev (nth 2 desired-arg))
               (desired-url (plist-get desired-spec :url))
               (pkg-dir (package-desc-dir pkg-desc)))
          (when (and desired-url
                     pkg-dir
                     (file-directory-p (expand-file-name ".git" pkg-dir)))
            (let* ((default-directory pkg-dir)
                   (current-url
                    (ignore-errors
                      (car (process-lines "git" "remote" "get-url" "origin")))))
              (when (and current-url
                         (not (string-equal
                               (replace-regexp-in-string "\\(?:\\.git\\|/\\)\\'" ""
                                                         current-url)
                               (replace-regexp-in-string "\\(?:\\.git\\|/\\)\\'" ""
                                                         desired-url))))
                (message "  %s: reinstalling from %s (was %s)"
                         (package-desc-name pkg-desc) desired-url current-url)
                (package-delete pkg-desc t t)
                (package-vc-install
                 (cons (package-desc-name pkg-desc) desired-spec)
                 desired-rev)))))))))

(defun vc-use-package-plus-batch--attach-vc-packages-to-branches ()
  (message "Checking VC packages for detached HEAD...")
  (dolist (pkg-alist-entry package-alist)
    (dolist (pkg-desc (cdr pkg-alist-entry))
      (when (package-vc-p pkg-desc)
        (let ((pkg-dir (package-desc-dir pkg-desc)))
          (when (and pkg-dir (file-directory-p (expand-file-name ".git" pkg-dir)))
            (let ((default-directory pkg-dir))
              (unless (zerop (process-file "git" nil nil nil
                                           "symbolic-ref" "--quiet" "HEAD"))
                (let ((branch
                       (string-trim
                        (with-output-to-string
                          (with-current-buffer standard-output
                            (process-file "git" nil t nil
                                          "rev-parse" "--abbrev-ref"
                                          "origin/HEAD"))))))
                  (when (string-prefix-p "origin/" branch)
                    (setq branch (substring branch 7)))
                  (when (or (string= branch "") (string= branch "HEAD"))
                    (setq branch
                          (cl-loop for b in '("main" "master" "trunk")
                                   when (zerop (process-file
                                                "git" nil nil nil
                                                "rev-parse" "--verify"
                                                (concat "origin/" b)))
                                   return b)))
                  (when branch
                    (message "  %s: checking out %s"
                             (package-desc-name pkg-desc) branch)
                    (process-file "git" nil nil nil
                                  "checkout" "-f" branch)))))))))))

(defun vc-use-package-plus-batch--clean-stale-vc-elc-files ()
  (message "Cleaning stale .elc files from VC packages...")
  (dolist (pkg-alist-entry package-alist)
    (dolist (pkg-desc (cdr pkg-alist-entry))
      (when (package-vc-p pkg-desc)
        (let ((pkg-dir (package-desc-dir pkg-desc)))
          (when pkg-dir
            (dolist (elc (directory-files-recursively pkg-dir "\\.elc\\'"))
              (let ((el (concat (file-name-sans-extension elc) ".el")))
                (when (and (file-exists-p el)
                           (file-newer-than-file-p el elc))
                  (delete-file elc))))))))))

(defun vc-use-package-plus-batch-install-packages ()
  "Install and upgrade packages declared by the current config."
  (setq vc-use-package-plus-batch--desired-vc-specs nil)
  (vc-use-package-plus-batch--run-setup)
  (setq package-native-compile vc-use-package-plus-batch-package-native-compile)
  (package-initialize)
  (require 'use-package)
  (when vc-use-package-plus-batch-refresh-contents
    (package-refresh-contents))
  (define-advice use-package-handler/:vc
      (:before (name keyword arg rest state) record-install-spec)
    (vc-use-package-plus-batch--record-vc-spec name keyword arg rest state))
  (advice-add 'project-remember-projects-under :override #'ignore)
  (advice-add 'yes-or-no-p :override (lambda (&rest _) t))
  (vc-use-package-plus-batch--load-config)
  (vc-use-package-plus-batch--reinstall-changed-vc-urls)
  (vc-use-package-plus-batch--attach-vc-packages-to-branches)
  (message "Upgrading VC packages to latest commits...")
  (package-vc-upgrade-all)
  (vc-use-package-plus-batch--clean-stale-vc-elc-files)
  (dolist (fn vc-use-package-plus-batch-post-install-functions)
    (funcall fn)))

(defun vc-use-package-plus-batch-native-comp-all ()
  "Native-compile the configured Emacs files."
  (unless (native-comp-available-p)
    (user-error "Native compilation is not available in this Emacs"))
  (vc-use-package-plus-batch--run-setup)
  (package-initialize)
  (advice-add 'package-vc-install :override #'ignore)
  (vc-use-package-plus-batch--load-config)
  (message "Native-compiling files...")
  (dolist (file (vc-use-package-plus-batch--compile-files))
    (native-compile (vc-use-package-plus-batch--expand-file file))))

(provide 'vc-use-package-plus-batch)
;;; vc-use-package-plus-batch.el ends here
