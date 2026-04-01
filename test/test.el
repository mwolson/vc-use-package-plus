;;; test/test.el --- ERT tests for vcupp -*- lexical-binding: t; -*-

(eval-and-compile
  (let ((test-dir (file-name-directory
                   (or load-file-name buffer-file-name))))
    (add-to-list 'load-path test-dir)
    (add-to-list 'load-path (expand-file-name ".." test-dir))))

(require 'cl-lib)
(require 'ert)
(require 'vcupp)
(require 'vcupp-batch)
(require 'vcupp-native-comp)
(require 'vcupp-install-packages)
(require 'comp-run)

(defvar my-test-setup-marker nil)
(defvar my-test-load-order nil)
(defvar my-test-post-load-called nil)

(defun my-test--display-warning-fail (type message &optional _level _buffer-name)
  "Fail the current test for warning TYPE with MESSAGE."
  (ert-fail (format "Unexpected warning (%s): %s" type message)))

(advice-add 'display-warning :override #'my-test--display-warning-fail)

(defvar my-test-test-dir (file-name-directory
                          (or load-file-name buffer-file-name)))
(defvar my-test-project-dir
  (expand-file-name ".." my-test-test-dir))

(defun my-test--with-tmp-dir (fn)
  "Call FN with a temporary directory, cleaned up afterward."
  (let ((tmp (make-temp-file "vcupp-test-" t)))
    (unwind-protect
        (funcall fn tmp)
      (delete-directory tmp t))))

(defmacro my-test-with-tmp-dir (var &rest body)
  "Bind VAR to a temporary directory, evaluate BODY, then clean up."
  (declare (indent 1))
  `(my-test--with-tmp-dir (lambda (,var) ,@body)))

(defun my-test-write-el-file (dir name content)
  "Write an .el file NAME in DIR with CONTENT.  Return the path."
  (let ((path (expand-file-name name dir)))
    (with-temp-file path
      (insert content))
    path))

(defun my-test-write-stale-elc (el-file)
  "Byte-compile EL-FILE, then update the .el so the .elc is stale."
  (let ((elc-file (concat el-file "c")))
    (byte-compile-file el-file)
    (sleep-for 1.1)
    (with-temp-file el-file
      (insert-file-contents el-file))
    elc-file))

;; ---------------------------------------------------------------------------
;; vcupp.el -- :compile-files normalization
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-normalize-vc-arg/compile-files-single ()
  "Single :compile-files value is wrapped in a list."
  (let ((use-package-vc-prefer-newest t))
    (let ((result (vcupp--normalize-vc-arg
                   #'use-package-normalize--vc-arg
                   '(my-pkg :url "https://example.com" :compile-files "foo.el"))))
      (should (equal (plist-get (nth 1 result) :compile-files) '("foo.el"))))))

(ert-deftest vcupp-normalize-vc-arg/compile-files-list ()
  ":compile-files list passes through."
  (let ((use-package-vc-prefer-newest t))
    (let ((result (vcupp--normalize-vc-arg
                   #'use-package-normalize--vc-arg
                   '(my-pkg :url "https://example.com"
                            :compile-files ("a.el" "b.el")))))
      (should (equal (plist-get (nth 1 result) :compile-files)
                     '("a.el" "b.el"))))))

(ert-deftest vcupp-normalize-vc-arg/compile-files-quoted-list ()
  "Quoted :compile-files list is unquoted."
  (let ((use-package-vc-prefer-newest t))
    (let ((result (vcupp--normalize-vc-arg
                   #'use-package-normalize--vc-arg
                   '(my-pkg :url "https://example.com"
                            :compile-files '("a.el" "b.el")))))
      (should (equal (plist-get (nth 1 result) :compile-files)
                     '("a.el" "b.el"))))))

(ert-deftest vcupp-normalize-vc-arg/no-compile-files-delegates ()
  "Without :compile-files, delegates to the original normalizer."
  (let ((use-package-vc-prefer-newest t))
    (let ((result (vcupp--normalize-vc-arg
                   #'use-package-normalize--vc-arg
                   '(my-pkg :url "https://example.com"))))
      (should (equal (plist-get (nth 1 result) :url) "https://example.com"))
      (should-not (plist-member (nth 1 result) :compile-files)))))

(ert-deftest vcupp-normalize-vc-arg/rev-newest ()
  ":rev :newest normalizes to nil (track HEAD)."
  (let ((use-package-vc-prefer-newest nil))
    (let ((result (vcupp--normalize-vc-arg
                   #'use-package-normalize--vc-arg
                   '(my-pkg :url "https://example.com"
                            :compile-files "foo.el"
                            :rev :newest))))
      (should (null (nth 2 result))))))

(ert-deftest vcupp-normalize-vc-arg/rev-last-release ()
  ":rev :last-release passes through."
  (let ((use-package-vc-prefer-newest t))
    (let ((result (vcupp--normalize-vc-arg
                   #'use-package-normalize--vc-arg
                   '(my-pkg :url "https://example.com"
                            :compile-files "foo.el"
                            :rev :last-release))))
      (should (eq (nth 2 result) :last-release)))))

;; ---------------------------------------------------------------------------
;; vcupp.el -- file expansion and compile targets
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-expand-el-file-specs/glob ()
  "Glob patterns expand to matching .el files."
  (my-test-with-tmp-dir tmp
    (my-test-write-el-file tmp "foo.el" "(provide 'foo)")
    (my-test-write-el-file tmp "bar.el" "(provide 'bar)")
    (my-test-write-el-file tmp "foo-autoloads.el" "")
    (let ((files (vcupp--expand-el-file-specs tmp '("*.el"))))
      (should (= (length files) 2))
      (should (cl-every (lambda (f) (string-match-p "/\\(foo\\|bar\\)\\.el\\'" f))
                        files)))))

(ert-deftest vcupp-expand-el-file-specs/filters-generated ()
  "Generated files (-autoloads.el, -pkg.el) are excluded."
  (my-test-with-tmp-dir tmp
    (my-test-write-el-file tmp "foo.el" "(provide 'foo)")
    (my-test-write-el-file tmp "foo-autoloads.el" "")
    (my-test-write-el-file tmp "foo-pkg.el" "")
    (let ((files (vcupp--expand-el-file-specs tmp '("*.el"))))
      (should (= (length files) 1))
      (should (string-match-p "/foo\\.el\\'" (car files))))))

(ert-deftest vcupp-generated-el-file-p ()
  "Detects autoloads and pkg files."
  (should (vcupp--generated-el-file-p "foo-autoloads.el"))
  (should (vcupp--generated-el-file-p "bar-pkg.el"))
  (should-not (vcupp--generated-el-file-p "foo.el"))
  (should-not (vcupp--generated-el-file-p "foo-utils.el")))

;; ---------------------------------------------------------------------------
;; vcupp.el -- pre-release version handling
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-handle-pre-release/dev-suffix ()
  "-DEV suffix is stripped to produce a usable version."
  (let ((result (vcupp--handle-pre-release #'package-strip-rcs-id "0.3.3-DEV")))
    (should (equal (version-to-list result) '(0 3 3)))))

(ert-deftest vcupp-handle-pre-release/normal-version ()
  "Normal version strings pass through unchanged."
  (let ((result (vcupp--handle-pre-release #'package-strip-rcs-id "1.2.3")))
    (should (equal result "1.2.3"))))

(ert-deftest vcupp-handle-pre-release/nil-input ()
  "nil input returns nil."
  (should (null (vcupp--handle-pre-release #'package-strip-rcs-id nil))))

;; ---------------------------------------------------------------------------
;; vcupp.el -- vcupp-suppress-native-comp-jit
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-suppress-native-comp-jit/sets-variables ()
  "Sets native-comp variables when not in batch native-comp."
  (let ((vcupp-native-comp-active-p nil)
        (native-comp-async-report-warnings-errors t)
        (native-comp-jit-compilation t))
    (vcupp-suppress-native-comp-jit)
    (should (eq native-comp-async-report-warnings-errors 'silent))
    (should (null native-comp-jit-compilation))))

(ert-deftest vcupp-suppress-native-comp-jit/noop-when-active ()
  "No-op when vcupp-native-comp-active-p is set."
  (let ((vcupp-native-comp-active-p t)
        (native-comp-async-report-warnings-errors t)
        (native-comp-jit-compilation t))
    (vcupp-suppress-native-comp-jit)
    (should (eq native-comp-async-report-warnings-errors t))
    (should (eq native-comp-jit-compilation t))))

;; ---------------------------------------------------------------------------
;; vcupp-batch.el -- effective-args
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-batch-effective-args/defaults ()
  "Default values are used when no args are provided."
  (let ((vcupp-batch-args nil)
        (vcupp-batch-root (expand-file-name user-emacs-directory))
        (vcupp-batch-load-files nil)
        (vcupp-batch-compile-files nil)
        (vcupp-batch-setup-forms nil)
        (vcupp-batch-preload-features nil)
        (vcupp-batch-delete-elc-globs nil)
        (vcupp-batch-post-load-function nil)
        (vcupp-batch-post-install-functions nil)
        (vcupp-batch-refresh-contents t)
        (vcupp-batch-package-native-compile t))
    (let ((result (vcupp-batch-effective-args)))
      (should (equal (plist-get result :load-files) '("early-init.el" "init.el")))
      (should (equal (plist-get result :compile-files) '("early-init.el" "init.el")))
      (should (null (plist-get result :setup-forms)))
      (should (null (plist-get result :delete-elc-globs)))
      (should (eq (plist-get result :refresh-contents) t)))))

(ert-deftest vcupp-batch-effective-args/plist-overrides ()
  "Plist values override variable defaults."
  (let ((vcupp-batch-args nil)
        (vcupp-batch-root "/default/root/")
        (vcupp-batch-load-files nil)
        (vcupp-batch-compile-files nil)
        (vcupp-batch-setup-forms nil)
        (vcupp-batch-preload-features nil)
        (vcupp-batch-delete-elc-globs nil)
        (vcupp-batch-post-load-function nil)
        (vcupp-batch-post-install-functions nil)
        (vcupp-batch-refresh-contents t)
        (vcupp-batch-package-native-compile t))
    (let ((result (vcupp-batch-effective-args
                   '(:root "/my/config/"
                     :load-files ("a.el" "b.el")
                     :compile-files ("a.el")
                     :refresh-contents nil))))
      (should (equal (plist-get result :root) (expand-file-name "/my/config/")))
      (should (equal (plist-get result :load-files) '("a.el" "b.el")))
      (should (equal (plist-get result :compile-files) '("a.el")))
      (should (null (plist-get result :refresh-contents))))))

(ert-deftest vcupp-batch-effective-args/compile-files-defaults-to-load-files ()
  "compile-files falls back to load-files when not specified."
  (let ((vcupp-batch-args nil)
        (vcupp-batch-root "/root/")
        (vcupp-batch-load-files nil)
        (vcupp-batch-compile-files nil)
        (vcupp-batch-setup-forms nil)
        (vcupp-batch-preload-features nil)
        (vcupp-batch-delete-elc-globs nil)
        (vcupp-batch-post-load-function nil)
        (vcupp-batch-post-install-functions nil)
        (vcupp-batch-refresh-contents t)
        (vcupp-batch-package-native-compile t))
    (let ((result (vcupp-batch-effective-args
                   '(:load-files ("x.el" "y.el")))))
      (should (equal (plist-get result :compile-files) '("x.el" "y.el"))))))

;; ---------------------------------------------------------------------------
;; vcupp-batch.el -- expand-file
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-batch-expand-file/relative ()
  "Relative paths expand against vcupp-batch-root."
  (let ((vcupp-batch-root "/my/config/"))
    (should (equal (vcupp-batch-expand-file "init.el")
                   "/my/config/init.el"))))

(ert-deftest vcupp-batch-expand-file/absolute ()
  "Absolute paths pass through."
  (let ((vcupp-batch-root "/my/config/"))
    (should (equal (vcupp-batch-expand-file "/other/file.el")
                   "/other/file.el"))))

;; ---------------------------------------------------------------------------
;; vcupp-batch.el -- run-setup
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-batch-run-setup/sets-load-prefer-newer ()
  "run-setup always sets load-prefer-newer to t."
  (my-test-with-tmp-dir tmp
    (let ((vcupp-batch-root tmp)
          (vcupp-batch-preload-features nil)
          (vcupp-batch-setup-forms nil)
          (vcupp-batch-delete-elc-globs nil)
          (load-prefer-newer nil))
      (vcupp-batch-run-setup)
      (should (eq load-prefer-newer t)))))

(ert-deftest vcupp-batch-run-setup/evaluates-setup-forms ()
  "Setup forms are evaluated."
  (my-test-with-tmp-dir tmp
    (let ((vcupp-batch-root tmp)
          (vcupp-batch-preload-features nil)
          (vcupp-batch-setup-forms '((setq my-test-setup-marker 42)))
          (vcupp-batch-delete-elc-globs nil))
      (setq my-test-setup-marker nil)
      (vcupp-batch-run-setup)
      (should (= my-test-setup-marker 42)))))

(ert-deftest vcupp-batch-run-setup/deletes-elc-globs ()
  "Matching .elc files are deleted."
  (my-test-with-tmp-dir tmp
    (let ((init-dir (expand-file-name "init" tmp)))
      (make-directory init-dir)
      (my-test-write-el-file init-dir "foo.elc" "")
      (my-test-write-el-file init-dir "bar.elc" "")
      (my-test-write-el-file init-dir "baz.el" "(provide 'baz)")
      (let ((vcupp-batch-root tmp)
            (vcupp-batch-preload-features nil)
            (vcupp-batch-setup-forms nil)
            (vcupp-batch-delete-elc-globs '("init/*.elc")))
        (vcupp-batch-run-setup)
        (should-not (file-exists-p (expand-file-name "init/foo.elc" tmp)))
        (should-not (file-exists-p (expand-file-name "init/bar.elc" tmp)))
        (should (file-exists-p (expand-file-name "init/baz.el" tmp)))))))

;; ---------------------------------------------------------------------------
;; vcupp-batch.el -- load-config
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-batch-load-config/loads-files ()
  "Config files are loaded in order."
  (my-test-with-tmp-dir tmp
    (my-test-write-el-file tmp "a.el"
                           "(push 'a my-test-load-order)\n(provide 'a)")
    (my-test-write-el-file tmp "b.el"
                           "(push 'b my-test-load-order)\n(provide 'b)")
    (setq my-test-load-order nil)
    (let ((vcupp-batch-root tmp)
          (vcupp-batch-load-files '("a.el" "b.el"))
          (vcupp-batch-post-load-function nil))
      (vcupp-batch-load-config)
      (should (equal my-test-load-order '(b a))))))

(ert-deftest vcupp-batch-load-config/calls-post-load-function ()
  "Post-load function is called after loading."
  (my-test-with-tmp-dir tmp
    (my-test-write-el-file tmp "a.el" "(provide 'a)")
    (setq my-test-post-load-called nil)
    (let ((vcupp-batch-root tmp)
          (vcupp-batch-load-files '("a.el"))
          (vcupp-batch-post-load-function
           (lambda () (setq my-test-post-load-called t))))
      (vcupp-batch-load-config)
      (should my-test-post-load-called))))

;; ---------------------------------------------------------------------------
;; vcupp-batch.el -- post-install runner
;; ---------------------------------------------------------------------------

(defvar my-test-post-install-marker nil)

(ert-deftest vcupp-batch-run-post-install/evaluates-forms ()
  "Post-install forms are evaluated."
  (let ((my-test-post-install-marker nil)
        (vcupp-batch-post-install-functions
         '((setq my-test-post-install-marker 'done))))
    (vcupp-batch-run-post-install)
    (should (eq my-test-post-install-marker 'done))))

(ert-deftest vcupp-batch-run-post-install/calls-functions ()
  "Post-install function entries are called."
  (let ((my-test-post-install-marker nil)
        (vcupp-batch-post-install-functions
         (list (lambda () (setq my-test-post-install-marker 'done)))))
    (vcupp-batch-run-post-install)
    (should (eq my-test-post-install-marker 'done))))

;; ---------------------------------------------------------------------------
;; vcupp-batch.el -- with-effective-args macro
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-batch-with-effective-args/binds-variables ()
  "Macro binds batch variables from plist."
  (let ((vcupp-batch-args nil)
        (vcupp-batch-root "/default/")
        (vcupp-batch-load-files nil)
        (vcupp-batch-compile-files nil)
        (vcupp-batch-setup-forms nil)
        (vcupp-batch-preload-features nil)
        (vcupp-batch-delete-elc-globs nil)
        (vcupp-batch-post-load-function nil)
        (vcupp-batch-post-install-functions nil)
        (vcupp-batch-refresh-contents t)
        (vcupp-batch-package-native-compile t))
    (vcupp-batch-with-effective-args '(:root "/test/" :load-files ("x.el"))
      (should (equal vcupp-batch-root (expand-file-name "/test/")))
      (should (equal vcupp-batch-load-files '("x.el"))))))

;; ---------------------------------------------------------------------------
;; vcupp-batch.el -- load-prefer-newer with stale .elc
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-batch-run-setup/load-prefer-newer-bypasses-stale-elc ()
  "With load-prefer-newer, loading prefers .el over stale .elc."
  (my-test-with-tmp-dir tmp
    (let* ((el-file (my-test-write-el-file
                     tmp "my-stale-lib.el"
                     ";;; my-stale-lib.el --- -*- lexical-binding: t -*-\n(defvar my-stale-lib-value \"original\")\n(provide 'my-stale-lib)\n"))
           (elc-file (concat el-file "c")))
      (byte-compile-file el-file)
      (should (file-exists-p elc-file))
      (sleep-for 1.1)
      (with-temp-file el-file
        (insert ";;; my-stale-lib.el --- -*- lexical-binding: t -*-\n(defvar my-stale-lib-value \"modified\")\n(provide 'my-stale-lib)\n"))
      (let ((vcupp-batch-root tmp)
            (vcupp-batch-preload-features nil)
            (vcupp-batch-setup-forms nil)
            (vcupp-batch-delete-elc-globs nil)
            (load-prefer-newer nil))
        (vcupp-batch-run-setup)
        (add-to-list 'load-path tmp)
        (setq features (delq 'my-stale-lib features))
        (require 'my-stale-lib)
        (should (equal (symbol-value 'my-stale-lib-value) "modified"))))))

;; ---------------------------------------------------------------------------
;; vcupp-native-comp.el -- active-p lifecycle
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-native-comp-active-p/initially-nil ()
  "vcupp-native-comp-active-p starts as nil."
  (should (null vcupp-native-comp-active-p)))

;; ---------------------------------------------------------------------------
;; vcupp-native-comp.el -- compile-angel state management
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-native-comp-enable-compile-angel/nil-input ()
  "Returns nil when compile-angel is not available."
  (should (null (vcupp-native-comp--enable-compile-angel nil))))

(ert-deftest vcupp-native-comp-disable-compile-angel/nil-state ()
  "No-op when state is nil."
  (vcupp-native-comp--disable-compile-angel nil))

(ert-deftest vcupp-native-comp-disable-compile-angel/empty-state ()
  "No-op when state has :enabled nil."
  (vcupp-native-comp--disable-compile-angel '(:enabled nil)))

;; ---------------------------------------------------------------------------
;; vcupp-native-comp.el -- use-compile-angel-p
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-native-comp-use-compile-angel-p/default ()
  "Defaults to vcupp-native-comp-use-compile-angel."
  (let ((vcupp-native-comp-use-compile-angel t))
    (should (vcupp-native-comp--use-compile-angel-p '())))
  (let ((vcupp-native-comp-use-compile-angel nil))
    (should-not (vcupp-native-comp--use-compile-angel-p '()))))

(ert-deftest vcupp-native-comp-use-compile-angel-p/plist-override ()
  "Plist :use-compile-angel overrides the default."
  (let ((vcupp-native-comp-use-compile-angel t))
    (should-not (vcupp-native-comp--use-compile-angel-p
                 '(:use-compile-angel nil))))
  (let ((vcupp-native-comp-use-compile-angel nil))
    (should (vcupp-native-comp--use-compile-angel-p
             '(:use-compile-angel t)))))

;; ---------------------------------------------------------------------------
;; vcupp.el -- package activation helper
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-activate-package/activates-installed-package ()
  "Activates an installed package when present in `package-alist'."
  (let* ((pkg-desc (package-desc-create
                    :name 'foo
                    :version '(1 0)
                    :kind 'vc
                    :dir "/tmp/foo"))
         (package-alist (list (list 'foo pkg-desc)))
         (activated nil))
    (cl-letf (((symbol-function 'package-activate-1)
               (lambda (pkg &rest _args)
                 (setq activated pkg))))
      (vcupp-activate-package 'foo))
    (should (eq activated pkg-desc))))

(ert-deftest vcupp-activate-package/noop-when-missing ()
  "Does nothing when the package is not present in `package-alist'."
  (let ((package-alist nil)
        (activated nil))
    (cl-letf (((symbol-function 'package-activate-1)
               (lambda (&rest _args)
                 (setq activated t))))
      (vcupp-activate-package 'foo))
    (should-not activated)))

;; ---------------------------------------------------------------------------
;; vcupp-install-packages.el -- active-p lifecycle
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-install-packages-active-p/initially-nil ()
  "vcupp-install-packages-active-p starts as nil."
  (should (null vcupp-install-packages-active-p)))

;; ---------------------------------------------------------------------------
;; vcupp.el -- vcupp-ensure-packages-on-install
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-ensure-packages-on-install/sets-ensure-when-active ()
  "Sets use-package-always-ensure when install sentinel is active."
  (let ((vcupp-install-packages-active-p t)
        (use-package-always-ensure nil))
    (vcupp-ensure-packages-on-install)
    (should (eq use-package-always-ensure t))))

(ert-deftest vcupp-ensure-packages-on-install/noop-when-inactive ()
  "No-op when vcupp-install-packages-active-p is nil."
  (let ((vcupp-install-packages-active-p nil)
        (use-package-always-ensure nil))
    (vcupp-ensure-packages-on-install)
    (should (null use-package-always-ensure))))

;; ---------------------------------------------------------------------------
;; vcupp-install-packages.el -- VC spec recording
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-install-packages-record-vc-spec ()
  "Recording a VC spec stores it in the alist."
  (let ((vcupp-install-packages--desired-vc-specs nil))
    (vcupp-install-packages--record-vc-spec
     'my-pkg nil '(my-pkg (:url "https://example.com") nil) nil nil)
    (should (equal (alist-get 'my-pkg vcupp-install-packages--desired-vc-specs)
                   '(my-pkg (:url "https://example.com") nil)))))

;; ---------------------------------------------------------------------------
;; vcupp-install-packages.el -- stale .elc cleanup
;; ---------------------------------------------------------------------------

(defconst my-test-el-header
  ";;; foo.el --- test -*- lexical-binding: t -*-\n"
  "Standard header for test .el files to avoid byte-compile warnings.")

(ert-deftest vcupp-install-packages-clean-stale-elc/removes-stale ()
  "Stale .elc files are deleted when .el is newer."
  (my-test-with-tmp-dir tmp
    (let* ((el-file (my-test-write-el-file
                     tmp "foo.el"
                     (concat my-test-el-header "(provide 'foo)\n")))
           (elc-file (concat el-file "c"))
           (warning-minimum-level :error))
      (byte-compile-file el-file)
      (should (file-exists-p elc-file))
      (sleep-for 1.1)
      (with-temp-file el-file
        (insert my-test-el-header "(provide 'foo)\n"))
      (should (file-newer-than-file-p el-file elc-file))
      (let* ((pkg-name 'foo)
             (pkg-desc (package-desc-create
                        :name pkg-name
                        :version '(1 0)
                        :kind 'vc
                        :dir tmp))
             (package-alist (list (list pkg-name pkg-desc))))
        (cl-letf (((symbol-function 'package-vc-p) (lambda (_) t)))
          (vcupp-install-packages--clean-stale-vc-elc-files))
        (should-not (file-exists-p elc-file))
        (should (file-exists-p el-file))))))

(ert-deftest vcupp-install-packages-clean-stale-elc/keeps-fresh ()
  "Fresh .elc files are kept."
  (my-test-with-tmp-dir tmp
    (let* ((el-file (my-test-write-el-file
                     tmp "foo.el"
                     (concat my-test-el-header "(provide 'foo)\n")))
           (elc-file (concat el-file "c"))
           (warning-minimum-level :error))
      (byte-compile-file el-file)
      (should (file-exists-p elc-file))
      (should-not (file-newer-than-file-p el-file elc-file))
      (let* ((pkg-name 'foo)
             (pkg-desc (package-desc-create
                        :name pkg-name
                        :version '(1 0)
                        :kind 'vc
                        :dir tmp))
             (package-alist (list (list pkg-name pkg-desc))))
        (cl-letf (((symbol-function 'package-vc-p) (lambda (_) t)))
          (vcupp-install-packages--clean-stale-vc-elc-files))
        (should (file-exists-p elc-file))))))

;; ---------------------------------------------------------------------------
;; vcupp-batch.el -- plist-value helper
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-batch-plist-value/present ()
  "Returns plist value when key is present."
  (should (equal (vcupp-batch--plist-value '(:foo 42) :foo 99) 42)))

(ert-deftest vcupp-batch-plist-value/present-nil ()
  "Returns nil when key is present with nil value (not fallback)."
  (should (null (vcupp-batch--plist-value '(:foo nil) :foo 99))))

(ert-deftest vcupp-batch-plist-value/absent ()
  "Returns fallback when key is absent."
  (should (equal (vcupp-batch--plist-value '(:bar 1) :foo 99) 99)))

;; ---------------------------------------------------------------------------
;; vcupp.el -- compile-files keyword registration
;; ---------------------------------------------------------------------------

(ert-deftest vcupp-compile-files-keyword-registered ()
  ":compile-files is registered in use-package-vc-valid-keywords."
  (should (memq :compile-files use-package-vc-valid-keywords)))

;;; test/test.el ends here
