;;;; mk-project.el --  Lightweight project handling

;;;; Define new wrapper fns (grep, tags, etc) that use new vars to customize
;;;; their operations. Don't touch std emacs vars or fns. On project init,
;;;; set vars, set keybindings.
;;;;
;;;; Operations:
;;;;   * Rebuild tags file: project-tags-build
;;;;   * Grep the project:  project-grep
;;;;   * Build project:     project-compile
;;;;
;;;; Admin:
;;;;   * Load project:   project-load
;;;;   * Quit project:   project-unload
;;;;   * Project status: project-status

;; ---------------------------------------------------------------------
;; Projects
;; ---------------------------------------------------------------------

(defvar mk-proj-list (make-hash-table :test 'equal))

(defun find-proj-config (proj-name)
  (gethash proj-name mk-proj-list))

(defun add-proj-config (proj-name config-alist)
  (puthash proj-name config-alist mk-proj-list))

(add-proj-config "qrev" 
                 '((name "qrev")
                   (basedir "/home/mk/code/lisp/qrev/")
                   (src-patterns ("*.lisp"))
                   (ignore-patterns ("*.fasl"))
                   (tags-file "/home/mk/code/lisp/qrev/TAGS")
                   (git-p t)
                   (compile-cmd "make -k")
                   (startup-hook qrev-startup-hook)
                   (shutdown-hook qrev-shutdown-hook)))

(defun qrev-startup-hook () (message "Qrev it up, baby!"))

(defun qrev-shutdown-hook () (message "Adios, qrev"))

(add-proj-config "12static" 
                 '((name "12static")
                   (basedir "/localdisk/viewstore/matthewk_mcp_core_12.0_3_static/mcp/")
                   (src-patterns ("*.java" "*.jsp"))
                   (ignore-patterns ("*.class" "*.wsdl"))
                   (tags-file "/localdisk/viewstore/matthewk_mcp_core_12.0_3_static/mcp/TAGS")
                   (git-p t)
                   (compile-cmd "mcpant 12static")
                   (startup-hook nil)
                   (shutdown-hook nil)))

(add-proj-config "12dyn" 
                 '((name "12dyn")
                   (basedir "/mcp/")
                   (src-patterns ("*.java" "*.jsp"))
                   (ignore-patterns ("*.class" "*.wsdl"))
                   (tags-file "/home/matthewk/.TAGS12")
                   (git-p nil)
                   (compile-cmd "mcpant 12dyn")
                   (startup-hook nil)
                   (shutdown-hook nil)))

;; ---------------------------------------------------------------------
;; Utils
;; ---------------------------------------------------------------------

(defmacro aif (test true-body &rest false-body)
  "Evaluate TRUE-BODY or FALSE-BODY depending on value of TEST.
If TEST returns non-nil, bind `it' to the value, and evaluate
TRUE-BODY.  Otherwise, evaluate forms in FALSE-BODY as if in `progn'.
Compare with `if'."
  (let ((sym (gensym "--ibuffer-aif-")))
    `(let ((,sym ,test))
       (if ,sym
	   (let ((it ,sym))
	     ,true-body)
	 (progn
	   ,@false-body)))))

(defun trim-from-end (str tail)
  "Remove tail from the end of str"
  (let ((tail-len (length tail))
        (str-len (length str)))
    (if (string= (substring str (- str-len tail-len)) tail)
        (substring str 0 (- str-len tail-len))
      str)))

;; ---------------------------------------------------------------------
;; Setup fns
;; ---------------------------------------------------------------------

