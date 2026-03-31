;;; native-comp-all.el --- Native-compile configured Emacs files -*- lexical-binding: t -*-

(eval-and-compile
  (let ((source-file (or load-file-name byte-compile-current-file buffer-file-name)))
    (load (expand-file-name "../vcupp-batch.el"
                            (file-name-directory source-file))
          nil nil t)))

(vcupp-batch-native-comp-all)

(provide 'native-comp-all)
;;; native-comp-all.el ends here
