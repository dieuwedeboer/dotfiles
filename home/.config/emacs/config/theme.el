;;; theme.el --- Omarchy palette -*- lexical-binding: t -*-

;; Quattro palette via berenddeboer/omarchy-emacs-theme. Clone and Omarchy
;; hook live in ~/.local/share/omarchy-emacs-theme (install.sh).

(defun monarchy-emacs-tty-no-background (&optional frame)
  "Leave GUI frames on the Omarchy palette. TTY uses the terminal background."
  (let ((frame (or frame (selected-frame))))
    (unless (display-graphic-p frame)
      (dolist (face '(default fringe line-number))
        (set-face-background face "unspecified-bg" frame)))))

(defun monarchy-emacs--hex-rgb (hex)
  "Return (R G B) integers 0-255 for HEX color #RRGGBB."
  (let ((n (string-to-number (if (eq (aref hex 0) ?#)
                                 (substring hex 1)
                               hex)
                             16)))
    (list (ash n -16) (logand (ash n -8) 255) (logand n 255))))

(defun monarchy-emacs-mix-hex (from to percent)
  "Mix hex colors FROM toward TO by PERCENT (0-100).
Parse hex directly so a TTY daemon frame cannot quantize the mix."
  (pcase-let* ((`(,r1 ,g1 ,b1) (monarchy-emacs--hex-rgb from))
               (`(,r2 ,g2 ,b2) (monarchy-emacs--hex-rgb to))
               (p (/ (float percent) 100.0)))
    (format "#%02x%02x%02x"
            (round (+ r1 (* (- r2 r1) p)))
            (round (+ g1 (* (- g2 g1) p)))
            (round (+ b1 (* (- b2 b1) p))))))

(defun monarchy-emacs-hl-line-distinct-from-blocks ()
  "Keep the current line visible inside org/markdown blocks.
The Omarchy theme paints both `hl-line' and code blocks with `surface'."
  (when (bound-and-true-p omarchy-emacs-theme-palette)
    (let* ((bg (alist-get 'background omarchy-emacs-theme-palette))
           (fg (alist-get 'foreground omarchy-emacs-theme-palette))
           ;; surface is a 10% mix; 22% is still quiet but distinct.
           (hl (and bg fg (monarchy-emacs-mix-hex bg fg 22))))
      (when hl
        (set-face-attribute 'hl-line nil :background hl)
        (set-face-attribute 'line-number-current-line nil :background hl)))))

(defun monarchy-font--file-int (path)
  "First number on its own line in PATH, or nil."
  (when (file-readable-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (goto-char (point-min))
      (when (re-search-forward "^[+-]?[0-9]+\\(\\.[0-9]+\\)?" nil t)
        (string-to-number (match-string 0))))))

(defun monarchy-font-pt ()
  "Point size from apply-font-size (Omarchy 12px->9pt plus MONARCHY_FONT_PT_OFFSET)."
  (let ((state (expand-file-name "~/.local/state/omarchy/font-pt"))
        (apply (expand-file-name "~/.config/omarchy/hooks/apply-font-size")))
    (or (monarchy-font--file-int state)
        (when (file-regular-p apply)
          (with-temp-buffer
            (when (eq 0 (call-process apply nil t nil "--print"))
              (goto-char (point-min))
              (when (looking-at "[+-]?[0-9]+")
                (string-to-number (match-string 0))))))
        12)))

(defun monarchy-emacs-apply-font-size (&optional frame)
  "Set the default face to `monarchy-font-pt' on GUI frames.
FRAME if given is refreshed too; otherwise every live frame is."
  (let ((height (* 10 (monarchy-font-pt))))
    (set-face-attribute 'default nil :height height)
    (dolist (fr (if frame (list frame) (frame-list)))
      (when (display-graphic-p fr)
        (set-face-attribute 'default fr :height height)))
    height))

(defun monarchy-alpha ()
  "Background opacity from MONARCHY_ALPHA, or nil if unset."
  (let ((env (getenv "MONARCHY_ALPHA"))
        (state (expand-file-name "~/.local/state/omarchy/alpha")))
    (cond
     ((and env (string-match-p "\\`[0-9]+\\(\\.[0-9]+\\)?\\'" env))
      (string-to-number env))
     ((monarchy-font--file-int state))
     (t nil))))

(defun monarchy-emacs-apply-alpha (&optional frame)
  "Set GUI frame background opacity from `monarchy-alpha'.
Text stays opaque, matching foot's colors.alpha. FRAME if given is
refreshed too; otherwise every live frame is."
  (let ((a (monarchy-alpha)))
    (when a
      (setf (alist-get 'alpha-background default-frame-alist) a)
      (dolist (fr (if frame (list frame) (frame-list)))
        (when (display-graphic-p fr)
          (ignore-errors (set-frame-parameter fr 'alpha-background a)))))
    a))

(defun monarchy-emacs-after-omarchy-theme ()
  "Font size, alpha, distinct current line, and TTY background after a palette load."
  (monarchy-emacs-apply-font-size)
  (monarchy-emacs-apply-alpha)
  (monarchy-emacs-hl-line-distinct-from-blocks)
  (mapc #'monarchy-emacs-tty-no-background (frame-list)))

(use-package omarchy-emacs-theme
  :straight nil
  :load-path "~/.local/share/omarchy-emacs-theme"
  :demand t
  :config
  (add-hook 'omarchy-emacs-theme-after-load-hook #'monarchy-emacs-after-omarchy-theme)
  (add-hook 'after-make-frame-functions #'monarchy-emacs-tty-no-background)
  (add-hook 'after-make-frame-functions #'monarchy-emacs-apply-font-size)
  (add-hook 'after-make-frame-functions #'monarchy-emacs-apply-alpha)
  (omarchy-emacs-theme-load))

;; Emoji support 👌
(set-fontset-font t 'symbol "Noto Color Emoji" nil 'append)

(monarchy-emacs-apply-font-size)
(monarchy-emacs-apply-alpha)
