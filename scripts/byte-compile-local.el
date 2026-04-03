;; byte-compile-local.el --- -*- lexical-binding: t -*-

(setq text-quoting-style 'straight) ; keep quotes ASCII for grep filters
(require 'package)
(package-load-all-descriptors)
(add-to-list 'load-path default-directory)

(defun my-byte-compile-local-package (lib-name lib-path)
  (let* ((lib-sym (intern lib-name))
         (pkg (cadr (assq lib-sym (package--alist))))
         (dir-or-file (file-name-concat default-directory lib-path)))
    (when-let* ((pkg)
                (pkg-dir (package-desc-dir pkg)))
      (setq load-path (remove pkg-dir load-path)))
    (cond ((string-match-p "\\.el\\'" dir-or-file)
           (message "Compiling %s..." (expand-file-name dir-or-file))
           (byte-compile-file dir-or-file))
          (t
           (error "Unsupported path type: %s" dir-or-file)))))

(apply #'my-byte-compile-local-package argv)

(provide 'byte-compile-local)
;;; byte-compile-local.el ends here
