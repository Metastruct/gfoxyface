include("gfoxyface/vrcft.lua")

local gfoxyface = gfoxyface
local Tag = assert(gfoxyface.Tag,"loading order fail")
local gfoxyface_autoenable = CreateClientConVar("gfoxyface_autoenable", "0", true)
local gfoxyface_listen_port = CreateClientConVar("gfoxyface_listen_port", "9000", true)
local gfoxyface_send_port = CreateClientConVar("gfoxyface_send_port", "9001", true)
local gfoxyface_debug_ui = CreateClientConVar("gfoxyface_debug_ui", "0", true)
local gfoxyface_debug_ui_3d = CreateClientConVar("gfoxyface_debug_ui_3d", "0", true)
local gfoxyface_see_others = CreateClientConVar("gfoxyface_see_others", "1", true)
local gfoxyface_debug_loopback = CreateClientConVar("gfoxyface_debug_loopback", "0", true)
local dbg = gfoxyface.dbg
local last_realtime = 0

--- Reset the frametime delta timer to now. Call before starting the listener
--- so the first delta isn't a huge value.
function gfoxyface.reset_frametime()
	last_realtime = RealTime()
end

local vrcft_count = 0

--- Latest known VRChat avatar parameter values, keyed by parameter name
--- (stripped of `/avatar/parameters/` prefix).
--- @type table<string, any>
gfoxyface.state = {}

--- Mirrors `state` keys with the RealTime() of the most recent update.
--- @type table<string, number>
gfoxyface.state_last_updated = {}

--- Stores incoming OSC data into `gfoxyface.state`.
--- Frametime and flex networking is handled by the Tick hook.
--- @param param string  Full OSC address (prefix is stripped for state key)
--- @param ...   any     OSC argument values
function gfoxyface.on_vrcft(param, ...)
	if vrcft_count < 15 then
		vrcft_count = vrcft_count + 1
		dbg("vrcft[" .. vrcft_count .. "]", param, ...)
	end
	local key = param:match("^/avatar/parameters/(.+)$") or param
	local args = { ... }
	local now = RealTime()
	if key == "tracking/eye/LeftRightPitchYaw" and #args >= 4 then
		local names = { "leftPitch", "leftYaw", "rightPitch", "rightYaw" }
		for i, name in ipairs(names) do
			local subkey = key .. "/" .. name
			gfoxyface.state[subkey] = args[i]
			gfoxyface.state_last_updated[subkey] = now
		end
	elseif #args == 1 then
		gfoxyface.state[key] = args[1]
		gfoxyface.state_last_updated[key] = now
	elseif #args > 0 then
		gfoxyface.state[key] = args
		gfoxyface.state_last_updated[key] = now
	end
end

vrcft.setup {
	listen_port = gfoxyface_listen_port:GetInt(),
	send_port = gfoxyface_send_port:GetInt(),
}

--- Send an arbitrary OSC message to VRChat.
--- @param ... any  OSC address followed by arguments
function gfoxyface.send(...)
	vrcft.send(...)
end
gfoxyface.tracking_avatar_name = "avtr_3efe552c-3f33-4eff-b360-26ccb5c925a1"
--- Send avatar change and enable tracking parameters.
function gfoxyface.request_tracking()
	vrcft.send("/avatar/change", gfoxyface.tracking_avatar_name)
	vrcft.send("/avatar/parameters/LipTrackingActive", true)
	vrcft.send("/avatar/parameters/EyeTrackingActive", true)
	dbg("Fake tracking avatar: ","https://vrchat.com/home/avatar/" .. gfoxyface.tracking_avatar_name)
end

gfoxyface.running = false

--- Start the OSC listener (UDP socket + timer). Resets frametime delta.
function gfoxyface.start()
	if not _G.socket then
		if util.IsBinaryModuleInstalled("socket.core") then
			require("socket")
		else
			dbg("cannot start — luasocket missing")
			return
		end
	end
	if gfoxyface.running then
		dbg("already running")
		return
	end
	gfoxyface.reset_frametime()
	local ok = vrcft.listen(gfoxyface.on_vrcft)
	gfoxyface.running = ok == true
	if ok then
		dbg("started listener on port", gfoxyface_listen_port:GetInt())
	else
		dbg("failed to start listener")
	end
