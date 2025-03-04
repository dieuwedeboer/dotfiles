(setq c-basic-offset 2)
(setq cperl-indent-level 2)

;; Guru-mode encourages good emacs practice.
(use-package guru-mode
  :straight t
  :config (guru-global-mode +1)
  :custom
  (guru-warn-only t "guru-mode should only warn")
  :hook ((prog-mode . guru-mode))
  )

;; Hex colours highlighted.
(use-package rainbow-mode
  :straight t
  :hook ((prog-mode . rainbow-mode)))

;; show the name of the current function definition in the modeline
(use-package which-func
  :config
  (which-function-mode 1))

;; Project management
(use-package projectile
  :straight t
  :config (projectile-mode)
  :bind-keymap
  ("C-c p" . projectile-command-map))

;; Auto-complete
(use-package company
  :straight t
  ;;:bind (("M-/" . company-complete))
  :config
  (global-company-mode))


;; Keybinding help
(use-package which-key
    :straight t
    :config
    (which-key-mode))

;; Indentation guides
(use-package highlight-indent-guides
  :straight t
  ;;:hook (
  ;;       (prog-mode . highlight-indent-guides))
  :config
  (setq highlight-indent-guides-method 'character
        highlight-indent-guides-responsive 'top)
  )

;; Eglot for PHP and React
(use-package eglot
  :hook
  (php-mode . eglot-ensure)  ;; Start Eglot for PHP files
  (web-mode . (lambda ()     ;; Start Eglot for JSX/TSX in web-mode
                (when (string-match-p "\\.jsx\\|\\.tsx\\'" buffer-file-name)
                  (eglot-ensure))))
  :config
  (add-to-list 'eglot-server-programs
               '(php-mode "intelephense" "--stdio"))
  (add-to-list 'eglot-server-programs
               '((web-mode :language-id "typescriptreact" "javascriptreact")
                 "typescript-language-server" "--stdio")))
