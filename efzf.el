;;; efzf.el --- Emacs-based fuzzy finder for the command line  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yoshinari Nomura

;; Author: Yoshinari Nomura <nom@quickhack.net>
;; Maintainer: Yoshinari Nomura <nom@quickhack.net>
;; URL: https://github.com/yoshinari-nomura/efzf
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, matching, terminals

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; efzf brings Emacs' completion UI (Vertico, Orderless, Marginalia,
;; etc.) to the terminal as an fzf-like selector.  The companion shell
;; script `efzf' calls `efzf-run-action' through emacsclient, which
;; shows a full-screen completion UI in the terminal and writes the
;; selected item to a file.
;;
;; When installed as a package, run `M-x efzf-install-scripts' to copy
;; the shell scripts `efzf' and `efzf.zsh' to your shell environment.
;;
;; See README.org for installation and shell integration.

;;; Code:

(require 'cl-lib)

(defvar vertico-count)
(defvar vertico-resize)

(defconst efzf--source-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing efzf.el and the bundled shell scripts.")

;;;###autoload
(defun efzf-install-scripts (script-dir zsh-dir)
  "Copy the bundled shell scripts to SCRIPT-DIR and ZSH-DIR.
The `efzf' script is copied to SCRIPT-DIR and made executable;
SCRIPT-DIR should be included in your $PATH.  `efzf.zsh' is
copied to ZSH-DIR; source it from your .zshrc.

Run this commandagain after upgrading efzf."
  (interactive
   (list (read-directory-name "Install efzf to: " "~/.local/bin/")
         (read-directory-name "Install efzf.zsh to: " "~/.zsh/")))
  (dolist (spec `(("efzf" ,script-dir #o755)
                  ("efzf.zsh" ,zsh-dir #o644)))
    (let* ((src (expand-file-name (nth 0 spec) efzf--source-directory))
           (dir (file-name-as-directory (expand-file-name (nth 1 spec))))
           (dst (expand-file-name (nth 0 spec) dir)))
      (unless (file-exists-p src)
        (user-error "Cannot find %s" src))
      (make-directory dir t)
      (copy-file src dst (if (called-interactively-p 'any) 1 t))
      (set-file-modes dst (nth 2 spec))
      (message "Installed %s" (abbreviate-file-name dst)))))

(defun efzf-run-action (target-dir input-file output-file action-func-symbol options)
  "Run ACTION-FUNC-SYMBOL in a full-screen UI for emacsclient.
TARGET-DIR: working directory (set as `default-directory')
INPUT-FILE: file containing the contents of stdin
OUTPUT-FILE: file to write the selection result to
ACTION-FUNC-SYMBOL: action function to call
OPTIONS: plist passed to the action function"
  (message nil)
  (let ((frame (selected-frame))
        (coding-system-for-write 'utf-8))
    (unwind-protect
        (progn
          (let ((ui-buf (get-buffer-create "*EFZF-UI*")))
            (with-current-buffer ui-buf
              (setq default-directory target-dir)
              (setq mode-line-format nil)
              (setq header-line-format nil)
              (erase-buffer))
            (switch-to-buffer ui-buf)
            (delete-other-windows)
            (redisplay))
          (with-temp-buffer
            (setq default-directory target-dir)
            ;; Load the input file
            (when (file-exists-p input-file)
              (let ((coding-system-for-read 'utf-8))
                (insert-file-contents input-file)))

            (let* ((vertico-count (- (frame-height) 2))
                   (vertico-resize nil)
                   (result (funcall action-func-symbol options)))

              (when (and (stringp result) (not (string= result "")))
                (with-temp-file output-file
                  (insert result))))))
      ;; Clean up
      (when (get-buffer "*EFZF-UI*")
        (kill-buffer "*EFZF-UI*"))

      (run-at-time 0 nil
                   (lambda (f)
                     (when (frame-live-p f)
                       (message nil)
                       (redisplay)
                       (delete-frame f)))
                   frame))))

(defun efzf-action-select (options)
  "Read a file name and return its absolute path, or nil if cancelled.
OPTIONS is a plist; :prompt overrides the default prompt."
  (let ((prompt (or (plist-get options :prompt) "Select file: ")))
    (let ((file (condition-case nil
                    (read-file-name prompt)
                  (quit nil))))
      (when (and file (not (string= file "")))
        (expand-file-name file)))))

(defun efzf-action-filter (options)
  "Select a line of the current buffer with `completing-read'.
Each line is split at the first NUL character into a candidate and
the value to return; a line without NUL is used for both.  Return
the value of the selected candidate, or nil if cancelled.
OPTIONS is a plist; :prompt overrides the default prompt."
  (let* ((lines (efzf--buffer-to-key-value-alist ?\0))
         (prompt (or (plist-get options :prompt) "Filter: "))
         (choice nil)
         (completion-table
          (lambda (string pred action)
            (if (eq action 'metadata)
                '(metadata (display-sort-function . identity)
                           (cycle-sort-function . identity))
              (complete-with-action action lines string pred)))))
    (when lines
      (setq choice (condition-case nil
                       (completing-read prompt completion-table nil t)
                     (quit nil))))
    (cdr (assoc choice lines))))

(defun efzf--buffer-to-key-value-alist (delimiter-char &optional key-is-last)
  "Convert each line of the current buffer to a (KEY . VALUE) alist.
DELIMITER-CHAR separates KEY and VALUE.
If KEY-IS-LAST is non-nil, the part after the last delimiter is KEY,
and the part before it is VALUE.
If a line has no delimiter, use the whole line for both KEY and VALUE."
  (save-excursion
    (goto-char (point-min))
    (let (alist)
      (while (not (eobp))
        (let* ((line (buffer-substring-no-properties
                      (line-beginning-position)
                      (line-end-position)))
               (pos (if key-is-last
                        (cl-position delimiter-char line :from-end t)
                      (cl-position delimiter-char line))))
          (push
           (if pos
               (if key-is-last
                   (cons (substring line (1+ pos))
                         (substring line 0 pos))
                 (cons (substring line 0 pos)
                       (substring line (1+ pos))))
             (cons line line))
           alist))
        (forward-line 1))
      (nreverse alist))))

(provide 'efzf)

;;; efzf.el ends here
