local Tag = "gfoxyface"
local gfoxyface = _G.gfoxyface or {}
gfoxyface.Tag = Tag
_G.gfoxyface = gfoxyface

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
dbg("loading...")

--- Send a frametime float to the server via the `gfoxyface.Tag` net channel.
--- @param ft number  Frametime value to send (sanity-checked before call)
function gfoxyface.network_server(ft)
	local ok, err = pcall(net.Start, Tag, true)
	if not ok then
		return
	end

	net.WriteUInt(1, 4)
	net.WriteFloat(ft)
	net.WriteUInt(0, 8)
	net.SendToServer()

end

function gfoxyface.send_flex_setup(entries)
	-- network flex names to be modified by on_net_flexes
	local ok, err = pcall(net.Start, Tag, true)
	if not ok then
		return
	end

	net.WriteUInt(0, 4)
	net.WriteUInt(#entries, 8)
	for _, e in ipairs(entries) do
		net.WriteUInt(e.id, 32)
		net.WriteString(e.name)
	end
	net.SendToServer()
end

local CB_NAMES = {
	"on_net_setup",
	"on_net_flexes"
}
net.Receive(Tag, function(len, pl)
	local mode = net.ReadUInt(4)
	local cb = CB_NAMES[mode + 1]
	if cb and gfoxyface[cb] then
		gfoxyface[cb](len, pl)
	else
		dbg("unknown net mode", mode)
	end
end)
