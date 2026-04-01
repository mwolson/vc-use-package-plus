;;; vcupp-install-packages.el --- Install packages declared by an Emacs config -*- lexical-binding: t -*-

;; Author: Michael Olson
;; SPDX-License-Identifier: GPL-3.0-or-later
;; URL: https://github.com/mwolson/vcupp

;;; Commentary:

;; Batch package installation with VC URL change detection, detached-HEAD
;; recovery, and stale .elc cleanup.  See the vcupp README for usage.

;;; Code:

(require 'vcupp-batch)

(defvar vcupp-install-packages-active-p nil
  "Non-nil while `vcupp-install-packages' is running.
User configs can check this with `bound-and-true-p' to enable
`use-package-always-ensure' only during batch installation.")

(defvar vcupp-install-packages--desired-vc-specs nil
  "Normalized VC specs declared by `use-package' during this run.")

(defun vcupp-install-packages--record-vc-spec (name _keyword arg _rest _state)
  "Store the normalized VC spec ARG for package NAME."
  (setf (alist-get name vcupp-install-packages--desired-vc-specs nil nil #'eq)
        arg))

(defun vcupp-install-packages--record-install-spec-advice (name keyword arg rest state)
  "Advice wrapper that records the VC spec for NAME.
KEYWORD, ARG, REST, and STATE are forwarded from `use-package-handler/:vc'."
  (vcupp-install-packages--record-vc-spec name keyword arg rest state))

(defun vcupp-install-packages--reinstall-changed-vc-urls ()
  "Reinstall VC packages whose configured source URL has changed."
  (message "Checking VC packages for source URL changes...")
  (dolist (pkg-alist-entry package-alist)
    (dolist (pkg-desc (cdr pkg-alist-entry))
      (when-let* (((package-vc-p pkg-desc))
                  (desired-arg (alist-get (package-desc-name pkg-desc)
                                          vcupp-install-packages--desired-vc-specs
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

(defun vcupp-install-packages--attach-vc-packages-to-branches ()
  "Check out a tracking branch for VC packages stuck on detached HEAD."
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

(defun vcupp-install-packages--wait-for-upgrade (result)
  "Block until async package upgrade RESULT is complete."
  (when (processp result)
    (while (process-live-p result)
      (accept-process-output result 1))))

(defun vcupp-install-packages--upgrade-vc-packages ()
  "Pull latest commits for all VC packages synchronously.
Waits for each `package-vc-upgrade' process before continuing so
packages are fully upgraded and reactivated before the batch
script moves on."
  (message "Upgrading VC packages to latest commits...")
  (dolist (package package-alist)
    (dolist (pkg-desc (cdr package))
      (when (package-vc-p pkg-desc)
        (vcupp-install-packages--wait-for-upgrade
         (package-vc-upgrade pkg-desc)))))
  (message "Done upgrading packages."))

(defun vcupp-install-packages--clean-stale-vc-elc-files ()
  "Delete `.elc' files from VC packages where the `.el' is newer."
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

(defun vcupp-install-packages (&optional args)
  "Install and upgrade packages declared by the current config.

ARGS is an optional plist.  Supported keys are `:root', `:load-files',
`:setup-forms', `:preload-features', `:delete-elc-globs',
`:post-load-function', `:post-install-functions', `:refresh-contents',
and `:package-native-compile'."
  (vcupp-batch-with-effective-args args
    (setq vcupp-install-packages--desired-vc-specs nil)
    (vcupp-batch-run-setup)
    (setq package-native-compile vcupp-batch-package-native-compile)
    (package-initialize)
    (require 'use-package)
    (when vcupp-batch-refresh-contents
      (package-refresh-contents))
    (advice-add 'use-package-handler/:vc :before
                #'vcupp-install-packages--record-install-spec-advice)
    (advice-add 'project-remember-projects-under :override #'ignore)
    (advice-add 'yes-or-no-p :override #'always)
    (setq vcupp-install-packages-active-p t)
    (unwind-protect
        (progn
          (vcupp-batch-load-config)
          (vcupp-install-packages--reinstall-changed-vc-urls)
          (vcupp-install-packages--attach-vc-packages-to-branches)
          (vcupp-install-packages--upgrade-vc-packages)
          (vcupp-install-packages--clean-stale-vc-elc-files)
          (dolist (fn vcupp-batch-post-install-functions)
            (funcall fn)))
      (setq vcupp-install-packages-active-p nil))))

(provide 'vcupp-install-packages)
;;; vcupp-install-packages.el ends here
