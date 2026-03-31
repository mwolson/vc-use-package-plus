;;; native-comp-all.el --- Native-compile configured Emacs files -*- lexical-binding: t -*-

(eval-and-compile
  (let* ((source-file (or load-file-name buffer-file-name byte-compile-current-file))
         (source-dir (and source-file
                          (file-name-directory (expand-file-name source-file)))))
    (when source-dir
      (add-to-list 'load-path (expand-file-name ".." source-dir)))
    (require 'vcupp-native-comp)))

(vcupp-native-comp-all vcupp-batch-args)

(provide 'native-comp-all)
;;; native-comp-all.el ends here
