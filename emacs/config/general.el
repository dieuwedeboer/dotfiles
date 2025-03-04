;; General configuration - much taken from prelude

;; Disable toolbar.
(when (fboundp 'tool-bar-mode)
  (tool-bar-mode -1))

;; Disable menubar by default (see f12 keybinding to toggle).
(menu-bar-mode -1)

;; Enable mouse support for terminal.
(xterm-mouse-mode t)

;; Mouse-select in terminal emacs should also copy to primary selection.
(setq mouse-drag-copy-region t)
(setq x-select-enable-primary t)
(setq x-select-enable-clipboard t)

;; icomplete / fido for autocompletion
(fido-vertical-mode t)

;; Disable the scroll bar
;;(scroll-bar-mode -1)

;; enable y/n answers
(fset 'yes-or-no-p 'y-or-n-p)

;; The blinking cursor is nothing but an annoyance.
(blink-cursor-mode -1)

;; disable the annoying bell ring
(setq ring-bell-function 'ignore)

;; disable startup screen
(setq inhibit-startup-screen t)

;; mode line settings
(line-number-mode t)
(column-number-mode t)
(size-indication-mode t)

;; more useful frame title, that shows either a file or a buffer name
;; (if the buffer isn't visiting a file)
(setq frame-title-format
      '("" invocation-name " - " (:eval (if (buffer-file-name)
                                            (abbreviate-file-name (buffer-file-name))
                                          "%b"))))

;; Death to tabs!
;; Emacs modes typically provide a standard means to change the
;; indentation width -- eg. c-basic-offset: use that to adjust your
;; personal indentation width, while maintaining the style (and
;; meaning) of any files you load.
(setq-default indent-tabs-mode nil)   ;; don't use tabs to indent
(setq-default tab-width 4)            ;; but maintain correct appearance

;; Newline at end of file
(setq require-final-newline t)

;; delete the selection with a keypress
(delete-selection-mode t)

;; store all backup and autosave files in the tmp dir
(setq backup-directory-alist
      `((".*" . ,temporary-file-directory)))
(setq auto-save-file-name-transforms
      `((".*" ,temporary-file-directory t)))

;; Play with restoring ssh buffers between sessions.
;; Emacs does not do this by default because it is slow.
(setq desktop-files-not-to-save "^$")

;; revert buffers automatically when underlying files are changed externally
(global-auto-revert-mode t)

;; disable annoying blink-matching-paren
(setq blink-matching-paren nil)

;; Go to last place in any buffer
(save-place-mode 1)

;; highlight the current line
(global-hl-line-mode +1)

(defun enable-flyspell ()
  "Enable command `flyspell-mode' if spellcheck program can be found."
  (when (executable-find ispell-program-name)
    (flyspell-mode +1)))

(defun enable-whitespace ()
  "Keep the whitespace decent all the time (in this buffer)."
  (add-hook 'before-save-hook 'whitespace-cleanup nil t)
  (whitespace-mode +1))

(add-hook 'text-mode-hook 'enable-flyspell)
(add-hook 'text-mode-hook 'enable-whitespace)
(add-hook 'prog-mode-hook 'enable-whitespace)

