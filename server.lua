local gfoxyface = gfoxyface
local dbg = gfoxyface.dbg
local Tag = gfoxyface.Tag

--- @type table<Player, number>
gfoxyface.last_seen = gfoxyface.last_seen or {}

local warned_tick_dedup = false
local now = CurTime()
hook.Add("Tick",Tag,function()
    now = CurTime()
end)

function gfoxyface.rebroadcast(ply,ft)
    net.Start(Tag, true)
    net.WritePlayer(ply)
    net.WriteFloat(ft)
    net.SendPVS(ply )
end
function gfoxyface.on_net(len, ply)
  local ft = net.ReadFloat()
  local last = gfoxyface.last_seen[ply]
  if last and now == last then
    if not warned_tick_dedup then
      warned_tick_dedup = true
      dbg("DEBUG HMM: tick dedup (same-tick messages dropped):", ply)
    end
    return
  end
  if not last then
    dbg("face tracking started by", ply:Name(), ply:SteamID())
  end
  gfoxyface.last_seen[ply] = now
  gfoxyface.rebroadcast(ply,ft)
end
