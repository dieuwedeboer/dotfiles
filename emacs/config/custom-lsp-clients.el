;; Ensure LSP is loaded.
(require 'lsp-mode)

;; Tell TRAMP to load the SSH user's path.
(add-to-list 'tramp-remote-path 'tramp-own-remote-path)

;; Commands to run on the remote server (note it must have PHP execuatable).
;; curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
;; source ~/.profile
;; npm i intelephense -g

;; Still does not work over TRAMP
;; https://github.com/emacs-lsp/lsp-mode/pull/2531
;; https://github.com/emacs-lsp/lsp-mode/issues/1845
;; Do I need to update TRAMP?
;; Or is it caused by Doom?
;; https://github.com/doomemacs/doomemacs/issues/3390

;; Run intelephense on the remote server with similar settings
;; to its local default.
(lsp-register-client
 (make-lsp-client :new-connection (lsp-tramp-connection '("intelephense" "--stdio"))
                     :major-modes '(php-mode)
                     :remote? t
                     :priority -1
                     :notification-handlers (ht ("indexingStarted" #'ignore)
                                                ("indexingEnded" #'ignore))
                     :initialization-options (lambda ()
                                               (list :storagePath lsp-intelephense-storage-path
                                                     :globalStoragePath lsp-intelephense-global-storage-path
                                                     :licenceKey lsp-intelephense-licence-key
                                                     :clearCache lsp-intelephense-clear-cache))
                     :completion-in-comments? t
                     ;;:multi-root lsp-intelephense-multi-root
                     :server-id 'iph-remote))
