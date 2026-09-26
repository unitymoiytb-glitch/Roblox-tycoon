"""Build the Roblox place file (.rbxlx) from src/ and validate it.

    python3 tools/build_rbxlx.py builds/Survive_India_Tycoon_V26_POLISHED_START.rbxlx

* Every Lua source is XML-escaped with xml.sax.saxutils.escape before it is written into
  its <ProtectedString name="Source">.
* After writing, the file is parsed with xml.etree.ElementTree and every script source is
  extracted again and compared byte-for-byte with the file in src/. Any mismatch aborts.

Script layout follows Rojo conventions:
    Foo.lua          -> ModuleScript "Foo"
    Foo.server.lua   -> Script "Foo"
    Foo.client.lua   -> LocalScript "Foo"
    Foo/init.server.lua (+ siblings) -> Script "Foo" with child ModuleScripts
"""
import os
import re
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")


class Ref:
    n = 0

    @classmethod
    def next(cls):
        cls.n += 1
        return f"RBX{cls.n:08X}"


def read(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    bad = [c for c in text if ord(c) < 32 and c not in "\t\n\r"]
    if bad:
        raise SystemExit(f"{path}: contains control characters that XML 1.0 cannot store: {set(bad)!r}")
    return text


def config_number(name):
    cfg = read(os.path.join(SRC, "ReplicatedStorage/Shared/Config.lua"))
    m = re.search(rf"\b{name}\s*=\s*(-?[0-9.]+)", cfg)
    if not m:
        raise SystemExit(f"Config.World.{name} not found")
    return float(m.group(1))


def item(cls, name, props="", children="", indent=2):
    pad = "  " * indent
    out = [f'{pad}<Item class="{cls}" referent="{Ref.next()}">', f"{pad}  <Properties>",
           f'{pad}    <string name="Name">{escape(name)}</string>']
    if props:
        out.append(props)
    out.append(f"{pad}  </Properties>")
    if children:
        out.append(children)
    out.append(f"{pad}</Item>")
    return "\n".join(out)


def script_item(cls, name, source_path, children="", indent=2):
    pad = "  " * (indent + 2)
    source = read(source_path)
    props = []
    if cls in ("Script", "LocalScript"):
        props.append(f'{pad}<bool name="Disabled">false</bool>')
    props.append(f'{pad}<ProtectedString name="Source">{escape(source)}</ProtectedString>')
    return item(cls, name, "\n".join(props), children, indent)


def classify(filename):
    if filename.endswith(".server.lua"):
        return "Script", filename[: -len(".server.lua")]
    if filename.endswith(".client.lua"):
        return "LocalScript", filename[: -len(".client.lua")]
    if filename.endswith(".lua"):
        return "ModuleScript", filename[: -len(".lua")]
    return None, None


def folder_children(path, indent):
    """Items for every script / subfolder inside `path` (sorted for stable output)."""
    out = []
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            init = [f for f in os.listdir(full) if f.startswith("init.")]
            if init:
                cls, _ = classify(init[0])
                kids = "\n".join(
                    script_item(*classify(f), os.path.join(full, f), indent=indent + 1)
                    for f in sorted(os.listdir(full)) if not f.startswith("init.") and classify(f)[0])
                out.append(script_item(cls, entry, os.path.join(full, init[0]), kids, indent))
            else:
                out.append(item("Folder", entry, "", folder_children(full, indent + 1), indent))
        else:
            cls, name = classify(entry)
            if cls:
                out.append(script_item(cls, name, full, indent=indent))
    return "\n".join(out)


def cframe_xml(name, x, y, z, rot, pad):
    r = rot
    return (f'{pad}<CoordinateFrame name="{name}">\n'
            f"{pad}  <X>{x}</X>\n{pad}  <Y>{y}</Y>\n{pad}  <Z>{z}</Z>\n"
            f"{pad}  <R00>{r[0]}</R00>\n{pad}  <R01>{r[1]}</R01>\n{pad}  <R02>{r[2]}</R02>\n"
            f"{pad}  <R10>{r[3]}</R10>\n{pad}  <R11>{r[4]}</R11>\n{pad}  <R12>{r[5]}</R12>\n"
            f"{pad}  <R20>{r[6]}</R20>\n{pad}  <R21>{r[7]}</R21>\n{pad}  <R22>{r[8]}</R22>\n"
            f"{pad}</CoordinateFrame>")


def build(out_path):
    Ref.n = 0
    zone1 = -400.0
    spawn_x = zone1 + config_number("HomeBackX") + config_number("HomeSpawnBack")
    spawn_z = config_number("HomeSpawnZ")
    pad = "        "
    # SpawnLocation inside the starter room, looking +X (toward the open front).
    # Rotation rows for LookVector (1,0,0): Right=(0,0,1), Up=(0,1,0), Back=(-1,0,0).
    spawn_props = "\n".join([
        f'{pad}<bool name="Anchored">true</bool>',
        f'{pad}<bool name="CanCollide">false</bool>',
        f'{pad}<bool name="CanQuery">false</bool>',
        cframe_xml("CFrame", spawn_x, 0.95, spawn_z, [0, 0, -1, 0, 1, 0, 1, 0, 0], pad),
        f'{pad}<Vector3 name="Size">\n{pad}  <X>4</X>\n{pad}  <Y>0.2</Y>\n{pad}  <Z>4</Z>\n{pad}</Vector3>',
        f'{pad}<float name="Transparency">1</float>',
        f'{pad}<bool name="Neutral">true</bool>',
        f'{pad}<int name="Duration">0</int>',
    ])
    workspace = item("Workspace", "Workspace", "", item("SpawnLocation", "SpawnLocation", spawn_props, indent=2), indent=1)
    # Lighting.Technology cannot be set from a script; Future gives the starter-room bulb real shadows.
    lighting = item("Lighting", "Lighting", "\n".join([
        '      <token name="Technology">4</token>',
        '      <float name="ClockTime">16.8</float>',
        '      <float name="Brightness">2.35</float>',
    ]), indent=1)
    rs = item("ReplicatedStorage", "ReplicatedStorage", "", folder_children(os.path.join(SRC, "ReplicatedStorage"), 2), indent=1)
    sss = item("ServerScriptService", "ServerScriptService", "", folder_children(os.path.join(SRC, "ServerScriptService"), 2), indent=1)
    sps = item("StarterPlayerScripts", "StarterPlayerScripts", "",
               folder_children(os.path.join(SRC, "StarterPlayer/StarterPlayerScripts"), 3), indent=2)
    sp = item("StarterPlayer", "StarterPlayer", "", sps, indent=1)
    doc = "\n".join([
        "<?xml version='1.0' encoding='utf-8'?>",
        '<roblox xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">',
        "  <External>null</External>",
        "  <External>nil</External>",
        workspace, lighting, rs, sss, sp,
        "</roblox>", ""])
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(doc)
    return out_path


def expected_scripts():
    """(class, dotted path) -> source, for every script under src/."""
    exp = {}
    service_of = {"ReplicatedStorage": "ReplicatedStorage", "ServerScriptService": "ServerScriptService",
                  "StarterPlayer": "StarterPlayer"}
    for dirpath, _, files in os.walk(SRC):
        rel = os.path.relpath(dirpath, SRC).split(os.sep)
        if rel[0] not in service_of:
            continue
        for f in files:
            cls, name = classify(f)
            if not cls:
                continue
            if f.startswith("init."):
                path = rel
            else:
                path = rel + [name]
            exp[(cls, "/".join(path))] = read(os.path.join(dirpath, f))
    return exp


def validate(out_path):
    tree = ET.parse(out_path)  # raises on malformed XML
    root = tree.getroot()
    found = {}
    refs = set()

    def walk(node, path):
        for it in node.findall("Item"):
            ref = it.get("referent")
            if ref in refs:
                raise SystemExit(f"duplicate referent {ref}")
            refs.add(ref)
            props = it.find("Properties")
            name = props.find("string[@name='Name']").text
            p = path + [name]
            src = props.find("ProtectedString[@name='Source']")
            if src is not None:
                found[(it.get("class"), "/".join(p))] = src.text or ""
            walk(it, p)

    walk(root, [])
    exp = expected_scripts()
    missing = set(exp) - set(found)
    extra = set(found) - set(exp)
    if missing or extra:
        raise SystemExit(f"script set mismatch: missing={missing} extra={extra}")
    for key, text in exp.items():
        if found[key] != text:
            raise SystemExit(f"source round-trip mismatch for {key}")
    classes = [it.get("class") for it in root.iter("Item")]
    return found, classes


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "builds/Survive_India_Tycoon_V26_POLISHED_START.rbxlx")
    build(out)
    found, classes = validate(out)
    print(f"built {out} ({os.path.getsize(out)} bytes)")
    print(f"XML parses OK; {len(found)} scripts round-trip byte-for-byte:")
    for (cls, path), text in sorted(found.items(), key=lambda kv: kv[0][1]):
        print(f"  {cls:12s} {path}  ({len(text.splitlines())} lines)")
    print("instances:", {c: classes.count(c) for c in sorted(set(classes))})


if __name__ == "__main__":
    main()
