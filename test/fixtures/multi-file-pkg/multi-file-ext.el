;;; multi-file-ext.el --- Test fixture: extension -*- lexical-binding: t -*-

;; Version: 1.0
;; Package-Requires: ((multi-file-pkg "1.0") (emacs "29.1"))

;;; Code:

(require 'multi-file-pkg)

(defun multi-file-ext-hello ()
  "Return a greeting from the extension."
  (concat (multi-file-pkg-hello) " from ext"))

(provide 'multi-file-ext)
;;; multi-file-ext.el ends here
