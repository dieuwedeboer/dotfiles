;;; theme.el --- Omarchy palette -*- lexical-binding: t -*-

;; Quattro palette via berenddeboer/omarchy-emacs-theme. Clone and Omarchy
;; hook live in ~/.local/share/omarchy-emacs-theme (install.sh).

(defun monarchy-emacs-tty-no-background (&optional frame)
  "Leave GUI frames on the Omarchy palette. TTY uses the terminal background."
  (let ((frame (or frame (selected-frame))))
    (unless (display-graphic-p frame)
      (dolist (face '(default fringe line-number))
        (set-face-background face "unspecified-bg" frame)))))

(use-package omarchy-emacs-theme
  :straight nil
  :load-path "~/.local/share/omarchy-emacs-theme"
  :demand t
  :config
  (add-hook 'omarchy-emacs-theme-after-load-hook
            (lambda ()
              (set-face-attribute 'default nil :height 140)
              (mapc #'monarchy-emacs-tty-no-background (frame-list))))
  (add-hook 'after-make-frame-functions #'monarchy-emacs-tty-no-background)
  (omarchy-emacs-theme-load))

;; Emoji support 👌
(set-fontset-font t 'symbol "Noto Color Emoji" nil 'append)

;; Font size (need this to differ between screen types)
(set-face-attribute 'default nil :height 140)
