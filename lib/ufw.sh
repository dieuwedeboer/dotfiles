#!/usr/bin/env bash
# Write the incoming allows. Do not enable or disable the firewall.
# ufw enable / ufw disable is the per-machine switch and it persists.
# Home vs cafe cannot be decided from this repo: RFC1918 is every hotel
# NAT, and SSID / gateway MAC / public IP do not belong in a public git.

ufw_apply_rules() {
    sudo ufw allow 8010/tcp comment 'VLC Chromecast HTTP stream'
    sudo ufw allow 1900/udp comment 'VLC Chromecast discovery (UPnP)'
    sudo ufw allow 22/tcp comment 'SSH'
    sudo ufw allow 25565/tcp comment 'Minecraft servers'
    sudo ufw allow 4445/udp comment 'Minecraft LAN discovery'
}
