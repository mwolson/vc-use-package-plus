;;; native-comp-all.el --- Native-compile configured Emacs files -*- lexical-binding: t -*-

(load (expand-file-name "../vc-use-package-plus-batch"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil nil t)

(vc-use-package-plus-batch-native-comp-all)

(provide 'native-comp-all)
;;; native-comp-all.el ends here
