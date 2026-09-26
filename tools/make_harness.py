"""Bundle the game's Luau sources with the Roblox mock into one runnable Luau program.

Usage: python3 tools/make_harness.py <test.lua> <out.lua>

The generated program defines `SIT.mount()` which creates the ReplicatedStorage /
ServerScriptService / StarterPlayerScripts trees with ModuleScripts whose `require`
runs the real source, plus `SIT.runServer()` / `SIT.runClient(name)` to execute scripts.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def fn(name, body):
    # Every script/module body becomes a function taking `script` as a local.
    return f"SIT.src[{name!r}] = function(script)\nlocal os = SIT.os\n{body}\nend\n"


def main():
    test_path, out_path = sys.argv[1], sys.argv[2]
    parts = ["local SIT = {src = {}}\nlocal realOs = os\nSIT.os = setmetatable({clock = function() return SIT.clock and SIT.clock() or realOs.clock() end}, {__index = realOs})\n"]
    parts.append("local mock = (function()\n" + read(os.path.join(ROOT, "tools/mock/roblox_mock.lua")) + "\nend)()\n")
    parts.append(fn("Config", read(os.path.join(SRC, "ReplicatedStorage/Shared/Config.lua"))))
    parts.append(fn("VehicleFactory", read(os.path.join(SRC, "ReplicatedStorage/Shared/VehicleFactory.lua"))))
    parts.append(fn("TrafficSim", read(os.path.join(SRC, "ReplicatedStorage/Shared/TrafficSim.lua"))))
    parts.append(fn("WorldBuilder", read(os.path.join(SRC, "ServerScriptService/Main/WorldBuilder.lua"))))
    parts.append(fn("TrafficServer", read(os.path.join(SRC, "ServerScriptService/Main/TrafficServer.lua"))))
    parts.append(fn("Main", read(os.path.join(SRC, "ServerScriptService/Main/init.server.lua"))))
    parts.append(fn("Client", read(os.path.join(SRC, "StarterPlayer/StarterPlayerScripts/Client.client.lua"))))
    parts.append(fn("TrafficClient", read(os.path.join(SRC, "StarterPlayer/StarterPlayerScripts/TrafficClient.client.lua"))))
    parts.append(r'''
local moduleCache = {}
function require(inst)
    local key = inst and inst.__props and inst.__props.__module
    assert(key, "require() on something that is not a mounted ModuleScript")
    if moduleCache[key] == nil then moduleCache[key] = SIT.src[key](inst) end
    return moduleCache[key]
end
local function module(parent, name)
    local m = Instance.new("ModuleScript") m.Name = name m.__props.__module = name m.Parent = parent return m
end
function SIT.mount()
    local RS = game:GetService("ReplicatedStorage")
    local shared = Instance.new("Folder") shared.Name = "Shared" shared.Parent = RS
    module(shared, "Config") module(shared, "VehicleFactory") module(shared, "TrafficSim")
    local SSS = game:GetService("ServerScriptService")
    local main = Instance.new("Script") main.Name = "Main" main.Parent = SSS
    module(main, "WorldBuilder") module(main, "TrafficServer")
    SIT.mainScript = main
end
function SIT.runServer() SIT.src.Main(SIT.mainScript) end
function SIT.runClient(name) local s = Instance.new("LocalScript") s.Name = name SIT.src[name](s) end
SIT.mock = mock
''')
    parts.append("\n-- ===================== TEST =====================\n")
    parts.append(read(test_path))
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))


if __name__ == "__main__":
    main()
