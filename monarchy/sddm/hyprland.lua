-- Minimal Hyprland config for the SDDM Wayland greeter.
-- SDDM starts the greeter itself after the compositor is ready.
-- background_color matches Unlock #1a1b26 so the first frame is not grey.
hl.config({
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
    background_color = "rgb(26, 27, 38)",
  },

  animations = {
    enabled = false,
  },
})
