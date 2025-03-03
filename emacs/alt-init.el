;; Berend's .emacs file

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

;;(use-package python-mode
;;  :straight t
;;  :config
;;  )

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
;; (use-package apache-mode
;;   :straight
;;   :config
;;   (setq apache-indent-level 2))

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

;; ido-mode
;; do not forget C-c C-r to access recent files!
(use-package ido
  :init
  ;; sort ido filelist by mtime instead of alphabetically
  ;; you might think that using access time might work better, but
  ;; ido will set access time by virtue of reading files in a directory
  (defun ido-sort-mtime ()
    (message ido-current-directory)
    (setq ido-temp-list
          (sort ido-temp-list
                (lambda (a b)
                  (if (not (or (char-equal (string-to-char a) ?@) (char-equal (string-to-char b) ?@)))
                      (time-less-p
                       (cl-sixth (file-attributes (concat ido-current-directory b)))
                       (cl-sixth (file-attributes (concat ido-current-directory a))))
                    nil))))
    (ido-to-end  ;; move . files to end (again)
     (delq nil (mapcar
                (lambda (x) (and (string-match-p "^\\.." x) x))
                ido-temp-list))))

  (add-hook 'ido-make-file-list-hook 'ido-sort-mtime)
  (add-hook 'ido-make-dir-list-hook 'ido-sort-mtime)

  :config
  (ido-mode t)
  )

;;(add-hook 'ido-make-file-list-hook 'ido-sort-mtime)
;;(add-hook 'ido-make-dir-list-hook 'ido-sort-mtime)
;;(remove-hook 'ido-make-file-list-hook 'ido-sort-atime)

(defun ido-find-file-in-tag-files ()
  (interactive)
  (save-excursion
    (let ((enable-recursive-minibuffers t))
      (visit-tags-table-buffer))
    (find-file
     (expand-file-name
      (ido-completing-read
       "Project file: " (tags-table-files) nil t)))))


;; Use ido to complete tags:
(defun my-ido-find-tag ()
  "Find a tag using ido"
  (interactive)
  (tags-completion-table)
  (let (tag-names)
    (mapc (lambda (x)
      (unless (integerp x)
        (push (prin1-to-string x t) tag-names)))
    tags-completion-table)
    (find-tag (ido-completing-read "Tag: " tag-names))))


;; Expand region increases the selected region by semantic units.
;; have maped C-= to C-<f5> as I can't generate C-= on my K480
(use-package expand-region
  :straight t
  :bind (("C-=" . er/expand-region))
  :bind (("C-<f5>" . er/expand-region))
  )


;; Convenient interface to your recently and most frequently used command
(use-package smex
  :straight t
  :bind (("M-x" . smex))
  :config
  (smex-initialize)
)