(defun project-defaults ()
  "Set all default values for vars and keybindings"
  (setq mk-proj-name nil
        mk-proj-basedir (getenv "HOME")
        mk-proj-src-patterns nil
        mk-proj-ignore-patterns nil
        mk-proj-git-p nil
        mk-proj-tags-file nil
        mk-proj-compile-cmd "make -k"
        mk-proj-startup-hooks nil
        mk-proj-shutdown-hooks nil)
  (cd mk-proj-basedir)
  (global-set-key [f5] 'compile)
  (global-set-key [f6] 'grep-find)
  (global-unset-key (kbd "C-c t")))

(defun config-val (key config-alist)
  "Get a config value from a config alist, nil if doesn't exist"
  (if (assoc key config-alist)
    (car (cdr (assoc key config-alist)))
    nil))

(defun project-load-vars (proj-alist)
  "Set vars from config alist"
  (project-defaults)
  ;; required vars
  (setq mk-proj-name (config-val 'name proj-alist))
  (setq mk-proj-basedir (config-val 'basedir proj-alist))
  ;; optional vars
  (aif (config-val 'src-patterns proj-alist) (setq mk-proj-src-patterns it))
  (aif (config-val 'ignore-patterns proj-alist) (setq mk-proj-ignore-patterns it))
  (aif (config-val 'git-p proj-alist) (setq mk-proj-git-p it))
  (aif (config-val 'tags-file proj-alist) (setq mk-proj-tags-file it))
  (aif (config-val 'compile-cmd proj-alist) (setq mk-proj-compile-cmd it))
  (aif (config-val 'startup-hook proj-alist) (setq mk-proj-startup-hooks (list it)))
  (aif (config-val 'shutdown-hook proj-alist) (setq mk-proj-shutdown-hooks (list it))))

(defun project-load (name)
  "Load a project <name>'s settings."
  (interactive "sProject Alist Name: ")
  (catch 'project-load
    (aif (find-proj-config name)
         (project-load-vars it)
         (message "Project %s does not exist!" name)
         (throw 'project-load t))
    (when (not (file-directory-p mk-proj-basedir))
      (message "Base directory %s does not exist!" mk-proj-basedir)
      (throw 'project-load t))
    (cd mk-proj-basedir)
    (when mk-proj-tags-file (visit-tags-table mk-proj-tags-file))
    (global-set-key [f5] 'project-compile)
    (global-set-key [f6] 'project-grep)
    (global-set-key (kbd "C-c t") 'project-tags-build)
    (when mk-proj-startup-hooks
      (run-hooks 'mk-proj-startup-hooks))))

(defun project-unload ()
  "Revert to default project settings."
  (interactive)
  (when mk-proj-shutdown-hooks
    (run-hooks 'mk-proj-shutdown-hooks))
  (project-defaults)
  (message "Project settings have been cleared"))

(defun project-status ()
  "View project's variables."
  (interactive)
  (message "Name=%s; Basedir=%s; Src=%s; Ignore=%s; Git-p=%s; Tags=%s; Compile=%s; Startup=%s; Shutdown=%s"
           mk-proj-name mk-proj-basedir mk-proj-src-patterns mk-proj-ignore-patterns mk-proj-git-p
           mk-proj-tags-file mk-proj-compile-cmd mk-proj-startup-hooks mk-proj-shutdown-hooks))

;; ---------------------------------------------------------------------
;; Operational fns
;; ---------------------------------------------------------------------

(defun etags-refresh-callback (process event)
  "Visit tags table when the etags process finishes."
  (message "Etags process %s received event %s" process event)
  (visit-tags-table mk-proj-tags-file)) ;; TODO: only visit tags when process completes sucessfully

(defun project-tags-build ()
  "Regenerate the projects TAG file. Runs in the background."
  (interactive)
  (if mk-proj-tags-file
    (progn
      (cd mk-proj-basedir)
      (message "Refreshing TAGS file %s (in the background)" mk-proj-tags-file)
      (let ((etags-cmd (concat "find " mk-proj-basedir " -type f " (find-cmd-src-patterns mk-proj-src-patterns)
                               " | etags -o " mk-proj-tags-file " - "))
            (proc-name "etags-process"))
        (start-process-shell-command proc-name "*etags*" etags-cmd)
        (set-process-sentinel (get-process proc-name) 'etags-refresh-callback)))
    (message "mk-proj-tags-file is not set")))

(defun find-cmd-src-patterns (src-patterns)
  "Generate the ( -name <pat1> -o -name <pat2> ...) pattern for find cmd"
  (let ((name-expr " \\("))
    (dolist (pat src-patterns)
      (setq name-expr (concat name-expr " -name \"" pat "\" -o ")))
    (concat (trim-from-end name-expr "-o ") "\\) ")))

(defun project-grep (s)
  "Run find-grep using this project's settings for basedir and src files."
  (interactive "sGrep project for: ")
  (cd mk-proj-basedir)
  (let ((find-cmd (concat "find . -type f"))
        (grep-cmd (concat "grep -i -n \"" s "\"")))
    (when mk-proj-src-patterns
      (setq find-cmd (concat find-cmd (find-cmd-src-patterns mk-proj-src-patterns))))
    (when mk-proj-tags-file
      (setq find-cmd (concat find-cmd " -not -name 'TAGS'")))
    (when mk-proj-git-p
      (setq find-cmd (concat find-cmd " -not -path '*/.git*'")))
    (grep-find (concat find-cmd " -print0 | xargs -0 -e " grep-cmd))))

(defun project-compile (opts)
  "Run the compile command for this project."
  (interactive "sCompile options: ")
  (cd mk-proj-basedir)
  (compile (concat mk-proj-compile-cmd " " opts)))

;; ---------------------------------------------------------------------
;; Run me!
;; ---------------------------------------------------------------------

(project-defaults)
