local gfoxyface = _G.gfoxyface

--- Enable debug output. Overridden by `CreateClientConVar("gfoxyface_debug")`.
--- @type boolean
gfoxyface.debug = gfoxyface.debug or true

--- Print message if debug is enabled.
--- @param ... any
local function dbg(...)
  if not gfoxyface.debug then return end
  Msg"[GFoxyFace] "
  print(...)
end
gfoxyface.dbg = dbg
dbg("loading")

--- Default handler for incoming OSC messages. Overridden in client.lua to
--- also track state and send frametimes to the server.
--- @param param string  OSC address (e.g. `/avatar/parameters/VRCEmote`)
--- @param ...   any     OSC arguments
function gfoxyface.on_vrcft(param, ...)
  dbg(param, ...)
end

--- Send a frametime float to the server via the `gfoxyface.Tag` net channel.
--- @param ft number  Frametime value to send (sanity-checked before call)
function gfoxyface.network_server(ft)
  local ok, err = pcall(net.Start, gfoxyface.Tag, true)
  if ok then
    net.WriteFloat(ft)
    net.SendToServer()
  else
    dbg("network_server error:", err)
  end
end

net.Receive(gfoxyface.Tag, function(len, pl) gfoxyface.on_net(len, pl) end)