;; Example configuration for Consult
;; (use-package consult
;;   :straight t
;;   ;; Replace bindings. Lazily loaded by `use-package'.
;;   :bind (;; C-c bindings in `mode-specific-map'
;;          ("C-c M-x" . consult-mode-command)
;;          ("C-c h" . consult-history)
;;          ("C-c k" . consult-kmacro)
;;          ("C-c m" . consult-man)
;;          ("C-c i" . consult-info)
;;          ([remap Info-search] . consult-info)
;;          ;; C-x bindings in `ctl-x-map'
;;          ("C-x M-:" . consult-complex-command)     ;; orig. repeat-complex-command
;;          ("C-x b" . consult-buffer)                ;; orig. switch-to-buffer
;;          ("C-x 4 b" . consult-buffer-other-window) ;; orig. switch-to-buffer-other-window
;;          ("C-x 5 b" . consult-buffer-other-frame)  ;; orig. switch-to-buffer-other-frame
;;          ("C-x t b" . consult-buffer-other-tab)    ;; orig. switch-to-buffer-other-tab
;;          ("C-x r b" . consult-bookmark)            ;; orig. bookmark-jump
;;          ("C-x p b" . consult-project-buffer)      ;; orig. project-switch-to-buffer
;;          ;; Custom M-# bindings for fast register access
;;          ("M-#" . consult-register-load)
;;          ("M-'" . consult-register-store)          ;; orig. abbrev-prefix-mark (unrelated)
;;          ("C-M-#" . consult-register)
;;          ;; Other custom bindings
;;          ("M-y" . consult-yank-pop)                ;; orig. yank-pop
;;          ;; M-g bindings in `goto-map'
;;          ("M-g e" . consult-compile-error)
;;          ("M-g f" . consult-flymake)               ;; Alternative: consult-flycheck
;;          ("M-g g" . consult-goto-line)             ;; orig. goto-line
;;          ("M-g M-g" . consult-goto-line)           ;; orig. goto-line
;;          ("M-g o" . consult-outline)               ;; Alternative: consult-org-heading
;;          ("M-g m" . consult-mark)
;;          ("M-g k" . consult-global-mark)
;;          ("M-g i" . consult-imenu)
;;          ("M-g I" . consult-imenu-multi)
;;          ;; M-s bindings in `search-map'
;;          ("M-s d" . consult-find)                  ;; Alternative: consult-fd
;;          ("M-s c" . consult-locate)
;;          ("M-s g" . consult-grep)
;;          ("M-s G" . consult-git-grep)
;;          ("M-s r" . consult-ripgrep)
;;          ("M-s l" . consult-line)
;;          ("M-s L" . consult-line-multi)
;;          ("M-s k" . consult-keep-lines)
;;          ("M-s u" . consult-focus-lines)
;;          ;; Isearch integration
;;          ("M-s e" . consult-isearch-history)
;;          :map isearch-mode-map
;;          ("M-e" . consult-isearch-history)         ;; orig. isearch-edit-string
;;          ("M-s e" . consult-isearch-history)       ;; orig. isearch-edit-string
;;          ("M-s l" . consult-line)                  ;; needed by consult-line to detect isearch
;;          ("M-s L" . consult-line-multi)            ;; needed by consult-line to detect isearch
;;          ;; Minibuffer history
;;          :map minibuffer-local-map
;;          ("M-s" . consult-history)                 ;; orig. next-matching-history-element
;;          ("M-r" . consult-history))                ;; orig. previous-matching-history-element

;;   ;; Enable automatic preview at point in the *Completions* buffer. This is
;;   ;; relevant when you use the default completion UI.
;;   :hook (completion-list-mode . consult-preview-at-point-mode)

;;   ;; The :init configuration is always executed (Not lazy)
;;   :init

;;   ;; Tweak the register preview for `consult-register-load',
;;   ;; `consult-register-store' and the built-in commands.  This improves the
;;   ;; register formatting, adds thin separator lines, register sorting and hides
;;   ;; the window mode line.
;;   (advice-add #'register-preview :override #'consult-register-window)
;;   (setq register-preview-delay 0.5)

;;   ;; Use Consult to select xref locations with preview
;;   (setq xref-show-xrefs-function #'consult-xref
;;         xref-show-definitions-function #'consult-xref)

;;   ;; Configure other variables and modes in the :config section,
;;   ;; after lazily loading the package.
;;   :config

;;   ;; Optionally configure preview. The default value
;;   ;; is 'any, such that any key triggers the preview.
;;   ;; (setq consult-preview-key 'any)
;;   ;; (setq consult-preview-key "M-.")
;;   ;; (setq consult-preview-key '("S-<down>" "S-<up>"))
;;   ;; For some commands and buffer sources it is useful to configure the
;;   ;; :preview-key on a per-command basis using the `consult-customize' macro.
;;   (consult-customize
;;    consult-theme :preview-key '(:debounce 0.2 any)
;;    consult-ripgrep consult-git-grep consult-grep consult-man
;;    consult-bookmark consult-recent-file consult-xref
;;    consult--source-bookmark consult--source-file-register
;;    consult--source-recent-file consult--source-project-recent-file
;;    ;; :preview-key "M-."
;;    :preview-key '(:debounce 0.4 any))

;;   ;; Optionally configure the narrowing key.
;;   ;; Both < and C-+ work reasonably well.
;;   (setq consult-narrow-key "<") ;; "C-+"

;;   ;; Optionally make narrowing help available in the minibuffer.
;;   ;; You may want to use `embark-prefix-help-command' or which-key instead.
;;   ;; (keymap-set consult-narrow-map (concat consult-narrow-key " ?") #'consult-narrow-help)
;; )

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
