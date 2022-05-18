(use-package doom-themes
  :straight t
  :config
  ;; Global settings (defaults)
  (setq doom-themes-enable-bold t    ; if nil, bold is universally disabled
        doom-themes-enable-italic t) ; if nil, italics is universally disabled

  ;; For theme list see https://github.com/hlissner/emacs-doom-themes#theme-list
  (load-theme 'doom-one t)

  ;; @todo change comment color to the green, and then quoted text to a yellow

  ;; Enable flashing mode-line on errors
  (doom-themes-visual-bell-config)
  ;; Corrects (and improves) org-mode's native fontification.
  (doom-themes-org-config))

;; Emoji support 👌
(set-fontset-font t 'symbol "Noto Color Emoji" nil 'append)
