include("gfoxyface/vrcft.lua")

CreateClientConVar("gfoxyface_autoenable", "1", true)
CreateClientConVar("gfoxyface_listen_port", "9000", true)
CreateClientConVar("gfoxyface_send_port", "9001", true)

vrcft.setup{
  listen_port = GetConVarNumber("gfoxyface_listen_port"),
  send_port = GetConVarNumber("gfoxyface_send_port"),
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

if GetConVarNumber("gfoxyface_autoenable") ~= 0 then
  vrcft.listen(gfoxyface.on_vrcft)
end

concommand.Add("gfoxyface_start", function() gfoxyface.start_listener() end)
concommand.Add("gfoxyface_stop", function() gfoxyface.stop_listener() end)