end

--- Stop the OSC listener (close socket, remove timer).
function gfoxyface.stop_listener()
	if not gfoxyface.running then
		dbg("not running")
		return
	end
	gfoxyface.running = false
	vrcft.stop()
end

local function autoenable()
	if not gfoxyface_autoenable:GetBool() then return end
	dbg("autoenable listener")
	gfoxyface.start()
end

if IsValid(LocalPlayer()) then
	autoenable()
else
	hook.Add("InitPostEntity", "gfoxyface_autoenable", function()
		timer.Simple(1, autoenable)
	end)
end

--- @type table<Player, number>
gfoxyface.last_seen = gfoxyface.last_seen or {}

function gfoxyface.on_net_setup()
	local ply = net.ReadPlayer()
	if not ply or not ply:IsValid() then return end
	if ply == LocalPlayer() then return end
	local count = net.ReadUInt(8)
	gfoxyface.state_setup[ply] = {}
	for i = 1, count do
		local id = net.ReadUInt(32)
		local name = net.ReadString()
		gfoxyface.state_setup[ply][id] = name
	end
end

gfoxyface.state_setup = {}
gfoxyface._flex_results = {}

local ply_warn_times = {}
function gfoxyface.on_net_flexes()
	local ply = net.ReadPlayer()
	local ft = net.ReadFloat()
	if not ply or not ply:IsValid() then return end
	if ply == LocalPlayer() and not gfoxyface_debug_loopback:GetBool() then return end
	if ply == LocalPlayer() or gfoxyface_see_others:GetBool() then
		if not gfoxyface.last_seen[ply] then
			dbg("face tracking started by", ply:Name(), ply:SteamID())
		end
		gfoxyface.last_seen[ply] = CurTime()
	end
	if not gfoxyface.state_setup[ply] then
		local rt = RealTime()
		if not ply_warn_times[ply] or rt - ply_warn_times[ply] > 10 then
			ply_warn_times[ply] = rt
			dbg("no setup data for", ply)
		end
		return
	end
	local count = net.ReadUInt(8)
	local flexes = {} --TODO: reuse
	for i = 1, count do
		local name = net.ReadString()
		local val = net.ReadFloat()
		local id = gfoxyface.flex_id_by_name(ply, name)
		flexes[name] = { found = id ~= nil, val = val, id = id }
	end
	gfoxyface._flex_results[ply] = { time = CurTime(), ft = ft, flexes = flexes } --TODO: reuse
end

function gfoxyface.flex_id_by_name(ent, name)
	local count = ent:GetFlexNum()
	for i = 0, count - 1 do
		if ent:GetFlexName(i) == name then
			return i
		end
	end
end

function gfoxyface.update_animation(ply)
	if not ply or not ply:IsValid() or not ply.SetFlexWeight then return end
	local data = gfoxyface._flex_results[ply]
	if not data then return end
	if CurTime() - data.time > 1 then return end
	for name, info in pairs(data.flexes) do
		if info.id then
			ply:SetFlexWeight(info.id, info.val)
			ply:SetFlexScale(info.id, 2)
		end
	end
end

gfoxyface._last_setup_time = 0
gfoxyface._last_model_check = 0
gfoxyface._last_model = ""

