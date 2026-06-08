local gfoxyface = gfoxyface
local dbg = gfoxyface.dbg
local Tag = assert(gfoxyface.Tag,"loading order fail")
local DEBUG = true
util.AddNetworkString(Tag)

--- @type table<Player, number>
gfoxyface.last_seen = gfoxyface.last_seen or {}
--- @type table<Player, table>
gfoxyface.state_setup = gfoxyface.state_setup or {}
gfoxyface._warned_setup_spam = gfoxyface._warned_setup_spam or {}

local warned_tick_dedup = false
local now = CurTime()
hook.Add("Tick", Tag, function()
	now = CurTime()
end)

gfoxyface._last_setup_sv = gfoxyface._last_setup_sv or {}

function gfoxyface.on_net_setup(len, ply)
	local rt = RealTime()
	if gfoxyface._last_setup_sv[ply] and rt - gfoxyface._last_setup_sv[ply] < 1 then
		if not gfoxyface._warned_setup_spam[ply] or rt - gfoxyface._warned_setup_spam[ply] > 5 then
			gfoxyface._warned_setup_spam[ply] = rt
			ply:ChatPrint("[GFoxyFace] setup rate-limited (1/sec)")
		end
		return
	end
	gfoxyface._last_setup_sv[ply] = rt
	local count = net.ReadUInt(8)
	local entries = {}
	for i = 1, count do
		entries[i] = { id = net.ReadUInt(32), name = net.ReadString() }
	end
	gfoxyface.state_setup[ply] = entries -- TODO: remove? not needed?
	net.Start(Tag, true)
	net.WriteUInt(0, 4)
	net.WritePlayer(ply)
	net.WriteUInt(count, 8)
	for i = 1, count do
		net.WriteUInt(entries[i].id, 32)
		net.WriteString(entries[i].name)
	end
	net.SendPVS(ply:GetPos())
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
	if not last or now - last > 20 then
		dbg("face tracking started by", ply:Name(), ply:SteamID())
	end
	gfoxyface.last_seen[ply] = now
	local count = net.ReadUInt(8)
	local flexes = {}
	for i = 1, count do
		flexes[i] = { name = net.ReadString(), val = net.ReadFloat() }
	end
	net.Start(Tag, true)
	net.WriteUInt(1, 4)
	net.WritePlayer(ply)
	net.WriteFloat(ft)
	net.WriteUInt(count, 8)
	for i = 1, count do
		net.WriteString(flexes[i].name)
		net.WriteFloat(flexes[i].val)
	end
	net.SendPVS(ply:GetPos())
end
