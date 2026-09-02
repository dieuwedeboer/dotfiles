-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- First dwindle split on an ultrawide (aspect >= 2) is 2/3 | 1/3.
-- After that, splits are stock 50/50 of the focused pane: the wide side
-- becomes three columns, the narrow side stacks.
local ultrawide_min_ratio = 2
local first_split = 4 / 3
local even_split = 1
local armed

local function is_ultrawide(mon)
  return mon and mon.height and mon.height > 0 and mon.width / mon.height >= ultrawide_min_ratio
end

local function tiled_on(ws, exclude)
  local n = 0
  for _, win in ipairs(hl.get_windows() or {}) do
    if win ~= exclude and win.workspace and win.workspace.id == ws.id and not win.floating then
      n = n + 1
    end
  end
  return n
end

local function desired_ratio(exclude)
  local ws = hl.get_active_workspace()
  if not ws or ws.special then
    return even_split
  end
  local layout = ws.tiled_layout or hl.get_config("general.layout")
  if layout ~= "dwindle" then
    return even_split
  end
  if not is_ultrawide(ws.monitor) then
    return even_split
  end
  if tiled_on(ws, exclude) ~= 1 then
    return even_split
  end
  return first_split
end

local function apply(exclude)
  local ratio = desired_ratio(exclude)
  if armed == ratio then
    return
  end
  armed = ratio
  hl.config({ ["dwindle.default_split_ratio"] = ratio })
end

apply()

hl.on("window.open", function()
  apply()
end)
hl.on("window.close", function(win)
  apply(win)
end)
hl.on("window.destroy", function()
  apply()
end)
hl.on("window.active", function()
  apply()
end)
hl.on("window.move_to_workspace", function()
  apply()
end)
hl.on("workspace.active", function()
  apply()
end)
hl.on("workspace.move_to_monitor", function()
  apply()
end)
hl.on("monitor.added", function()
  apply()
end)
hl.on("monitor.removed", function()
  apply()
end)
hl.on("monitor.layout_changed", function()
  apply()
end)

-- Keep the Omarchy screensaver (and the lock that follows it) away while
-- games or video are on screen. Hyprland's idle_inhibit rule suppresses the
-- ext-idle-notify events that omarchy-shell counts idle time from.
-- https://wiki.hypr.land/Configuring/Window-Rules/

-- Native Steam games get class steam_app_<appid>, and some are wrapped in
-- gamescope. Omarchy only inhibits while such a window is fullscreen, which
-- misses borderless-windowed games, so inhibit for as long as one is open.
o.window("^steam_app_[0-9]+$", { idle_inhibit = "always" })
o.window("^gamescope$", { idle_inhibit = "always" })

-- Proton and Wine games report the Windows executable as their class.
o.window("\\.exe$", { idle_inhibit = "fullscreen" })

-- Local video players. Browsers hold their own inhibitor during playback.
o.window("^(mpv|vlc)$", { idle_inhibit = "fullscreen" })
