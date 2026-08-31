;; Quattro palette via berenddeboer/omarchy-emacs-theme. Clone and Omarchy
;; hook live in ~/.local/share/omarchy-emacs-theme (install.sh).
(use-package omarchy-emacs-theme
  :straight nil
  :load-path "~/.local/share/omarchy-emacs-theme"
  :demand t
  :config
  (add-hook 'omarchy-emacs-theme-after-load-hook
            (lambda ()
              (set-face-attribute 'default nil :height 140)))
  (omarchy-emacs-theme-load))

;; Emoji support 👌
(set-fontset-font t 'symbol "Noto Color Emoji" nil 'append)

;; Font size (need this to differ between screen types)
(set-face-attribute 'default nil :height 140)
