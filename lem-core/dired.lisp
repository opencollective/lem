(defpackage :lem.dired
  (:use :cl :lem)
  (:export :dired-header-attribute
           :dired-file-attribute
           :dired-directory-attribute
           :dired-link-attribute
           :dired
           :dired-buffer))
(in-package :lem.dired)

(define-attribute dired-header-attribute
  (:light :foreground "dark green")
  (:dark :foreground "green"))

(define-attribute dired-file-attribute
  (t))

(define-attribute dired-directory-attribute
  (:light :foreground "blue" :bold-p t)
  (:dark :foreground "sky blue"))

(define-attribute dired-link-attribute
  (:light :foreground "dark green")
  (:dark :foreground "green"))

(define-major-mode dired-mode ()
    (:name "dired"
     :keymap *dired-mode-keymap*))

(define-key *dired-mode-keymap* "q" 'quit-window)
(define-key *dired-mode-keymap* "g" 'dired-update-buffer)
(define-key *dired-mode-keymap* "^" 'dired-up-directory)
(define-key *dired-mode-keymap* "C-m" 'dired-find-file)
(define-key *dired-mode-keymap* "Spc" 'dired-read-file)
(define-key *dired-mode-keymap* "o" 'dired-find-file-other-window)

(define-key *dired-mode-keymap* "n" 'dired-next-line)
(define-key *dired-mode-keymap* "p" 'dired-previous-line)
(define-key *dired-mode-keymap* ">" 'dired-next-directory-line)
(define-key *dired-mode-keymap* "<" 'dired-previous-directory-line)

(define-key *dired-mode-keymap* "m" 'dired-mark-and-next-line)
(define-key *dired-mode-keymap* "u" 'dired-unmark-and-next-line)
(define-key *dired-mode-keymap* "U" 'dired-unmark-and-previous-line)
(define-key *dired-mode-keymap* "t" 'dired-toggle-marks)
(define-key *dired-mode-keymap* "* !" 'dired-unmark-all)
(define-key *dired-mode-keymap* "* %" 'dired-mark-regexp)

(define-key *dired-mode-keymap* "Q" 'dired-query-replace)

(define-key *dired-mode-keymap* "D" 'dired-delete-files)
(define-key *dired-mode-keymap* "C" 'dired-copy-files)
(define-key *dired-mode-keymap* "R" 'dired-rename-files)
(define-key *dired-mode-keymap* "+" 'dired-mkdir)

(defun adjust-point (point)
  (let ((charpos (buffer-value point 'start-file-charpos 0)))
    (line-offset point 0 charpos)))

(defun start-point (buffer)
  (with-point ((p (buffer-point buffer)))
    (buffer-start p)
    (or (line-offset p 3) p)
    (adjust-point p)))

(defun move-to-start-point (point)
  (move-point point (start-point (point-buffer point))))

(defun dired-first-line-p (point)
  (point<= point (start-point (point-buffer point))))

(defun dired-last-line-p (point)
  (last-line-p point))

(defun dired-range-p (point)
  (and (point<= (start-point (point-buffer point)) point)
       (not (end-buffer-p point))))

(define-command dired-update-buffer () ()
  (update (current-buffer)))

(define-command dired-up-directory () ()
  (switch-to-buffer
   (dired-buffer
    (uiop:pathname-parent-directory-pathname
     (buffer-directory)))))

(define-command dired-find-file () ()
  (select-file 'find-file))

(define-command dired-read-file () ()
  (select-file 'read-file))

(define-command dired-find-file-other-window () ()
  (select-file (lambda (file)
                 (setf (current-window)
                       (pop-to-buffer (find-file-buffer file))))))

(define-command dired-next-line (n) ("p")
  (let ((point (current-point)))
    (line-offset point n)
    (when (dired-first-line-p point)
      (move-to-start-point point))
    (when (last-line-p point)
      (line-offset point -1))
    (adjust-point point)))

(define-command dired-previous-line (n) ("p")
  (let ((point (current-point)))
    (line-offset point (- n))
    (when (dired-first-line-p point)
      (move-to-start-point point))
    (adjust-point point)))

(define-command dired-next-directory-line (n) ("p")
  (with-point ((cur-point (current-point)))
    (loop
      (when (dired-last-line-p cur-point)
        (return))
      (line-offset cur-point 1)
      (when (and (eq :directory (text-property-at cur-point 'type))
                 (>= 0 (decf n)))
        (move-point (current-point) cur-point)
        (return)))
    (adjust-point (current-point))))

(define-command dired-previous-directory-line (n) ("p")
  (with-point ((cur-point (current-point)))
    (loop
      (when (dired-first-line-p cur-point)
        (return))
      (line-offset cur-point -1)
      (when (and (eq :directory (text-property-at cur-point 'type))
                 (>= 0 (decf n)))
        (move-point (current-point) cur-point)
        (return)))
    (adjust-point (current-point))))

(define-command dired-mark-and-next-line (n) ("p")
  (loop :repeat n
        :do (mark-current-line t)
            (dired-next-line 1)))

(define-command dired-unmark-and-next-line (n) ("p")
  (loop :repeat n
        :do (mark-current-line nil)
            (dired-next-line 1)))

(define-command dired-unmark-and-previous-line (n) ("p")
  (loop :repeat n
        :do (dired-previous-line 1)
            (mark-current-line nil)))

(define-command dired-toggle-marks () ()
  (mark-lines (constantly t)
              #'not))

(define-command dired-unmark-all () ()
  (mark-lines (constantly t)
              (constantly nil)))

(define-command dired-mark-regexp (regex) ("sRegex: ")
  (mark-lines (lambda (flag file)
                (declare (ignore flag))
                (setf file
                      (let ((file1 (file-namestring file)))
                        (if (string= "" file1)
                            (car (last (pathname-directory file)))
                            file1)))
                (ppcre:scan regex file))
              (constantly t)))

(defun dired-query-replace-internal (query-function)
  (destructuring-bind (before after)
      (lem.isearch:read-query-replace-args)
    (dolist (file (selected-files))
      (find-file file)
      (buffer-start (current-point))
      (funcall query-function before after))))

(define-command dired-query-replace () ()
  (dired-query-replace-internal 'lem.isearch:query-replace))

(define-command dired-query-replace-regexp () ()
  (dired-query-replace-internal 'lem.isearch:query-replace-regexp))

(define-command dired-query-replace-symbol () ()
  (dired-query-replace-internal 'lem.isearch:query-replace-symbol))

(defun run-command (string &rest args)
  (let ((error-string
          (with-output-to-string (error-output)
            (uiop:run-program (apply #'format nil string args)
                              :ignore-error-status t
                              :error-output error-output))))
    (when (string/= error-string "")
      (editor-error "~A" error-string))))

(define-command dired-delete-files () ()
  (when (prompt-for-y-or-n-p "Really delete files")
    (dolist (file (selected-files))
      (run-command "rm -fr '~A'" file)))
  (update-all))

(defun get-dest-directory ()
  (dolist (window (window-list) (buffer-directory))
    (when (and (not (eq window (current-window)))
               (eq 'dired-mode (buffer-major-mode (window-buffer window))))
      (return (buffer-directory (window-buffer window))))))

(define-command dired-copy-files () ()
  (let ((to-pathname (prompt-for-file "Destination Filename: " (get-dest-directory))))
    (dolist (file (selected-files))
      (run-command "cp -r '~A' '~A'" file to-pathname)))
  (update-all))

(define-command dired-rename-files () ()
  (let ((to-pathname (prompt-for-file "Destination Filename: " (get-dest-directory))))
    (dolist (file (selected-files))
      (run-command "mv '~A' '~A'" file to-pathname)))
  (update-all))

(define-command dired-mkdir (buffer-name) ("smkdir: ")
  (multiple-value-bind (pathname make-p)
      (ensure-directories-exist
       (uiop:ensure-directory-pathname
        (merge-pathnames buffer-name (buffer-directory))))
    (unless make-p
      (editor-error "failed mkdir: ~A" pathname))
    (message "mkdir: ~A" pathname)
    (update-all)))

(defun select-file (open-file)
  (let ((file (get-file)))
    (when file
      (funcall open-file file))))

(defun mark-current-line (flag &optional (point (current-point)))
  (when (dired-range-p point)
    (line-start point)
    (with-buffer-read-only (point-buffer point) nil
      (save-excursion
        (delete-character point 1)
        (if flag
            (insert-character point #\*)
            (insert-character point #\space))))
    (adjust-point point)))

(defun mark-lines (test get-flag)
  (with-point ((p (current-point)))
    (move-to-start-point p)
    (line-offset p 2)
    (loop
      (line-start p)
      (let ((flag (char= (character-at p) #\*))
            (file (get-file p)))
        (when (and file (funcall test flag file))
          (mark-current-line (funcall get-flag flag) p)))
      (unless (line-offset p 1)
        (return)))))

(defun selected-files ()
  (let ((files '()))
    (with-point ((p (current-point)))
      (move-to-start-point p)
      (loop
        (line-start p)
        (let ((flag (char= (character-at p) #\*)))
          (when flag
            (line-start p)
            (push (get-file p) files)))
        (unless (line-offset p 1)
          (return))))
    (if (null files)
        (let ((file (get-file)))
          (when file
            (list file)))
        (nreverse files))))

(defun get-line-property (point property-name)
  (with-point ((point point))
    (line-start point)
    (character-offset point 1)
    (text-property-at point property-name)))

(defun get-file (&optional (point (current-point)))
  (get-line-property point 'file))

(defun get-type (&optional (point (current-point)))
  (get-line-property point 'type))

(defun ls-output-string (filename)
  (with-output-to-string (stream)
    (uiop:run-program (format nil "LANG=en; ls -al '~A'" filename) :output stream)))

(defun update (buffer)
  (with-buffer-read-only buffer nil
    (let ((line-number (line-number-at-point (buffer-point buffer)))
          (charpos (point-charpos (buffer-point buffer)))
          (dirname (probe-file (buffer-directory buffer))))
      (erase-buffer buffer)
      (when dirname
        (with-point ((cur-point (buffer-point buffer) :left-inserting))
          (insert-string cur-point
                         (namestring dirname)
                         :attribute 'dired-header-attribute)
          (insert-character cur-point #\newline 2)
          (let ((output-string (ls-output-string dirname)))
            (insert-string cur-point output-string)
            (buffer-start cur-point)
            (line-offset cur-point 3)
            (loop
              (let ((string (line-string cur-point)))
                (multiple-value-bind (start end start-groups end-groups)
                    (ppcre:scan "^(\\S*)\\s+(\\d+)\\s+(\\S*)\\s+(\\S*)\\s+(\\d+)\\s+(\\S+\\s+\\S+\\s+\\S+)\\s(.*?)(?: -> .*)?$"
                                string)
                  (declare (ignorable start end start-groups end-groups))
                  (when start
                    (insert-string cur-point "  ")
                    (let* ((index (1- (length start-groups)))
                           (filename (merge-pathnames
                                      (subseq string
                                              (aref start-groups index)
                                              (aref end-groups index))
                                      dirname))
                           (start-file-charpos (+ 2 (aref start-groups index))))
                      (setf (buffer-value buffer 'start-file-charpos) start-file-charpos)
                      (with-point ((start-point (line-start cur-point))
                                   (end-point (line-end cur-point)))
                        (case (char string 0)
                          (#\l
                           (put-text-property start-point end-point 'type :link)
                           (character-offset (line-start cur-point) start-file-charpos)
                           (put-text-property cur-point end-point :attribute 'dired-link-attribute))
                          (#\d
                           (put-text-property start-point end-point 'type :directory)
                           (character-offset (line-start cur-point) start-file-charpos)
                           (put-text-property cur-point end-point :attribute 'dired-directory-attribute)
                           (setf filename (namestring (uiop:ensure-directory-pathname filename))))
                          (#\-
                           (put-text-property start-point end-point 'type :file)))
                        (put-text-property start-point end-point 'file filename)))
                    (line-offset cur-point 1)
                    (when (end-line-p cur-point)
                      (return))))))))
        (move-to-line (buffer-point buffer) line-number)
        (line-offset (buffer-point buffer) 0 charpos)
        t))))

(defun update-all ()
  (dolist (buffer (buffer-list))
    (when (eq 'dired-mode (buffer-major-mode buffer))
      (update buffer))))

(defun dired-buffer (filename)
  (let* ((filename
           (uiop:directory-exists-p
            (expand-file-name (namestring filename) (buffer-directory))))
         (buffer-name (format nil "DIRED ~A" (princ-to-string filename))))
    (or (get-buffer buffer-name)
        (let ((buffer (make-buffer buffer-name :enable-undo-p nil :read-only-p t)))
          (change-buffer-mode buffer 'dired-mode)
          (setf (buffer-directory buffer) filename)
          (update buffer)
          (move-to-start-point (buffer-point buffer))
          buffer))))

(setf *find-directory-function* 'dired-buffer)
