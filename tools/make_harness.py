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
    shared_dir = os.path.join(SRC, "ReplicatedStorage/Shared")
    main_dir = os.path.join(SRC, "ServerScriptService/Main")
    client_dir = os.path.join(SRC, "StarterPlayer/StarterPlayerScripts")
    shared = sorted(f[:-4] for f in os.listdir(shared_dir) if f.endswith(".lua"))
    mains = sorted(f[:-4] for f in os.listdir(main_dir) if f.endswith(".lua") and not f.startswith("init."))
    for name in shared:
        parts.append(fn(name, read(os.path.join(shared_dir, name + ".lua"))))
    for name in mains:
        parts.append(fn(name, read(os.path.join(main_dir, name + ".lua"))))
    parts.append(fn("Main", read(os.path.join(main_dir, "init.server.lua"))))
    for f in sorted(os.listdir(client_dir)):
        if f.endswith(".client.lua"):
            parts.append(fn(f[:-len(".client.lua")], read(os.path.join(client_dir, f))))
    parts.append("SIT.sharedModules = {" + ", ".join(repr(n) for n in shared) + "}\n")
    parts.append("SIT.mainModules = {" + ", ".join(repr(n) for n in mains) + "}\n")
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
    for _, n in ipairs(SIT.sharedModules) do module(shared, n) end
    local SSS = game:GetService("ServerScriptService")
    local main = Instance.new("Script") main.Name = "Main" main.Parent = SSS
    for _, n in ipairs(SIT.mainModules) do module(main, n) end
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
