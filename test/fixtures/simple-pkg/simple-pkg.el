;;; simple-pkg.el --- Test fixture: standalone package -*- lexical-binding: t -*-

;; Version: 1.0
;; Package-Requires: ((emacs "29.1"))

;;; Code:

(defun simple-pkg-hello ()
  "Return a greeting."
  "hello from simple-pkg")

(provide 'simple-pkg)
;;; simple-pkg.el ends here
