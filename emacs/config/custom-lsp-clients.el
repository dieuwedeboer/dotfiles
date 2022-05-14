(require 'lsp-mode)

;; Tell TRAMP to load the SSH user's path.
(add-to-list 'tramp-remote-path 'tramp-own-remote-path)

;; Run intelephense on the remote server with similar settings to its local default.
(lsp-register-client
 (make-lsp-client :new-connection (lsp-tramp-connection '("intelephense" "--stdio"))
                     :major-modes '(php-mode)
                     :remote? t
                     :activation-fn (lsp-activate-on "php")
                     :priority -1
                     :notification-handlers (ht ("indexingStarted" #'ignore)
                                                ("indexingEnded" #'ignore))
                     :initialization-options (lambda ()
                                               (list :storagePath lsp-intelephense-storage-path
                                                     :globalStoragePath lsp-intelephense-global-storage-path
                                                     :licenceKey lsp-intelephense-licence-key
                                                     :clearCache lsp-intelephense-clear-cache))
                     :completion-in-comments? t
                     :server-id 'iph-remote))
