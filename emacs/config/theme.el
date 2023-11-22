(use-package doom-themes
  :straight t
  :config
  ;; Global settings (defaults)
  (setq doom-themes-enable-bold t    ; if nil, bold is universally disabled
        doom-themes-enable-italic t) ; if nil, italics is universally disabled

  ;; For theme list see https://github.com/doomemacs/themes#theme-list
  (load-theme 'doom-dark+ t)

  ;; Customisations
  (set-face-attribute 'region nil :foreground "#ffffff")

  ;; Enable flashing mode-line on errors
  (doom-themes-visual-bell-config)
  ;; Corrects (and improves) org-mode's native fontification.
  (doom-themes-org-config))

;; Emoji support 👌
(set-fontset-font t 'symbol "Noto Color Emoji" nil 'append)

;; @todo work on getting some more Doom features
;; per the https://github.com/doomemacs/doomemacs screenshots, such as:
;; hotter toolbar
;; sidebar with folder structure