;; always delete and copy recursively
(setq dired-recursive-deletes 'always)
(setq dired-recursive-copies 'always)

;; make a shell script executable automatically on save
(add-hook 'after-save-hook
          'executable-make-buffer-file-executable-if-script-p)

;; Disable scroll acceleration
(setq ns-use-mwheel-momentum nil)

;; Active follow mouse
(setq mouse-autoselect-window t)

;; save desktop when idle
(run-with-idle-timer 300 t 'desktop-save-in-desktop-dir)


;; CONFIGURING STANDARD PACKAGES

;; meaningful names for buffers with the same name
(use-package uniquify
  :custom
  (uniquify-buffer-name-style 'forward)
  (uniquify-separator "/")
  (uniquify-after-kill-buffer-p t "rename after killing uniquified")
  (uniquify-ignore-buffers-re "^\\*" "don't muck with special buffers"))

;; savehist keeps track of some history
(use-package savehist
  :custom
  (savehist-additional-variables '(search-ring regexp-search-ring) "search entries")
  (savehist-autosave-interval 60 "save every minute")
  :config
  (savehist-mode +1))

;; whitespace-mode config
(use-package whitespace
  :custom
  (whitespace-line-column 80 "limit line length")
  (whitespace-style '(face tabs empty trailing lines-tail)))

;; bookmarks
(use-package bookmark
  :custom
  (bookmark-save-flag 1))

;; flyspell-mode does spell-checking on the fly as you type
(use-package flyspell
  :custom
  (ispell-program-name "aspell" "use aspell instead of ispell")
  (ispell-extra-args '("--sug-mode=ultra")))


;; DOWNLOADED PACKAGES

;; Cursor for Emacs (https://github.com/MatthewZMD/aidermacs)
(use-package aidermacs
  :straight (:host github :repo "MatthewZMD/aidermacs" :files ("*.el"))
  :custom
  (aidermacs-default-model "anthropic/claude-3-5-sonnet-20241022")
  :config
  (global-set-key (kbd "C-c a") 'aidermacs-transient-menu))

;; direnv support
(use-package envrc
  :straight t
  :config
  (envrc-global-mode))

;; show available keybindings after you start typing
(use-package which-key
  :straight t
  :config
  (which-key-mode t))

(use-package exec-path-from-shell
  :straight t
  :config
  (exec-path-from-shell-initialize))

;; smart pairing (see lisp.el for hooks)
(use-package smartparens
  :straight t
  :custom
  (sp-base-key-bindings 'paredit)
  (sp-autoskip-closing-pair 'always)
  (sp-hybrid-kill-entire-symbol nil)
  :config
  (require 'smartparens-config)
  (sp-use-paredit-bindings)
  (show-smartparens-global-mode +1))

;; Browse cut/copied text.
(use-package browse-kill-ring
  :straight t)

;; Highlight TODO keywords
(use-package hl-todo
  :straight t)

;; temporarily highlight text affected by certain operations (e.g. yank, undo)
(use-package volatile-highlights
  :straight t
  :config
  (volatile-highlights-mode t))

;; anzu-mode enhances isearch & query-replace by showing total matches and current match position
(use-package anzu
  :straight t
  :config
  (global-anzu-mode))

;; sensible undo
(use-package undo-tree
  :straight t
  :config
  (setq undo-tree-history-directory-alist '(("." . "~/.emacs.d/undo")))
  (global-undo-tree-mode))

;; diff-hl - diff highlighting
(use-package diff-hl
  :straight t
  :hook ((dired-mode . diff-hl-dired-mode)
         (magit-post-refresh . diff-hl-magit-post-refresh))
  :config
  (global-diff-hl-mode +1)
  ;; Show in margin for terminal
  (unless (display-graphic-p)
    (diff-hl-margin-mode +1)))

;; enable line numbers (linum is incompatible with diff-hl)
(global-display-line-numbers-mode +1)

;; use settings from .editorconfig file when present
(use-package editorconfig
  :straight t
  :config
  (editorconfig-mode +1))

(use-package popwin
  :straight t
  :config
  (popwin-mode 1))

(use-package direx
  :straight t
  :bind (("C-x C-j" . direx-project:jump-to-project-root-other-window)
         ("C-x C-h" . direx:find-directory-other-window))
  :config
  (require 'direx-project)
  (push '(direx:direx-mode :position left :width 75 :dedicated t)
        popwin:special-display-config))

;; Bookmarks
(use-package bm
  :straight t
  :custom
  (bm-restore-repository-on-load t "Load bookmarks when starting emacs")
  :bind (("<C-f9>" . bm-toggle)
         ("<f9>" . bm-next)
         ("<f10>" . bm-previous)))

;; Toggle first-character and first-non-whitespace-character with C-a
(use-package crux
  :straight t
  :config
  (global-set-key [remap move-beginning-of-line] #'crux-move-beginning-of-line))

;; Automatically save files on buffer and windows switch
;; Disabled by default due to annoyance on remote buffers and mouse clicks
;; @todo see if we can offload this async?
(use-package super-save
  :straight t
  :config
  ;;(super-save-mode +1)
  )

;; Swiper
(use-package swiper :straight t)

;; Org-mode improvements
(use-package org-superstar
  :straight t
  :hook (org-mode . org-superstar-mode))

;; Make the modeline look sexy.
(use-package nerd-icons
  :straight t)
(use-package doom-modeline
  :straight t
  :init (doom-modeline-mode 1))

;; Misc KEY BINDINGS

;; Font size (only for graphical interface)
(when (display-graphic-p)
 (global-set-key (kbd "C-+") 'text-scale-increase)
 (global-set-key (kbd "C--") 'text-scale-decrease))

;; Press ze escape key? WHERE IS ZE ESCAPE KEY?!
(global-set-key (kbd "<escape>") 'keyboard-escape-quit)

;; replace zap-to-char functionality with the more powerful zop-to-char
(use-package zop-to-char
  :straight t
  :bind (("M-z" . zop-up-to-char)
         ("M-Z" . zop-to-char)))

;; replace buffer-menu with ibuffer
(global-set-key (kbd "C-x C-b") 'ibuffer)

;; toggle menu-bar visibility
(global-set-key (kbd "<f12>") 'menu-bar-mode)

;; use menu-bar
(global-set-key (kbd "C-x C-l") 'menu-bar-open)

;; Comments
(global-set-key [f3] 'comment-region)
(global-set-key [f4] 'uncomment-region)

;; Buffer revert
(global-set-key [f5] 'revert-buffer)

;; Goto line
(global-set-key [f7] 'goto-line)

(defun switch-to-previous-buffer ()
  "Toggle between the previous buffer"
  (interactive)
  (switch-to-buffer (other-buffer)))

;; Easy buffer toggling (C-tab does not escape on terminals to use S-tab).
(global-set-key [C-tab] 'switch-to-previous-buffer)
(global-set-key (kbd "<backtab>") 'switch-to-previous-buffer)

;; Rebind delete key to delete-char function
(global-set-key [delete] 'delete-char)

(defun unfill-region (beg end)
  "Unfill the region, joining text paragraphs into a single
    logical line.  This is useful, e.g., for use with
    `visual-line-mode'."
  (interactive "*r")
  (let ((fill-column (point-max)))
    (fill-region beg end)))

;; Handy key definition
(global-set-key (kbd "M-p") 'unfill-region)

;; Don't use standard beginning/end commands that set mark.
(global-set-key (kbd "M-<") #'(lambda ()
                               (interactive)
                               (goto-char (point-min))))
(global-set-key (kbd "M->") #'(lambda ()
                               (interactive)
                               (goto-char (point-max))))
