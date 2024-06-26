(use-package web-mode
  :straight t
  :mode
  (("\\.phtml\\'" . web-mode)
   ("\\.tpl\\.php\\'" . web-mode)
   ("\\.tpl\\'" . web-mode)
   ("\\.blade\\.php\\'" . web-mode)
   ("\\.jsp\\'" . web-mode)
   ("\\.as[cp]x\\'" . web-mode)
   ("\\.erb\\'" . web-mode)
   ("\\.html?\\'" . web-mode)
   ("\\.twig?\\'" . web-mode)
   ("\\.jsx?$" . js2-mode)
   ("\\.ts?\\'" . web-mode)
   ("\\.tsx?$" . web-mode)
   ("/\\(views\\|html\\|theme\\|templates\\)/.*\\.php\\'" . web-mode))
  :custom
  (web-mode-code-indent-offset 2)
  (web-mode-css-indent-offset 2)
  (web-mode-markup-indent-offset 2)
  (web-mode-enable-auto-pairing nil "Make web-mode play nice with smartparens")
  (web-mode-content-types-alist '(("jsx" . "\\.js[x]?\\'")))
  :config
  (sp-with-modes '(web-mode)
    (sp-local-pair "%" "%"
                   :unless '(sp-in-string-p)
                   :post-handlers '(((lambda (&rest _ignored)
                                       (just-one-space)
                                       (save-excursion (insert " ")))
                                     "SPC" "=" "#")))
    (sp-local-tag "%" "<% "  " %>")
    (sp-local-tag "=" "<%= " " %>")
    (sp-local-tag "#" "<%# " " %>")))

(use-package js2-mode
  :straight t
  :custom
  (js-indent-level 2)
  (js2-bounce-indent-p nil)
  :mode
  (("\\.js\\'" . js2-mode)
   ("\\.pac\\'" . js2-mode))
  :interpreter
  (("node" . js2-mode))
  :hook
  ((js2-mode . (lambda ()
                 ;; electric-layout-mode doesn't play nice with smartparens
                 (setq-local electric-layout-rules '((?\; . after)))
                 (setq mode-name "JS2")
                 (js2-imenu-extras-mode +1)))))

(use-package css-mode
  :straight t
  :custom
  (css-indent-offset 2))

(use-package scss-mode
  :straight t
  :custom
  (scss-compile-at-save nil "turn off annoying auto-compile on save"))

(use-package apache-mode
  :straight t)

(use-package elm-mode
  :straight t)
