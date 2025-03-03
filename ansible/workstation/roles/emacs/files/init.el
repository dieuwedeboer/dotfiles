;; TODO .emacs file

(setq load-path (cons "~/.emacs.d/init" load-path))
;;(load "init-key-bindings.el")

;; things configured outside of a package
(fset 'yes-or-no-p 'y-or-n-p)

;; install straight and use-package
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 6))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(setq straight-override-recipe t)
(straight-use-package 'use-package)

;; Better terminal support
;;(load "init-term-keys.el")

;; customise built-in packages

;; always show parens
(use-package paren
  :config
  (show-paren-mode))

;; enable mouse in terminal
(use-package xt-mouse
  :config
  (xterm-mouse-mode)
  )

(use-package delsel
  :config
  (delete-selection-mode))

(use-package ispell
  :config
  (setq ispell-program-name "aspell")
  (setq ispell-local-dictionary "british")
  )

;; default bind is C-M-i which my keyboard or terminal cannot generate
;; (use-package minibuffer
;;   :bind ("M-i" . completion-at-point))

(use-package shell-script-mode
  :config
  :mode "\\.envrc$")

;; I want my C+Tab key
(defun my-keep-control-tab ()
  (local-set-key [C-tab] #'(lambda () (interactive) (switch-to-buffer (other-buffer)))))
(add-hook 'magit-status-mode-hook 'my-keep-control-tab)

;; no menubar
(menu-bar-mode -1)

;; ignore case when completing
(setq completion-ignore-case t)


;;
;; custom packages
;;

;; remove modes we're not interested in
(use-package diminish
  :straight t
  :config
  (diminish 'abbrev-mode)
  (diminish 'flyspell-mode)
  (diminish 'flyspell-prog-mode)
  (diminish 'eldoc-mode)
  (diminish 'anzu-mode))

;; put backup files in a single spot
(use-package no-littering
  :straight t
  :config
  (setq undo-tree-history-directory-alist '(("." . "~/.emacs.d/var/undo-tree-hist")))
  )

;; scroll before reaching end of bottom, and also scroll without jumping
(use-package smooth-scrolling
  :straight t
  :config
  (smooth-scrolling-mode 1)
  (setq smooth-scroll-margin 4))


;; manually patched
;; and this does not work, need to execute this separately after loading emacs
;; possibly my functions are not setup correctly.
;; 2023-09-08: again not working after restart: copies to wayland after reload
;; but Emacs cannot access the clipboard
;; 2023-12-16: reexecuting this package does not work I think?
;; then tried the advice-remove, and execute: : ctrl+v fails, but outside ctrl+v works
(use-package waypipe-mode
  :straight (waypipe-mode
             :type git :host nil :repo "https://gitlab.freedesktop.org/sochotnicky/waypipe-mode.el")
  :config
  (waypipe-mode 1)

  ;; improve yank in text mode
  (define-advice kill-ring-save (:around (old-fun &rest args) waypipe-mode)
    "In addition to copying to kill ring, copy to X clipboard."
    (let ()
      (waypipe--wl-copy
       (substring-no-properties
        (filter-buffer-substring (region-beginning) (region-end))))
      (apply old-fun args))
    )

  ;; copy till end of line to clipboard
  (defun my-copy-to-end-of-line ()
    "Copy all text from cursor to end of line"
    (interactive)
    (save-excursion
      (let ((beg (point)))
        (move-end-of-line 1)
        (waypipe--wl-copy
         (substring-no-properties
          (filter-buffer-substring beg (point))))))
    )

  (defun my-waypipe--wl-paste ()
    "Paste text from Wayland clipboard using wl-paste."
    (if (and waypipe-wl-copy-process (process-live-p waypipe-wl-copy-process))
        nil ; should return nil if we're the current paste owner
      (shell-command-to-string "wl-paste -n")))

  ;; paste directly into buffer
  (defun my-paste-from-clipboard ()
    (interactive)
    (insert (my-waypipe--wl-paste)))

  :bind ("C-v" . my-paste-from-clipboard)
  :bind ("C-M-e" . my-copy-to-end-of-line)
  )

(use-package ethan-wspace
  :straight t
  :config
  (global-ethan-wspace-mode 1)
  )

(use-package yaml-mode
  :straight t
  :mode ("/ansible/group_vars/[^\.]+$'" . yaml-mode)
)

(use-package python-mode
  :straight t
  :config
  )

;(straight-use-package 'jinja2-mode)
(straight-use-package 'twig-mode)
(straight-use-package 'systemd)
(straight-use-package 'fish-mode)
(straight-use-package 'flycheck)

;; different style of making unique buffer names
(require 'uniquify)
(setq uniquify-strip-common-suffix nil)
(setq uniquify-buffer-name-style 'post-forward)


(use-package electric
	     :config
	     (electric-indent-mode))

(use-package company
  :straight t
  :config
  ;;(add-to-list 'company-backends 'company-ac-php-backend )
  (diminish 'company-mode)
  )

;; search using the silver searcher
(use-package ag
  :straight t)

;; (use-package company-php
;;   :straight t
;; )

(use-package phps-mode
  :straight t
  :after flycheck
  :ensure t
  :mode ("\\.php\\'" "\\.phtml\\'" "\\.module\\'" "\\.inc\\'")
  :config
  (phps-mode-flycheck-setup)
  (setq-local tab-width 2)
  (setq phps-mode-async-process nil)
  (setq phps-mode-async-process-using-async-el t)
  ;; Drupal
  :mode "\\.\\(php\\|module\\|inc\\|theme\\)$"
  :mode "modules/.*\\.install$"
  :mode "modules/.*\\.test$"
  :mode "modules/.*\\.info$"
  :mode "tests/.*\\.test$"
  )

(use-package web-mode
  :straight t
  :init
  ;; better indenting
  (setq web-mode-css-indent-offset 2)
  (setq cssm-indent-function 'cssm-c-style-indenter)

  (defun my-web-mode-hook ()
    "Hooks for Web mode."
    (setq web-mode-code-indent-offset 2))
  :mode "\\.tpl\.php$"
  :mode "\\(\\.php\\|\\.inc\\)\\.j2$"
  :hook my-web-mode-hook
)

;; (defun drupal-browse-api ()
;;   "Bring up Drupal API at point"
;;   (interactive)
;;   (let ((function-name (thing-at-point 'filename)))
;;     (if function-name
;;   (w3m-browse-url (concat "http://api.drupal.org/api/function/" function-name "/7"))
;;       (error "No function found"))))

;; (global-set-key [F1 d] 'drupal-browse-api)

;; git
(use-package magit
  :straight t
  :config
  (setq magit-diff-refine-hunk t))

;; Apache mode
(use-package apache-mode
  :straight
  :config
  (setq apache-indent-level 2))

;;Sets up the with-editor package so things that invoke $EDITOR will use the current emacs if I'm already inside of emacs
(use-package with-editor
  :init
  (progn
    (add-hook 'shell-mode-hook  'with-editor-export-editor)
    (add-hook 'eshell-mode-hook 'with-editor-export-editor)))

(use-package markdown-mode
  :straight t)

;; show: (undo-tree-visualize)
(use-package undo-tree
  :straight t
  :config
  (global-undo-tree-mode))

(use-package treesit-auto
  :straight t
  :custom
  (treesit-auto-install 'prompt)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode))

;; Cursor for Emacs: https://github.com/MatthewZMD/aidermacs
(use-package aidermacs
  :straight (:host github :repo "MatthewZMD/aidermacs" :files ("*.el"))
  :custom
  (aidermacs-default-model "anthropic/claude-3-5-sonnet-20241022")
  ;;(aidermacs-default-model "openai/o1-mini")
  ;;(aidermacs-default-model "openai/o3-mini")
  ;;(setq aidermacs-use-architect-mode t)
  ;;(setq aidermacs-architect-model "o1-mini") ; default
  ;;(setq aidermacs-editor-model "deepseek/deepseek-chat") ;; defaults to aidermacs-default-model
  (aidermacs-backend 'comint) ;; Use vterm backend (default is comint)
  :config
  (global-set-key (kbd "C-c a") 'aidermacs-transient-menu))

;; direnv support
(use-package envrc
  :straight t
  :config
  (envrc-global-mode))

;; use emacs server
(server-start)

(use-package desktop
  :config
  (setq desktop-save-mode t
        desktop-restore-in-current-display t
        desktop-save 'if-exists
        desktop-auto-save-timeout 60)
  (desktop-save-mode t)
  )

(put 'downcase-region 'disabled nil)

(put 'upcase-region 'disabled nil)
