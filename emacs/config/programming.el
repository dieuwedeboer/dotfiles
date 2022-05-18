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

;; @see lisp.el as I find this a bit annoying in PHP/JS modes
;;(use-package smartparens
;;  :straight t
;;  :hook ((prog-mode . smartparens-mode)))

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

;; Helm is like ido-mode, but lists options vertically instead of
;; horizontally in the mini-buffer.
(use-package helm
  :straight t
  ;; Based on http://tuhdo.github.io/helm-intro.html
  :config
  ;; The default "C-x c" is quite close to "C-x C-c", which quits Emacs.
  ;; Changed to "C-c h". Note: We must set "C-c h" globally, because we
  ;; cannot change `helm-command-prefix-key' once `helm-config' is loaded.
  (global-set-key (kbd "C-c h") 'helm-command-prefix)
  (global-unset-key (kbd "C-x c"))
  (global-set-key (kbd "C-c h o") 'helm-occur)
  (global-set-key (kbd "M-x") #'helm-M-x)
  (global-set-key (kbd "C-x C-f") #'helm-find-files)
  (global-set-key (kbd "C-x b") #'helm-mini)
  (setq helm-split-window-in-side-p           t ; open helm buffer inside current window, not occupy whole other window
        helm-move-to-line-cycle-in-source     t ; move to end or beginning of source when reaching top or bottom of source.
        helm-ff-search-library-in-sexp        t ; search for library in `require' and `declare-function' sexp.
        helm-scroll-amount                    8 ; scroll 8 lines other window using M-<next>/M-<prior>
        helm-ff-file-name-history-use-recentf t
        helm-echo-input-in-header-line t)
  ;; persistent-action doesn't quit the helm session
  (define-key helm-map (kbd "<tab>") 'helm-execute-persistent-action) ; rebind tab to run persistent action
  (define-key helm-map (kbd "C-z")  'helm-select-action) ; list actions using C-z
  (global-set-key (kbd "M-y") 'helm-show-kill-ring)
  (helm-mode 1))

(use-package helm-projectile
  :straight t
  :config
  (setq projectile-completion-system 'helm)
  (helm-projectile-on)
  (global-set-key (kbd "C-c p") 'helm-projectile))

;; LSP
(use-package lsp-mode
  :straight t
  :init
  ;; set prefix for lsp-command-keymap (few alternatives - "C-l", "C-c l")
  (setq lsp-keymap-prefix "C-c l")
  :hook (
         (php-mode . lsp-deferred)
         ;; if you want which-key integration
         (lsp-mode . lsp-enable-which-key-integration))
  :commands lsp)

(load (expand-file-name "custom-lsp-clients.el" config-dir))

;; optionally
(use-package lsp-ui :straight t :commands lsp-ui-mode)
;; if you are helm user
(use-package helm-lsp :commands helm-lsp-workspace-symbol)
;; if you are ivy user
(use-package lsp-ivy :commands lsp-ivy-workspace-symbol)
(use-package lsp-treemacs :commands lsp-treemacs-errors-list)

;; Auto-complete
(use-package company
  :straight t
  :bind (("M-/" . company-complete))
  :config
  (global-company-mode))

;; optionally if you want to use debugger
(use-package dap-mode :straight t)
;; (use-package dap-LANGUAGE) to load the dap adapter for your language

;; optional if you want which-key integration
(use-package which-key
    :straight t
    :config
    (which-key-mode))

;; optionally show indentation guides
(use-package highlight-indent-guides
  :straight t
  ;;:hook (
  ;;       (prog-mode . highlight-indent-guides))
  :config
  (setq highlight-indent-guides-method 'character
        highlight-indent-guides-responsive 'top)
  )
