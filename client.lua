include("gfoxyface/vrcft.lua")

local gfoxyface_autoenable = CreateClientConVar("gfoxyface_autoenable", "1", true)
local gfoxyface_listen_port = CreateClientConVar("gfoxyface_listen_port", "9000", true)
local gfoxyface_send_port = CreateClientConVar("gfoxyface_send_port", "9001", true)
local dbg = gfoxyface.dbg

vrcft.setup{
  listen_port = gfoxyface_listen_port:GetInt(),
  send_port = gfoxyface_send_port:GetInt(),
}

function gfoxyface.send(...)
  vrcft.send(...)
end

function gfoxyface.start()
  vrcft.send("/avatar/change", "avtr_3efe552c-3f33-4eff-b360-26ccb5c925a1")
end

function gfoxyface.start_listener()
  vrcft.start()
end

function gfoxyface.stop_listener()
  vrcft.stop()
end

if gfoxyface_autoenable:GetBool() then
  dbg("autoenable listener")
  vrcft.listen(gfoxyface.on_vrcft)
end

concommand.Add("gfoxyface_start", function() gfoxyface.start_listener() end)
concommand.Add("gfoxyface_stop", function() gfoxyface.stop_listener() end)
