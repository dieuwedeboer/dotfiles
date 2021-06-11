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


;; OCTAVE

(use-package octave
  :bind (("C-c C-j" . octave-send-line)
         ("C-c C-k" . octave-send-defun)))