function gfoxyface.get_localplayer_flex_names()
	local lp = LocalPlayer()
	if not lp or not lp:IsValid() then return {} end
	local count = lp:GetFlexNum()
	if not count or count == 0 then return {} end
	local t = {}
	for i = 0, count - 1 do
		local name = lp:GetFlexName(i)
		if name and name ~= "" then
			t[#t + 1] = name
		end
	end
	return t
end

gfoxyface.mapping = {
	["FT/v2/JawOpen"] = { targets = { ["jaw_drop"] = { 2 } } },
	["FT/v2/LipPucker"] = { targets = { ["left_puckerer"] = { 2 }, ["right_puckerer"] = { 2 } } },
	["FT/v2/LipFunnel"] = { targets = { ["left_funneler"] = { 2 }, ["right_funneler"] = { 2 } } },
	["FT/v2/MouthStretchLeft"] = { targets = { ["left_stretcher"] = { 2 } } },
	["FT/v2/MouthStretchRight"] = { targets = { ["right_stretcher"] = { 2 } } },
	["FT/v2/MouthClosed"] = { targets = { ["bite"] = { 2 } } },
	["FT/v2/MouthLowerDown"] = { targets = { ["lower_lip"] = { 2 } } },
	["FT/v2/MouthPress"] = { targets = { ["presser"] = { 2 } } },
	["FT/v2/MouthRaiserLower"] = { targets = { ["chin_raiser"] = { 2 } } },
	["FT/v2/MouthUpperUpLeft"] = { targets = { ["left_upper_raiser"] = { 2 } } },
	["FT/v2/MouthUpperUpRight"] = { targets = { ["right_upper_raiser"] = { 2 } } },
	["FT/v2/SmileFrownLeft"] = { targets = { ["left_corner_puller"] = { 2 } } },
	["FT/v2/SmileFrownRight"] = { targets = { ["right_corner_puller"] = { 2 } } },
	["FT/v2/CheekPuffSuckLeft"] = { targets = { ["left_cheek_raiser"] = { 2 } } },
	["FT/v2/CheekPuffSuckRight"] = { targets = { ["right_cheek_raiser"] = { 2 } } },
	["FT/v2/EyeLidLeft"] = { targets = { ["left_lid_closer"] = { 2 } } },
	["FT/v2/EyeLidRight"] = { targets = { ["right_lid_closer"] = { 2 } } },
	["FT/v2/EyeLeftX"] = { targets = { ["eyes_rightleft"] = { 2 } } },
	["FT/v2/EyeRightX"] = { targets = { ["eyes_rightleft"] = { 2 } } },
	["FT/v2/EyeY"] = { targets = { ["eyes_updown"] = { 2 } } },
	["FT/v2/EyeSquintLeft"] = { targets = { ["left_lid_tightener"] = { 2 } } },
	["FT/v2/EyeSquintRight"] = { targets = { ["right_lid_tightener"] = { 2 } } },
	["FT/v2/BrowExpressionLeft"] = { targets = { ["left_outer_raiser"] = { 2 } } },
	["FT/v2/BrowExpressionRight"] = { targets = { ["right_outer_raiser"] = { 2 } } },
	["FT/v2/NoseSneer"] = { targets = { ["wrinkler"] = { 2 } } },
	["FT/v2/MouthRaiserUpper"] = { targets = { ["smile"] = { 2 } } },
}

function gfoxyface.on_model_change() -- build state_setup[lp] from mapping + model flexes
	local flex_names = gfoxyface.get_localplayer_flex_names()
	local flex_set = {}
	for _, name in ipairs(flex_names) do
		flex_set[name] = true
	end

	local lp = LocalPlayer()
	if not lp or not lp:IsValid() then return end
	gfoxyface.state_setup[lp] = {}

	for vrcft_name, entry in pairs(gfoxyface.mapping or {}) do
		for flex_name, scale_info in pairs(entry.targets or {}) do
			if flex_set[flex_name] then
				local id = gfoxyface.flex_id_by_name(lp, flex_name)
				if id then
					gfoxyface.state_setup[lp][id] = {
						param = vrcft_name,
						flex_name = flex_name,
						scale = scale_info
					}
		end
	end
	if not next(gfoxyface.state_setup[lp] or {}) then
		dbg("no mapping targets found for this model")
		lp:ChatPrint("[GFoxyFace] no mapping targets found for " .. lp:GetModel())
	end
end
	end
end

function gfoxyface.think_modelcheck()
	if not gfoxyface.running then return end
	local rt = RealTime()
	if rt - gfoxyface._last_model_check < 1 then return end
	gfoxyface._last_model_check = rt
	local lp = LocalPlayer()
	if not lp or not lp:IsValid() then return end
	local model = lp:GetModel()
	if model == gfoxyface._last_model then return end
	gfoxyface._last_model = model
	gfoxyface.on_model_change()
end

function gfoxyface.think_setup()
	if not gfoxyface.running then return end
	local rt = RealTime()
	if rt - gfoxyface._last_setup_time < 5 then return end
	local lp = LocalPlayer()
	if not lp or not lp:IsValid() then return end
	local count = lp:GetFlexNum()
	if not count or count == 0 then return end
	local entries = {}
	for i = 0, count - 1 do
		local name = lp:GetFlexName(i)
		if name and name ~= "" then
			entries[#entries + 1] = { id = i, name = name }
		end
	end
	if #entries == 0 then return end
	gfoxyface._last_setup_time = rt
	gfoxyface.send_flex_setup(entries)
end

hook.Add("Think", Tag, function()
	gfoxyface.think_modelcheck()
	gfoxyface.think_setup()
end)

hook.Add("UpdateAnimation", Tag, gfoxyface.update_animation)

hook.Add("Tick", Tag, function()
	if not gfoxyface.running then return end
	local rt = RealTime()

	local has_updates = false
	for _, last_upd in pairs(gfoxyface.state_last_updated) do
		if last_upd > last_realtime then
			has_updates = true
			break
		end
	end
	if not has_updates then return end

	local ft = rt - last_realtime
	last_realtime = rt
	if ft <= 0 or ft > 1 then ft = 0 end

	local lp = LocalPlayer()
	local flexes = {}
	local setup = lp and lp:IsValid() and gfoxyface.state_setup[lp]
	if setup then
		for flex_id, info in pairs(setup) do
			local val = gfoxyface.state[info.param]
			if val ~= nil and type(val) == "number" then
				local scale = info.scale
				local scaled_val = val
				if type(scale) == "number" then
					scaled_val = val * scale
				end
				flexes[#flexes + 1] = { name = info.flex_name, val = scaled_val }
			end
		end
	end

	local ok, err = pcall(net.Start, Tag, true)
	if not ok then return end

	net.WriteUInt(1, 4)
	net.WriteFloat(ft)
	net.WriteUInt(#flexes, 8)
	for _, f in ipairs(flexes) do
		net.WriteString(f.name)
		net.WriteFloat(f.val)
	end
	net.SendToServer()
end)

concommand.Add("gfoxyface_start", function()
	if gfoxyface.running then
		dbg("already running")
		return
	end
	gfoxyface.start()
end)

concommand.Add("gfoxyface_request_tracking_vrcft", function()
	gfoxyface.request_tracking()
end)

concommand.Add("gfoxyface_stop", function()
	if not gfoxyface.running then return end
	gfoxyface.stop_listener()
end)

function gfoxyface.status()
	local lp = LocalPlayer()
	local c_h = Color(255, 255, 200)
	local c_g = Color(100, 255, 100)
	local c_r = Color(255, 100, 100)
	local c_w = Color(255, 255, 255)
	MsgC(c_h, "--- GFoxyFace Status ---\n")
	MsgC(gfoxyface.running and c_g or c_r, "running: " .. tostring(gfoxyface.running) .. "\n")
	MsgC(c_w, "state keys: " .. tostring(table.Count(gfoxyface.state)) .. "\n")
	if lp and lp:IsValid() then
		local setup = gfoxyface.state_setup[lp]
		if setup then
			local n = 0
			for _, info in pairs(setup) do
				if type(info) == "table" then
					n = n + 1
				end
			end
			MsgC(c_w, "model mappings: " .. n .. "\n")
			if n == 0 then
				MsgC(c_r, "  no mapping targets matched this model\n")
				MsgC(c_h, "  model flexes:\n")
				for _, name in ipairs(gfoxyface.get_localplayer_flex_names()) do
					MsgC(c_w, "    " .. name .. "\n")
				end
				MsgC(c_h, "  received state keys:\n")
				for key, _ in pairs(gfoxyface.state) do
					MsgC(c_w, "    " .. key .. "\n")
				end
			else
				for id, info in pairs(setup) do
					if type(info) == "table" then
						MsgC(c_g, "  ")
						MsgC(c_w, info.param .. " -> " .. info.flex_name .. " (id " .. id .. ")\n")
					end
				end
			end
		else
			MsgC(c_r, "model mappings: none (on_model_change not run)\n")
		end
		MsgC(c_w, "model: " .. lp:GetModel() .. "\n")
	else
		MsgC(c_r, "no local player\n")
	end
	MsgC(c_h, "-----------------------\n")
end

concommand.Add("gfoxyface_status", function()
	gfoxyface.status()
end)

hook.Add("HUDPaint", "gfoxyface_debug_ui", function()
	if not gfoxyface_debug_ui:GetBool() then return end
	local now = RealTime()
	local y = 10
	local bar_x, bar_w = 200, 200
	local half_w = bar_w / 2
	local center_x = bar_x + half_w
	local lp = LocalPlayer()
	local active_params = {}
	if lp and lp:IsValid() then
		local setup = gfoxyface.state_setup[lp]
		if setup then
			for _, info in pairs(setup) do
				if type(info) == "table" then
					active_params[info.param] = true
				end
			end
		end
	end
	local keys = table.GetKeys(gfoxyface.state)
	table.sort(keys)
	for _, key in ipairs(keys) do
		local value = gfoxyface.state[key]
		local last = gfoxyface.state_last_updated[key]
		if last and now - last <= 5 then
			if active_params[key] then
				surface.SetDrawColor(50, 200, 50, 220)
				surface.DrawRect(2, y + 2, 6, 14)
			end
			draw.DrawText(key, "DermaDefault", 10, y, Color(255, 255, 255), TEXT_ALIGN_LEFT)
			if type(value) == "number" then
				local clamped = math.Clamp(value, -1, 1)
				local val_x = center_x + clamped * half_w
				surface.SetDrawColor(50, 50, 50, 200)
				surface.DrawRect(bar_x, y + 4, bar_w, 10)
				surface.SetDrawColor(173, 216, 230, 220)
				if clamped >= 0 then
					surface.DrawRect(center_x, y + 4, val_x - center_x, 10)
				else
					surface.DrawRect(val_x, y + 4, center_x - val_x, 10)
				end
				draw.DrawText(string.format("%.3f", value), "DermaDefault", bar_x + bar_w + 5, y, Color(255, 255, 255),
					TEXT_ALIGN_LEFT)
			else
				draw.DrawText(tostring(value), "DermaDefault", bar_x, y, Color(200, 200, 200), TEXT_ALIGN_LEFT)
			end
			y = y + 22
		end
	end
end)

hook.Add("PostPlayerDraw", "gfoxyface_debug_ui_3d", function(ply)
	if not gfoxyface_debug_ui_3d:GetBool() then return end
	if ply == LocalPlayer() then return end
	local results = gfoxyface._flex_results[ply]
	if not results then return end
	local age = CurTime() - results.time
	if age > 5 then return end

	local pos = ply:GetPos() + Vector(0, 0, 80)
	local ang = Angle(0, (EyePos() - pos):Angle().yaw + 90, 90)

	cam.Start3D2D(pos, ang, 0.1)
		draw.DrawText(string.format("ft: %.3f", results.ft), "DermaDefault", 0, 0, Color(255, 255, 255), TEXT_ALIGN_LEFT)
		local y = 14
		for name, info in pairs(results.flexes) do
			local col = info.found and Color(0, 220, 0) or Color(220, 0, 0)
			draw.DrawText((info.found and "✓ " or "✗ ") .. name, "DermaDefault", 0, y, col, TEXT_ALIGN_LEFT)
			local clamped = math.Clamp(info.val, -1, 1)
			local bw, bh = 60, 8
			local cx = 140
			local hw = bw / 2
			surface.SetDrawColor(40, 40, 40, 200)
			surface.DrawRect(cx - hw, y + 3, bw, bh)
			surface.SetDrawColor(info.found and Color(0, 220, 0, 200) or Color(220, 0, 0, 200))
			if clamped >= 0 then
				surface.DrawRect(cx, y + 3, clamped * hw, bh)
			else
				surface.DrawRect(cx + clamped * hw, y + 3, -clamped * hw, bh)
			end
			draw.DrawText(string.format("%.3f", info.val), "DermaDefault", 205, y, Color(255, 255, 255), TEXT_ALIGN_LEFT)
			y = y + 16
		end
	cam.End3D2D()
end)
