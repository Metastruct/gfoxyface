# GFoxyFace

Garry's Mod ↔ VRCFaceTracking bridge using OSC over UDP.

> **⚠ WIP — Work in Progress.** Everything is subject to change. Use at your own risk.

## Prerequisites

1. **[VRCFaceTracking](https://store.steampowered.com/app/3329480/VRCFaceTracking/)** — Install from Steam. This receives data from your face-tracking hardware and forwards it as OSC.
2. **[FoxyFace](https://foxyface.jeka8833.pp.ua/docs/FoxyFace/install-update-uninstall/install/Install-FoxyFace/)** — Install and configure FoxyFace so it can relay tracking data to other applications.
3. **Garry's Mod luasocket** — Already bundled with GMod (`lua/bin/gmcl_socket.core_win64.dll` + `lua/includes/modules/luasocket.lua`). No separate install needed.

## Install

Copy the `lua/gfoxyface/` folder into your Garry's Mod `garrysmod/` directory so the full path is:

```
garrysmod/lua/gfoxyface/
```

On the client, run:

```
lua_openscript_cl gfoxyface/main.lua
```

## Usage

| ConVar | Default | Description |
|--------|---------|-------------|
| `gfoxyface_autoenable` | 1 | Auto-start OSC listener on load |
| `gfoxyface_listen_port` | 9000 | UDP port to receive VRChat OSC |
| `gfoxyface_send_port` | 9001 | UDP port to send OSC to VRChat |
| `gfoxyface_debug_ui` | 0 | Show real-time parameter overlay |
| `gfoxyface_see_others` | 1 | Receive forwarded data from other players |

| Command | Description |
|---------|-------------|
| `gfoxyface_start` | Start the OSC listener |
| `gfoxyface_stop` | Stop the OSC listener |

## How it works

```
VRCFT / FoxyFace  ──OSC──>  GMod (port 9000)
                                   │
                            gfoxyface.state
                                   │
                           net message ──> Server ──> Other Clients
                                   │
                            OSC ──> VRChat (port 9001)
```
