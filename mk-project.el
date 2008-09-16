;;;; mk-project.el --  Lightweight project handling
;;;;
;;;; Perform per-project operations: grep, TAGS, compile
;;;;
;;;; Admin:
;;;;   * Load project:   project-load
;;;;   * Quit project:   project-unload
;;;;   * Project status: project-status
;;;;
;;;; Operations:
;;;;   * Rebuild tags file: project-tags-build <C-c t>
;;;;   * Grep the project:  project-grep       <f6>
;;;;   * Build project:     project-compile    <f5>
;;;;

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

(defun replace-tail (str tail-str replacement)
  (if (string-match (concat tail-str "$")  str)
    (replace-match replacement t t str)
    str))

;; ---------------------------------------------------------------------
;; Project list 
;; ---------------------------------------------------------------------

(defvar mk-proj-list (make-hash-table :test 'equal))

(defun find-proj-config (proj-name)
  (gethash proj-name mk-proj-list))

(defun project-add (proj-name config-alist)
  "Assciate the settings in the alist <config-alist> with project <proj-name>"
  (puthash proj-name config-alist mk-proj-list))

;; ---------------------------------------------------------------------
;; Setup 
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

(defun project-load ()
  "Load a project's settings."
  (interactive)
  (catch 'project-load
    (let ((name (completing-read "Project Name: " mk-proj-list)))
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
      (project-index)
      (when mk-proj-startup-hooks
        (run-hooks 'mk-proj-startup-hooks)))))

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
;; Etags
;; ---------------------------------------------------------------------

(defun etags-refresh-callback (process event)
  "Visit tags table when the etags process finishes."
  (message "Etags process %s received event %s" process event)
  (when (string= event "finished\n")
    (visit-tags-table mk-proj-tags-file)))

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
    (concat (replace-tail name-expr "-o " "") "\\) ")))

(defun find-cmd-ignore-patterns (ignore-patterns)
  "Generate the -not ( -name <pat1> -o -name <pat2> ...) pattern for find cmd"
  (concat " -not " (find-cmd-src-patterns ignore-patterns)))

;; ---------------------------------------------------------------------
;; Grep 
;; ---------------------------------------------------------------------

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

;; ---------------------------------------------------------------------
;; Compile 
;; ---------------------------------------------------------------------

(defun project-compile (opts)
  "Run the compile command for this project."
  (interactive "sCompile options: ")
  (project-home)
  (compile (concat mk-proj-compile-cmd " " opts)))

(defun project-home ()
  "cd to the basedir of the current project"
  (interactive)
  (cd mk-proj-basedir))

;; ---------------------------------------------------------------------
;; Find-file 
;; ---------------------------------------------------------------------

(defconst mk-proj-fib-name "*file-index*")

(defun fib-clear ()
  "Clear the contents of the fib buffer"
  (aif (get-buffer mk-proj-fib-name)
    (with-current-buffer it
      (kill-region (point-min) (point-max))
      t)
    nil))

(defun fib-callback (process event)
  "Handle failure to complete fib building"
  (if (string= event "finished\n")
      (progn
        (buffer-enable-undo mk-proj-fib-name)
        (message "The %s buffer has been succesfully rebuilt" mk-proj-fib-name))
    (fib-clear)
    (message "Failed to generate the %s buffer!" mk-proj-fib-name)))

(defun project-index ()
  "Regenerate the *file-index* buffer that is used for project-find-file"
  (interactive)
  (message "Refreshing %s buffer (in the background)" mk-proj-fib-name)
  (fib-clear)
  (let ((find-cmd (concat "find " mk-proj-basedir " -type f " 
                          (find-cmd-ignore-patterns mk-proj-ignore-patterns)))
        (proc-name "index-process"))
    (when mk-proj-git-p
      (setq find-cmd (concat find-cmd " -not -path '*/.git*'")))
    (aif (get-buffer mk-proj-fib-name)
         (buffer-disable-undo)) ;; this is a large change we don't need to undo
    (start-process-shell-command proc-name mk-proj-fib-name find-cmd) 
    (set-process-sentinel (get-process proc-name) 'fib-callback)))

(defun* project-find-file (regex)
  "Find file in the current project matching the given regex.

The file list in buffer *file-index* is scanned for regex matches. If only
one match is found, the file is opened automatically. If more than one match
is found, this prompts for completion. See also: project-index."
  (interactive "sFind file in project matching: ")
  (unless (get-buffer mk-proj-fib-name)
    (when (yes-or-no-p "No file index exists for this project. Generate one? ")
      (project-index))
    (message "Cancelling project-find-file")
    (return-from "project-find-file" nil))
  (with-current-buffer mk-proj-fib-name
    (let ((matches nil))
      (goto-char (point-min))
      (dotimes (i (count-lines (point-min) (point-max)))
        (let ((bufline (buffer-substring (line-beginning-position) (line-end-position))))
          (when (string-match regex bufline)
            (push bufline matches))
          (forward-line)))
      (let ((match-cnt (length matches)))
        (cond
         ((= 0 match-cnt)
          (message "No matches for \"%s\" in this project" regex))
         ((= 1 match-cnt )
          (find-file (car matches)))
         (t
          (let ((file (completing-read "Multiple matches, pick one: " matches)))
            (when file
              (find-file file)))))))))

;; ---------------------------------------------------------------------
;; Run me!
;; ---------------------------------------------------------------------

(project-defaults)

(provide 'mk-project)
