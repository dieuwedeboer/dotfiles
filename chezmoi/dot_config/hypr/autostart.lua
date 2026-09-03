-- Extra autostart processes.

-- Unlock KWallet so NetworkManager can use Wi-Fi secrets saved under Plasma.
o.launch_on_start("/usr/lib/pam_kwallet_init")
