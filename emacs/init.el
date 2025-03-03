(defvar emacs-dir (file-name-directory load-file-name)
  "The root dir of the Emacs configuration.")

(desktop-save-mode 1)
;; Reduce the frequency of garbage collection by making it happen on
;; each 50MB of allocated data (the default is on every 0.76MB).
(setq gc-cons-threshold 50000000)

;; Warn when opening files bigger than 100MB.
(setq large-file-warning-threshold 100000000)

;; Config changes made through the customize UI will be store here.
(setq custom-file (expand-file-name "custom.el" emacs-dir))

;; Prevent warning buffer from popping up.
(setq native-comp-async-report-warnings-errors 'silent)

;; Set up Straight as the package manager.
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 5))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'use-package)

;; Git setup.
(use-package magit
  :straight t)
(use-package git-modes
  :straight t)
;; Docker support.
(use-package dockerfile-mode
  :straight t)

;; Load environment/language specific configuration.
(defvar config-dir (expand-file-name "config" emacs-dir))

;; Custom everything else.
;;(load (expand-file-name "theme.el" config-dir))
(load (expand-file-name "general.el" config-dir))
;;(load (expand-file-name "helm.el" config-dir))
(load (expand-file-name "programming.el" config-dir))
(load (expand-file-name "markup.el" config-dir))
(load (expand-file-name "web.el" config-dir))
(load (expand-file-name "php.el" config-dir))
(load (expand-file-name "lisp.el" config-dir))
;;(load (expand-file-name "music.el" config-dir))


;; WIP

;; scroll before reaching end of bottom, and also scroll without jumping
(use-package smooth-scrolling
  :straight t
  :config
  (smooth-scrolling-mode 1)
  (setq smooth-scroll-margin 4))
