local gfoxyface = gfoxyface
local dbg = gfoxyface.dbg
local Tag = gfoxyface.Tag

--- @type table<Player, number>
gfoxyface.last_seen = gfoxyface.last_seen or {}
--- @type table<Player, table>
gfoxyface.state_setup = gfoxyface.state_setup or {}

local warned_tick_dedup = false
local now = CurTime()
hook.Add("Tick", Tag, function()
	now = CurTime()
end)

function gfoxyface.on_net_setup(len, ply)
	local count = net.ReadUInt(8)
	local entries = {}
	for i = 1, count do
		entries[i] = { id = net.ReadUInt(32), name = net.ReadString() }
	end
	gfoxyface.state_setup[ply] = entries
	net.Start(Tag, true)
	net.WriteUInt(0, 4)
	net.WritePlayer(ply)
	net.WriteUInt(count, 8)
	for i = 1, count do
		net.WriteUInt(entries[i].id, 32)
		net.WriteString(entries[i].name)
	end
	net.SendPVS(ply)
end

function gfoxyface.on_net_flexes(len, ply)
	local ft = net.ReadFloat()
	local last = gfoxyface.last_seen[ply]
	if last and now == last then
		if not warned_tick_dedup then
			warned_tick_dedup = true
			dbg("tick dedup (same-tick messages dropped):", ply)
		end
		return
	end
	if not last then
		dbg("face tracking started by", ply:Name(), ply:SteamID())
	end
	gfoxyface.last_seen[ply] = now
	local count = net.ReadUInt(8)
	local flexes = {}
	for i = 1, count do
		flexes[i] = { id = net.ReadUInt(32), val = net.ReadFloat() }
	end
	net.Start(Tag, true)
	net.WriteUInt(1, 4)
	net.WritePlayer(ply)
	net.WriteFloat(ft)
	net.WriteUInt(count, 8)
	for i = 1, count do
		net.WriteUInt(flexes[i].id, 32)
		net.WriteFloat(flexes[i].val)
	end
	net.SendPVS(ply)
end
