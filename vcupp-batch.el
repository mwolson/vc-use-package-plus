;;; vcupp-batch.el --- Batch helpers for vcupp -*- lexical-binding: t -*-

;; Author: Michael Olson
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; URL: https://github.com/mwolson/vcupp

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
  "Files to native-compile after loading the config.
Defaults to `vcupp-batch-load-files'.")

(defvar vcupp-batch-setup-forms nil
  "Forms evaluated before the config files are loaded.")

(defvar vcupp-batch-preload-features nil
  "Features to `require' before the config files are loaded.")

(defvar vcupp-batch-delete-elc-globs nil
  "Glob patterns whose matching `.elc' files are deleted before load.
Patterns are resolved relative to `vcupp-batch-root'.")

(defvar vcupp-batch-post-load-function nil
  "Function called after the config files finish loading.")

(defvar vcupp-batch-post-install-functions nil
  "Functions called after install or upgrade completes.")

(defvar vcupp-batch-refresh-contents t
  "Whether to run `package-refresh-contents' before loading the config.")

(defvar vcupp-batch-package-native-compile t
  "Value to assign to `package-native-compile' during installs.")

(defvar vcupp-batch--desired-vc-specs nil
  "Normalized VC specs declared by `use-package' during this run.")

(defun vcupp-batch--plist-value (args prop fallback)
  (if (plist-member args prop)
      (plist-get args prop)
    fallback))

(defun vcupp-batch--effective-args (&optional args)
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
          :post-load-function (vcupp-batch--plist-value args :post-load-function
                                                        vcupp-batch-post-load-function)
          :post-install-functions (vcupp-batch--plist-value args :post-install-functions
                                                            vcupp-batch-post-install-functions)
          :refresh-contents (vcupp-batch--plist-value args :refresh-contents
                                                      vcupp-batch-refresh-contents)
          :package-native-compile (vcupp-batch--plist-value args :package-native-compile
                                                           vcupp-batch-package-native-compile))))

(defmacro vcupp-batch--with-effective-args (args &rest body)
  (declare (indent 1) (debug t))
  `(let* ((effective-args (vcupp-batch--effective-args ,args))
          (vcupp-batch-root (plist-get effective-args :root))
          (vcupp-batch-load-files (plist-get effective-args :load-files))
          (vcupp-batch-compile-files (plist-get effective-args :compile-files))
          (vcupp-batch-setup-forms (plist-get effective-args :setup-forms))
          (vcupp-batch-preload-features (plist-get effective-args :preload-features))
          (vcupp-batch-delete-elc-globs (plist-get effective-args :delete-elc-globs))
          (vcupp-batch-post-load-function (plist-get effective-args :post-load-function))
          (vcupp-batch-post-install-functions
           (plist-get effective-args :post-install-functions))
          (vcupp-batch-refresh-contents (plist-get effective-args :refresh-contents))
          (vcupp-batch-package-native-compile
           (plist-get effective-args :package-native-compile)))
     ,@body))

(defun vcupp-batch--expand-file (path)
  (if (file-name-absolute-p path)
      path
    (expand-file-name path vcupp-batch-root)))

(defun vcupp-batch--load-files ()
  (or vcupp-batch-load-files
      (user-error "Set :load-files or `vcupp-batch-load-files' before loading this script")))

(defun vcupp-batch--compile-files ()
  (or vcupp-batch-compile-files
      (vcupp-batch--load-files)))

(defun vcupp-batch--run-setup ()
  (dolist (feature vcupp-batch-preload-features)
    (require feature))
  (dolist (form vcupp-batch-setup-forms)
    (eval form t))
  (dolist (pattern vcupp-batch-delete-elc-globs)
    (dolist (elc (file-expand-wildcards
                  (vcupp-batch--expand-file pattern) t))
      (delete-file elc))))

(defun vcupp-batch--load-config ()
  (dolist (file (vcupp-batch--load-files))
    (load-file (vcupp-batch--expand-file file)))
  (when vcupp-batch-post-load-function
    (funcall vcupp-batch-post-load-function)))

(defun vcupp-batch--record-vc-spec (name _keyword arg _rest _state)
  (setf (alist-get name vcupp-batch--desired-vc-specs nil nil #'eq)
        arg))

(defun vcupp-batch--record-install-spec-advice (name keyword arg rest state)
  (vcupp-batch--record-vc-spec name keyword arg rest state))

(defun vcupp-batch--reinstall-changed-vc-urls ()
  (message "Checking VC packages for source URL changes...")
  (dolist (pkg-alist-entry package-alist)
    (dolist (pkg-desc (cdr pkg-alist-entry))
      (when-let* (((package-vc-p pkg-desc))
                  (desired-arg (alist-get (package-desc-name pkg-desc)
                                          vcupp-batch--desired-vc-specs
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

(defun vcupp-batch--attach-vc-packages-to-branches ()
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

(defun vcupp-batch--clean-stale-vc-elc-files ()
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

(defun vcupp-batch-install-packages (&optional args)
  "Install and upgrade packages declared by the current config.

ARGS is an optional plist. Supported keys are `:root', `:load-files',
`:setup-forms', `:preload-features', `:delete-elc-globs',
`:post-load-function', `:post-install-functions', `:refresh-contents',
and `:package-native-compile'."
  (vcupp-batch--with-effective-args args
    (setq vcupp-batch--desired-vc-specs nil)
    (vcupp-batch--run-setup)
    (setq package-native-compile vcupp-batch-package-native-compile)
    (package-initialize)
    (require 'use-package)
    (when vcupp-batch-refresh-contents
      (package-refresh-contents))
    (advice-add 'use-package-handler/:vc :before
                #'vcupp-batch--record-install-spec-advice)
    (advice-add 'project-remember-projects-under :override #'ignore)
    (advice-add 'yes-or-no-p :override (lambda (&rest _) t))
    (vcupp-batch--load-config)
    (vcupp-batch--reinstall-changed-vc-urls)
    (vcupp-batch--attach-vc-packages-to-branches)
    (message "Upgrading VC packages to latest commits...")
    (package-vc-upgrade-all)
    (vcupp-batch--clean-stale-vc-elc-files)
    (dolist (fn vcupp-batch-post-install-functions)
      (funcall fn))))

(defun vcupp-batch-native-comp-all (&optional args)
  "Native-compile the configured Emacs files.

ARGS is an optional plist. Supported keys are `:root', `:load-files',
`:compile-files', `:setup-forms', `:preload-features',
`:delete-elc-globs', and `:post-load-function'."
  (vcupp-batch--with-effective-args args
    (unless (native-comp-available-p)
      (user-error "Native compilation is not available in this Emacs"))
    (vcupp-batch--run-setup)
    (package-initialize)
    (advice-add 'package-vc-install :override #'ignore)
    (vcupp-batch--load-config)
    (message "Native-compiling files...")
    (dolist (file (vcupp-batch--compile-files))
      (native-compile (vcupp-batch--expand-file file)))))

(provide 'vcupp-batch)
;;; vcupp-batch.el ends here
