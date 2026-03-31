;;; install-packages.el --- Install packages declared by an Emacs config -*- lexical-binding: t -*-

(load (expand-file-name "../vc-use-package-plus-batch"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil t)

(vc-use-package-plus-batch-install-packages)

(provide 'install-packages)
;;; install-packages.el ends here
