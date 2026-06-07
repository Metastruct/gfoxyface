local Tag = 'gfoxyface'
local gfoxyface = gfoxyface or {}
gfoxyface.Tag = Tag
_G.gfoxyface = gfoxyface
include("gfoxyface/shared.lua")
if SERVER then
    util.AddNetworkString(gfoxyface.Tag)
    AddCSLuaFile("gfoxyface/shared.lua")
    AddCSLuaFile("gfoxyface/client.lua")
    AddCSLuaFile("gfoxyface/vrcft.lua")
    AddCSLuaFile("gfoxyface/osc_parser.lua")
    AddCSLuaFile("gfoxyface/main.lua")
    include("gfoxyface/server.lua")
    return
end

include("gfoxyface/client.lua")