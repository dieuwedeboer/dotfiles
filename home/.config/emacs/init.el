;;; init.el --- Dieuwe's Emacs -*- lexical-binding: t -*-

(desktop-save-mode 1)
(setq gc-cons-threshold 50000000)
(setq large-file-warning-threshold 100000000)
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(setq native-comp-async-report-warnings-errors 'silent)

;; Overlay bin, not ~/.local/share/omarchy/bin (that path is stock Omarchy).
(let ((omarchy-bin "/usr/local/share/omarchy/bin"))
  (when (file-directory-p omarchy-bin)
    (add-to-list 'exec-path omarchy-bin)
    (setenv "PATH" (concat omarchy-bin ":" (or (getenv "PATH") "")))))

(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 5))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'use-package)

(use-package magit
  :straight t)
(use-package git-modes
  :straight t)
(use-package dockerfile-mode
  :straight t)

(defvar config-dir (expand-file-name "config" user-emacs-directory))

(load (expand-file-name "theme.el" config-dir))
(load (expand-file-name "general.el" config-dir))
(load (expand-file-name "programming.el" config-dir))
(load (expand-file-name "markup.el" config-dir))
(load (expand-file-name "web.el" config-dir))
(load (expand-file-name "php.el" config-dir))
(load (expand-file-name "lisp.el" config-dir))

(custom-set-faces
 '(diff-hl-insert ((t (:foreground "#5fff00" :background "none"))))
 '(diff-hl-delete ((t (:foreground "#d70000" :background "none"))))
 '(diff-hl-change ((t (:foreground "#00afff" :background "none")))))
