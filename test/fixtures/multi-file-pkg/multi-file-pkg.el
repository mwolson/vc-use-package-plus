;;; multi-file-pkg.el --- Test fixture: main file -*- lexical-binding: t -*-

;; Version: 1.0
;; Package-Requires: ((emacs "29.1"))

;;; Code:

(defun multi-file-pkg-hello ()
  "Return a greeting."
  "hello")

(provide 'multi-file-pkg)
;;; multi-file-pkg.el ends here
