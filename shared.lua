gfoxyface = gfoxyface or {}
gfoxyface.Tag = "gfoxyface"
gfoxyface.debug = gfoxyface.debug or false

function gfoxyface.dbg(...)
  if not gfoxyface.debug then return end
  Msg"[GFoxyFace]"
  print(...)
end

function gfoxyface.on_vrcft(param, ...)
  gfoxyface.dbg(param, ...)
end

function gfoxyface.network_server(...)
  local ok = pcall(net.Start, gfoxyface.Tag, true)
  if ok then net.SendToServer() end
end
