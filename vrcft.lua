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

local callback
local STATE_KEY = "gf_vrcft"
local cfg = { send_host = "127.0.0.1", send_port = 9001, listen_port = 9000 }

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

local function stop()
  local s = state()
  timer.Remove("VRCFT_Receiver")
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
          print("vrcft receive error:", ip)
        end
        return
      end
      on_receive(data, ip, port)
    end
  end
end

local function start()
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
      print("vrcft: failed to bind port " .. cfg.listen_port .. " (" .. tostring(err) .. ")")
      sock:close()
      return
    end
  end
  timer.Create("VRCFT_Receiver", 0.01, 0, poll(sock))
  s.sock = sock
  print("vrcft: listening on port " .. cfg.listen_port)
end

local function listen(cb)
  callback = cb
  start()
end

-- OSC sender

local function pad4(s)
  return s .. string.rep("\0", (4 - #s % 4) % 4)
end

local function pack_int32(n)
  n = math.floor(n)
  local b0 = bit_band(bit_rshift(n, 24), 0xFF)
  local b1 = bit_band(bit_rshift(n, 16), 0xFF)
  local b2 = bit_band(bit_rshift(n, 8), 0xFF)
  local b3 = bit_band(n, 0xFF)
  return string.char(b0, b1, b2, b3)
end

local function pack_float32(n)
  if n ~= n then
    return string.char(0x7F, 0xC0, 0x00, 0x00)
  end
  if n == math.huge then
    return string.char(0x7F, 0x80, 0x00, 0x00)
  end
  if n == -math.huge then
    return string.char(0xFF, 0x80, 0x00, 0x00)
  end
  local sign = 0
  if n < 0 then
    sign = 1
    n = -n
  end
  if n == 0 then
    return sign == 0
      and string.char(0x00, 0x00, 0x00, 0x00)
      or string.char(0x80, 0x00, 0x00, 0x00)
  end
  local e = 0
  local m = n
  while m >= 2 do m = m / 2; e = e + 1 end
  while m < 1 do m = m * 2; e = e - 1 end
  local biased = e + 127
  local frac = m - 1
  local mantissa_bits = 0
  for _ = 1, 23 do
    mantissa_bits = bit_lshift(mantissa_bits, 1)
    frac = frac * 2
    if frac >= 1 then
      mantissa_bits = bit_bor(mantissa_bits, 1)
      frac = frac - 1
    end
  end
  local packed = bit_bor(bit_bor(bit_lshift(sign, 31), bit_lshift(biased, 23)), mantissa_bits)
  return string.char(
    bit_band(bit_rshift(packed, 24), 0xFF),
    bit_band(bit_rshift(packed, 16), 0xFF),
    bit_band(bit_rshift(packed, 8), 0xFF),
    bit_band(packed, 0xFF)
  )
end

local function build_osc_message(address, ...)
  local args = {...}
  local type_tags = ","
  local arg_data = {}
  for _, v in ipairs(args) do
    local t = type(v)
    if t == "string" then
      type_tags = type_tags .. "s"
      table.insert(arg_data, pad4(v))
    elseif t == "number" then
      if v == math.floor(v) and v >= -0x80000000 and v <= 0x7FFFFFFF then
        type_tags = type_tags .. "i"
        table.insert(arg_data, pack_int32(v))
      else
        type_tags = type_tags .. "f"
        table.insert(arg_data, pack_float32(v))
      end
    elseif t == "boolean" then
      type_tags = type_tags .. (v and "T" or "F")
    end
  end
  local data = pad4(address) .. pad4(type_tags)
  for _, d in ipairs(arg_data) do
    data = data .. d
  end
  return data
end

local function setup(opts)
  if type(opts) == "table" then
    for k, v in pairs(opts) do
      cfg[k] = v
    end
  end
end

local function send(address, ...)
  local s = state().sock_send
  if not s then
    s = socket.udp()
    state().sock_send = s
  end
  local data = build_osc_message(address, ...)
  local ok, err = s:sendto(data, cfg.send_host, cfg.send_port)
  if not ok then
    print("vrcft send error:", err)
  end
end

local mod = { listen = listen, start = start, stop = stop, send = send, setup = setup }
_G.vrcft = mod
return mod
