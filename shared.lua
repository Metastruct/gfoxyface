local gfoxyface = _G.gfoxyface

--- Enable debug output. Overridden by `CreateClientConVar("gfoxyface_debug")`.
--- @type boolean
gfoxyface.debug = gfoxyface.debug or true

--- Print message if debug is enabled.
--- @param ... any
local function dbg(...)
	if not gfoxyface.debug then return end
	Msg "[GFoxyFace] "
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
		net.WriteUInt(1, 4)
		net.WriteFloat(ft)
		net.WriteUInt(0, 8)
		net.SendToServer()
	else
		dbg("network_server error:", err)
	end
end

function gfoxyface.network_server_setup(entries)
	local ok, err = pcall(net.Start, gfoxyface.Tag, true)
	if ok then
		net.WriteUInt(0, 4)
		net.WriteUInt(#entries, 8)
		for _, e in ipairs(entries) do
			net.WriteUInt(e.id, 32)
			net.WriteString(e.name)
		end
		net.SendToServer()
	else
		dbg("network_server_setup error:", err)
	end
end

local CB_NAMES = {
	"on_net_setup",
	"on_net_flexes"
}
net.Receive(gfoxyface.Tag, function(len, pl)
	local mode = net.ReadUInt(4)
	local cb = CB_NAMES[mode + 1]
	if cb and gfoxyface[cb] then
		gfoxyface[cb](len, pl)
	else
		dbg("unknown net mode", mode)
	end
end)
