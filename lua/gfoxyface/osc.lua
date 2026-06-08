local socket = _G.socket
local bit_band, bit_bor, bit_lshift, bit_rshift, bit_tobit = bit.band, bit.bor, bit.lshift, bit.rshift, bit.tobit
local math_ldexp = math.ldexp

local function read_i4(data, pos)
  local a, b, c, d = data:byte(pos, pos + 3)
  local v = bit_bor(bit_lshift(a, 24), bit_lshift(b, 16), bit_lshift(c, 8), d)
  return bit_tobit(v), pos + 4
end

local function read_f4(data, pos)
  local int, pos = read_i4(data, pos)
  local sign = bit_rshift(bit_band(int, 0x80000000), 31)
  local exponent = bit_rshift(bit_band(int, 0x7F800000), 23)
  local mantissa = bit_band(int, 0x007FFFFF)
  if exponent == 0 then
    if mantissa == 0 then return sign == 0 and 0.0 or -0.0, pos end
    return (sign == 0 and 1 or -1) * math_ldexp(mantissa / 0x800000, -126), pos
  elseif exponent == 255 then
    if mantissa == 0 then return sign == 0 and math.huge or -math.huge, pos end
    return 0.0 / 0.0, pos
  end
  return (sign == 0 and 1 or -1) * math_ldexp(1 + mantissa / 0x800000, exponent - 127), pos
end

local function read_string(data, pos)
  local end_pos = data:find("\0", pos)
  if not end_pos then return nil, pos end
  local str = data:sub(pos, end_pos - 1)
  local new_pos = end_pos + 1
  local pad = (4 - (new_pos - pos) % 4) % 4
  return str, new_pos + pad
end

local function read_blob(data, pos)
  local size, pos = read_i4(data, pos)
  local blob = data:sub(pos, pos + size - 1)
  local new_pos = pos + size
  local pad = (4 - size % 4) % 4
  return blob, new_pos + pad
end

local function parse_osc(data)
  local pos = 1
  local address, pos = read_string(data, pos)
  if not address then return end
  if address == "#bundle" then
    pos = 17
    local messages = {}
    while pos <= #data do
      local size, new_pos = read_i4(data, pos)
      if not size then break end
      pos = new_pos
      if pos + size <= #data + 1 then
        local msg = parse_osc(data:sub(pos, pos + size - 1))
        if msg then table.insert(messages, msg) end
        pos = pos + size
      end
    end
    return {address = address, args = messages}
  end
  local type_tags, pos = read_string(data, pos)
  if not type_tags or type_tags:sub(1, 1) ~= "," then
    return {address = address, args = {}}
  end
  local args = {}
  for i = 2, #type_tags do
    local tag = type_tags:sub(i, i)
    if tag == "i" then
      local val, new_pos = read_i4(data, pos)
      pos = new_pos
      table.insert(args, val)
    elseif tag == "f" then
      local val, new_pos = read_f4(data, pos)
      pos = new_pos
      table.insert(args, val)
    elseif tag == "s" then
      local val, new_pos = read_string(data, pos)
      pos = new_pos
      table.insert(args, val)
    elseif tag == "b" then
      local val, new_pos = read_blob(data, pos)
      pos = new_pos
      table.insert(args, val)
    elseif tag == "h" then
      local hi, new_pos = read_i4(data, pos)
      pos = new_pos
      local lo, new_pos = read_i4(data, pos)
      pos = new_pos
      table.insert(args, {hi = hi, lo = lo})
    elseif tag == "d" then
      local hi, new_pos = read_i4(data, pos)
      pos = new_pos
      local lo, new_pos = read_i4(data, pos)
      pos = new_pos
      table.insert(args, {hi = hi, lo = lo})
    elseif tag == "t" then
      local hi, new_pos = read_i4(data, pos)
      pos = new_pos
      local lo, new_pos = read_i4(data, pos)
      pos = new_pos
      table.insert(args, {secs = hi, frac = lo})
    elseif tag == "T" then
      table.insert(args, true)
    elseif tag == "F" then
      table.insert(args, false)
    elseif tag == "N" then
      table.insert(args, nil)
    elseif tag == "I" then
      table.insert(args, math.huge)
    end
  end
  return {address = address, args = args}
end

local PORT = 9000
local STATE_KEY = "gf_osc"

local function state()
  local s = rawget(_G, STATE_KEY)
  if not s then
    s = {}
    rawset(_G, STATE_KEY, s)
  end
  return s
end

local function osc_on_receive(data, ip, port)
  local ok, msg = pcall(parse_osc, data)
  if not ok or not msg then return end
  hook.Run("OSCMessage", msg.address, msg.args, ip, port)
  hook.Run("OSC_" .. msg.address:gsub("/", "_"), msg.args, ip, port)
end

local function stop()
  local s = state()
  timer.Remove("OSCReceiver")
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
        if ip ~= "timeout" then
          print("OSC receive error:", ip)
        end
        return
      end
      osc_on_receive(data, ip, port)
    end
  end
end

local function start()
  stop()
  local s = state()
  local sock = socket.udp()
  sock:settimeout(0)
  for attempt = 1, 3 do
    local ok, err = sock:setsockname("0.0.0.0", PORT)
    if ok then break end
    if attempt < 3 then
      collectgarbage()
      sock:close()
      sock = socket.udp()
      sock:settimeout(0)
    else
      print("OSC: failed to bind port " .. PORT .. " (" .. tostring(err) .. ")")
      print("OSC: check if another program (nc, VRChat, etc.) is using it")
      sock:close()
      return
    end
  end
  timer.Create("OSCReceiver", 0.01, 0, poll(sock))
  s.sock = sock
  print("OSC: listening on port " .. PORT)
end

concommand.Add("osc_start", function() start() end)
concommand.Add("osc_stop", function() stop() end)
concommand.Add("osc_restart", function() stop() start() end)

start()
