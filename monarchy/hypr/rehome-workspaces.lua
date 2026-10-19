-- Unplugging the screen a laptop panel mirrors leaves Hyprland with no outputs
-- for a moment. Workspaces parked during that gap stay on no monitor once the
-- panel comes back, and their windows are unreachable. An ordinary unplug
-- with another output still on is handled by Hyprland itself.

local function home()
  local active = hl.get_active_monitor()
  if active and not active.is_mirror then
    return active
  end
  for _, mon in ipairs(hl.get_monitors()) do
    if not mon.is_mirror then
      return mon
    end
  end
end

local function rehome()
  local dest = home()
  if not dest then
    return
  end
  for _, ws in ipairs(hl.get_workspaces()) do
    if not ws.special and not ws.monitor then
      hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(ws.id), monitor = dest.name }))
    end
  end
end

-- The panel returns a beat after the removal event, so check again once the
-- outputs have settled.
local function soon()
  rehome()
  hl.timer(rehome, { timeout = 500, type = "oneshot" })
end

hl.on("monitor.removed", soon)
hl.on("monitor.added", soon)
hl.on("monitor.layout_changed", soon)
