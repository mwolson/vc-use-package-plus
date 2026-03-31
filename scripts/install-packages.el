;;; install-packages.el --- Install packages declared by an Emacs config -*- lexical-binding: t -*-

(eval-and-compile
  (let* ((source-file (or load-file-name buffer-file-name byte-compile-current-file))
         (source-dir (and source-file
                          (file-name-directory (expand-file-name source-file)))))
    (when source-dir
      (add-to-list 'load-path (expand-file-name ".." source-dir)))
    (require 'vcupp-batch)))

(vcupp-batch-install-packages)

(provide 'install-packages)
;;; install-packages.el ends here
