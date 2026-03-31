;;; install-packages.el --- Install packages declared by an Emacs config -*- lexical-binding: t -*-

(eval-and-compile
  (let ((source-file (or load-file-name byte-compile-current-file buffer-file-name)))
    (load (expand-file-name "../vcupp-batch.el"
                            (file-name-directory source-file))
          nil nil t)))

(vcupp-batch-install-packages)

(provide 'install-packages)
;;; install-packages.el ends here
