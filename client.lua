include("gfoxyface/vrcft.lua")

local gfoxyface = gfoxyface
local gfoxyface_autoenable = CreateClientConVar("gfoxyface_autoenable", "0", true)
local gfoxyface_listen_port = CreateClientConVar("gfoxyface_listen_port", "9000", true)
local gfoxyface_send_port = CreateClientConVar("gfoxyface_send_port", "9001", true)
local gfoxyface_debug_ui = CreateClientConVar("gfoxyface_debug_ui", "0", true)
local gfoxyface_see_others = CreateClientConVar("gfoxyface_see_others", "1", true)
local dbg = gfoxyface.dbg
local last_realtime = 0

--- Reset the frametime delta timer to now. Call before starting the listener
--- so the first delta isn't a huge value.
function gfoxyface.reset_frametime()
  last_realtime = RealTime()
end

local _on_vrcft = gfoxyface.on_vrcft
local vrcft_count = 0

--- Latest known VRChat avatar parameter values, keyed by parameter name
--- (stripped of `/avatar/parameters/` prefix).
--- @type table<string, any>
gfoxyface.state = {}

--- Mirrors `state` keys with the RealTime() of the most recent update.
--- @type table<string, number>
gfoxyface.state_last_updated = {}

--- Override of the shared `on_vrcft`. Stores incoming OSC data into
--- `gfoxyface.state`, computes the inter-message frametime, sends it to
--- the server via `net`, and calls the original shared handler for debug.
--- @param param string  Full OSC address (prefix is stripped for state key)
--- @param ...   any     OSC argument values
function gfoxyface.on_vrcft(param, ...)
  if vrcft_count < 15 then
    vrcft_count = vrcft_count + 1
    dbg("vrcft[" .. vrcft_count .. "]", param, ...)
  end
  local key = param:match("^/avatar/parameters/(.+)$") or param
  local args = {...}
  if #args == 1 then
    gfoxyface.state[key] = args[1]
  elseif #args > 0 then
    gfoxyface.state[key] = args
  end
  gfoxyface.state_last_updated[key] = RealTime()
  local rt = RealTime() 
  local ft = rt - last_realtime
  last_realtime = rt
  if ft > 0 and ft <= 1 then
    gfoxyface.network_server(ft)
  end
  _on_vrcft(param, ...)
end

vrcft.setup{
  listen_port = gfoxyface_listen_port:GetInt(),
  send_port = gfoxyface_send_port:GetInt(),
}

--- Send an arbitrary OSC message to VRChat.
--- @param ... any  OSC address followed by arguments
function gfoxyface.send(...)
  vrcft.send(...)
end

--- Send avatar change and enable tracking parameters.
function gfoxyface.start()
  vrcft.send("/avatar/change", "avtr_3efe552c-3f33-4eff-b360-26ccb5c925a1")
  vrcft.send("/avatar/parameters/LipTrackingActive", true)
  vrcft.send("/avatar/parameters/EyeTrackingActive", true)
end

gfoxyface.running = false

--- Start the OSC listener (UDP socket + timer). Resets frametime delta.
function gfoxyface.start_listener()
  if gfoxyface.running then return end
  gfoxyface.running = true
  gfoxyface.reset_frametime()
  dbg("start listener")
  vrcft.listen(gfoxyface.on_vrcft)
end

--- Stop the OSC listener (close socket, remove timer).
function gfoxyface.stop_listener()
  gfoxyface.running = false
  vrcft.stop()
end

local function autoenable()
  if not gfoxyface_autoenable:GetBool() then return end
  dbg("autoenable listener")
  gfoxyface.start_listener()
end

if IsValid(LocalPlayer()) then
  autoenable()
else
  hook.Add("InitPostEntity", "gfoxyface_autoenable", function()
    timer.Simple(1, autoenable)
  end)
end

--- @type table<Player, number>
gfoxyface.last_seen = gfoxyface.last_seen or {}

function gfoxyface.on_net()
  local ply = net.ReadPlayer()
  local ft = net.ReadFloat()
  if ply and ply:IsValid() and (ply == LocalPlayer() or gfoxyface_see_others:GetBool()) then
    if not gfoxyface.last_seen[ply] then
      dbg("face tracking started by", ply:Name(), ply:SteamID())
    end
    gfoxyface.last_seen[ply] = CurTime()
  end
end

concommand.Add("gfoxyface_start", function()
  if gfoxyface.running then
    dbg("already running")
    return
  end
  gfoxyface.start_listener()
end)
concommand.Add("gfoxyface_stop", function()
  if not gfoxyface.running then return end
  gfoxyface.stop_listener()
end)

hook.Add("HUDPaint", "gfoxyface_debug_ui", function()
  if not gfoxyface_debug_ui:GetBool() then return end
  local now = RealTime()
  local y = 10
  local bar_x, bar_w = 200, 200
  local half_w = bar_w / 2
  local center_x = bar_x + half_w
  local keys = table.GetKeys(gfoxyface.state)
  table.sort(keys)
  for _, key in ipairs(keys) do
    local value = gfoxyface.state[key]
    local last = gfoxyface.state_last_updated[key]
    if last and now - last <= 5 then
      draw.DrawText(key, "DermaDefault", 10, y, Color(255,255,255), TEXT_ALIGN_LEFT)
      if type(value) == "number" then
        local clamped = math.Clamp(value, -1, 1)
        local val_x = center_x + clamped * half_w
        surface.SetDrawColor(50, 50, 50, 200)
        surface.DrawRect(bar_x, y + 4, bar_w, 10)
        surface.SetDrawColor(173, 216, 230, 220)
        if clamped >= 0 then
          surface.DrawRect(center_x, y + 4, val_x - center_x, 10)
        else
          surface.DrawRect(val_x, y + 4, center_x - val_x, 10)
        end
        draw.DrawText(string.format("%.3f", value), "DermaDefault", bar_x + bar_w + 5, y, Color(255,255,255), TEXT_ALIGN_LEFT)
      else
        draw.DrawText(tostring(value), "DermaDefault", bar_x, y, Color(200,200,200), TEXT_ALIGN_LEFT)
      end
      y = y + 22
    end
  end
end)
