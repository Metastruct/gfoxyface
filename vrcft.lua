--- Hacky module for receiving VRCFT data, pretending to be VRChat with OSC.
---
--- Parses incoming OSC bundles/messages from VRCFT on a UDP socket,
--- and sends OSC messages back to VRChat. Uses luasocket (`_G.socket`).
---
--- Public API (exported via `_G.vrcft`):
---   - `vrcft.setup({listen_port, send_port, send_host})`
---   - `vrcft.listen(callback)`         — set callback & start
---   - `vrcft.start()`                  — start UDP receiver
---   - `vrcft.stop()`                   — stop receiver, close socket
---   - `vrcft.send(address, ...)`       — send OSC message to VRChat
local DEBUG = true
local function dbg(...)
	if not DEBUG then return end
	Msg "[vrcft] "
	print(...)
end
local Tag = "vrcft"
local _osc = include("gfoxyface/osc_parser.lua")
local parse_osc, build_osc_message = _osc.parse_osc, _osc.build_osc_message
local callback
local STATE_KEY = "gf_vrcft"
local cfg = {
	send_host = "127.0.0.1",
	send_port = 9001,
	listen_port = 9000
}

local function state()
	local s = rawget(_G, STATE_KEY)
	if not s then
		s = {}
		rawset(_G, STATE_KEY, s)
	end
	return s
end

local function dispatch(msg)
	if not callback then return end
	if msg.address == "#bundle" then
		for _, sub in ipairs(msg.args) do
			callback(sub.address, unpack(sub.args))
		end
	else
		callback(msg.address, unpack(msg.args))
	end
end

local function on_receive(data, ip, port)
	local ok, msg = pcall(parse_osc, data)
	if ok and msg then dispatch(msg) end
end

--- Close the UDP socket and stop the receiver timer.
local function stop()
	local s = state()
	timer.Remove(Tag)
	if s.sock then
		s.sock:close()
		s.sock = nil
	end
end

local function poll(sock)
	return function()
		while true do
			local data, ip, port = sock:receivefrom()
			if not data then
				if ip ~= "timeout" then dbg("receive error:", ip) end
				return
			end

			on_receive(data, ip, port)
		end
	end
end

--- Bind the UDP socket and start the polling timer (0.01 s interval).
--- Calls `stop()` first to clean up any previous session.
local function start()
	local socket = _G.socket
	if not socket or not socket.udp then return nil, "no socket" end
	stop()
	local s = state()
	local sock = socket.udp()
	sock:settimeout(0)
	for attempt = 1, 3 do
		local ok, err = sock:setsockname("0.0.0.0", cfg.listen_port)
		if ok then break end
		if attempt < 3 then
			collectgarbage()
			sock:close()
			sock = socket.udp()
			sock:settimeout(0)
		else
			dbg("failed to bind port", cfg.listen_port, "(", tostring(err), ")")
			sock:close()
			return
		end
	end

	timer.Create(Tag, 0.01, 0, poll(sock))
	s.sock = sock
	dbg("listening on port", cfg.listen_port)
	return true
end

--- Set the OSC message callback and start the receiver.
--- Equivalent to setting the callback then calling `start()`.
--- @param cb function  Function called as `cb(address, ...)` on each message.
local function listen(cb)
	callback = cb
	return start()
end

--- Configure OSC settings. Accepted keys:
---   - `listen_port` (number, default 9000)
---   - `send_port`   (number, default 9001)
---   - `send_host`   (string, default "127.0.0.1")
--- @param opts table
local function setup(opts)
	if type(opts) == "table" then
		for k, v in pairs(opts) do
			cfg[k] = v
		end
	end
end

--- Build and send an OSC message to the configured host/port.
--- @param address string  OSC address (e.g. `/avatar/parameters/VRCEmote`)
--- @param ... any          Arguments (string, number, boolean)
local function send(address, ...)
	local socket = _G.socket
	if not socket then return nil, "no socket" end
	local s = state().sock_send
	if not s then
		s = socket.udp()
		state().sock_send = s
	end

	local data = build_osc_message(address, ...)
	local ok, err = s:sendto(data, cfg.send_host, cfg.send_port)
	if not ok then dbg("send error:", err) end
	return true
end

local _M = {
	listen = listen,
	start = start,
	stop = stop,
	send = send,
	setup = setup
}

_G.vrcft = _M
return _M
