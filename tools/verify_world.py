"""Geometric verification of the generated world (reads the dump from tools/tests/world_dump.lua).

Flood-fills the walkable area of every district on a 0.25-stud grid with a character
radius of 0.45 studs (an R15 torso turned sideways is ~1 stud deep):

  A. GameplayBounds only, lanes open   -> player can never leave the designed corridor,
                                          and every drop / NPC is reachable
  B. GameplayBounds only, lanes lethal -> NO drop point and no part of the far side can be
                                          reached without entering the traffic lanes
  C. all collision, lanes lethal       -> the sidewalk barricades really close the sidewalks
  D. all collision                     -> the central exit path from the spawn is free
Plus height / count / structure checks. Exit code 1 on any failure.
"""
import math
import sys
from collections import deque

RES = 0.25
RADIUS = 0.45

# Must match Config.World
ZONES = [-400, -200, 0, 200, 400]
ROAD = 22.0
SIDE = 28.0
MEDIAN = 6.0
PEN = 110.0
ALLEY_HALF, ALLEY_BACK = 6.0, -42.0
HOME_BACK, HOME_HALF = -56.0, 9.0
SPAWN_BACK, SPAWN_Z = 5.5, -0.8
LANE_OFFSETS = [-18, -10, 10, 18]
LANE_WIDTH = 8
TRAFFIC_HALF = 175
DROP_Z = [-94, -58, -22, 24, 60, 94]

failures = []
notes = []


def check(cond, msg):
    (notes if cond else failures).append(("OK   " if cond else "FAIL ") + msg)


def load(path):
    parts, npcs, spawn = [], {}, None
    total = None
    for line in open(path, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if f[0] == "PART":
            pos = tuple(map(float, f[3].split(",")))
            rot = tuple(map(float, f[4].split(",")))
            size = tuple(map(float, f[5].split(",")))
            parts.append(dict(path=f[1], cls=f[2], pos=pos, rot=rot, size=size,
                              collide=f[6] == "true", query=f[7] == "true", touch=f[8] == "true",
                              transp=float(f[9]), shape=f[10]))
        elif f[0] == "NPC":
            npcs[f[1]] = tuple(map(float, f[2].split(",")))
        elif f[0] == "SPAWNLOC":
            spawn = (tuple(map(float, f[1].split(","))), tuple(map(float, f[2].split(","))))
        elif f[0].startswith("TOTALPARTS"):
            total = int(line.split()[1])
    return parts, npcs, spawn, total


def world_extent_y(p):
    """Vertical extent of an OBB."""
    r = p["rot"]
    hx, hy, hz = (s / 2 for s in p["size"])
    ey = abs(r[3]) * hx + abs(r[4]) * hy + abs(r[5]) * hz
    return p["pos"][1] - ey, p["pos"][1] + ey


def footprint_contains(p, x, z, grow):
    """Is world point (x, z) inside the XZ projection of the OBB grown by `grow`? (vertical axis ignored)"""
    r = p["rot"]
    dx, dz = x - p["pos"][0], z - p["pos"][2]
    hx, hy, hz = (s / 2 for s in p["size"])
    # local coords = R^T * d (ignoring y component of d: we test the whole vertical column)
    # For a column test, project the box onto the XZ plane: check along the box's two most
    # horizontal axes. Parts here are yaw-rotated or mildly tilted, so this is accurate enough.
    axes = [(r[0], r[6], hx), (r[1], r[7], hy), (r[2], r[8], hz)]
    # keep the two axes with the largest horizontal component
    axes.sort(key=lambda a: -(a[0] ** 2 + a[1] ** 2))
    for ax, az, h in axes[:2]:
        n = math.hypot(ax, az)
        if n < 1e-6:
            continue
        # half extent of the projected box along this horizontal direction
        ux, uz = ax / n, az / n
        ext = 0.0
        for bx, bz, bh in axes:
            ext += abs(bx * ux + bz * uz) * bh
        if abs(dx * ux + dz * uz) > ext + grow:
            return False
    return True


class Grid:
    def __init__(self, x0, x1, z0, z1):
        self.x0, self.z0 = x0, z0
        self.nx = int(round((x1 - x0) / RES)) + 1
        self.nz = int(round((z1 - z0) / RES)) + 1
        self.blocked = bytearray(self.nx * self.nz)

    def idx(self, x, z):
        i = int(round((x - self.x0) / RES))
        k = int(round((z - self.z0) / RES))
        if 0 <= i < self.nx and 0 <= k < self.nz:
            return k * self.nx + i
        return None

    def xz(self, idx):
        return self.x0 + (idx % self.nx) * RES, self.z0 + (idx // self.nx) * RES

    def mark_part(self, p, grow):
        r = p["rot"]
        hx, hy, hz = (s / 2 for s in p["size"])
        ex = abs(r[0]) * hx + abs(r[1]) * hy + abs(r[2]) * hz + grow
        ez = abs(r[6]) * hx + abs(r[7]) * hy + abs(r[8]) * hz + grow
        cx, cz = p["pos"][0], p["pos"][2]
        axis_aligned = abs(abs(r[0]) - 1) < 1e-6 and abs(abs(r[8]) - 1) < 1e-6
        i0 = max(0, int(math.floor((cx - ex - self.x0) / RES)))
        i1 = min(self.nx - 1, int(math.ceil((cx + ex - self.x0) / RES)))
        k0 = max(0, int(math.floor((cz - ez - self.z0) / RES)))
        k1 = min(self.nz - 1, int(math.ceil((cz + ez - self.z0) / RES)))
        for k in range(k0, k1 + 1):
            z = self.z0 + k * RES
            row = k * self.nx
            for i in range(i0, i1 + 1):
                x = self.x0 + i * RES
                if axis_aligned:
                    if abs(x - cx) <= ex and abs(z - cz) <= ez:
                        self.blocked[row + i] = 1
                elif footprint_contains(p, x, z, grow):
                    self.blocked[row + i] = 1

    def mark_rect(self, x0, x1, z0, z1):
        for k in range(self.nz):
            z = self.z0 + k * RES
            if z0 <= z <= z1:
                row = k * self.nx
                for i in range(self.nx):
                    x = self.x0 + i * RES
                    if x0 <= x <= x1:
                        self.blocked[row + i] = 1

    def fill(self, start):
        s = self.idx(*start)
        assert s is not None and not self.blocked[s], f"start {start} blocked or outside grid"
        seen = bytearray(self.nx * self.nz)
        seen[s] = 1
        q = deque([s])
        nx = self.nx
        n = len(seen)
        reach_edge = False
        while q:
            c = q.popleft()
            i = c % nx
            if i == 0 or i == nx - 1 or c < nx or c >= n - nx:
                reach_edge = True
            for d in (1, -1, nx, -nx):
                j = c + d
                if 0 <= j < n and not seen[j] and not self.blocked[j]:
                    if d == 1 and i == nx - 1:
                        continue
                    if d == -1 and i == 0:
                        continue
                    seen[j] = 1
                    q.append(j)
        return seen, reach_edge


def zone_of(p):
    for z, cx in enumerate(ZONES, 1):
        if f"Zone_{z}/" in p["path"]:
            return z
    return 0


def walkable_intended(lx, lz):
    if -SIDE <= lx <= SIDE and -PEN <= lz <= PEN:
        return True
    if ALLEY_BACK <= lx <= -SIDE and -ALLEY_HALF <= lz <= ALLEY_HALF:
        return True
    if HOME_BACK <= lx <= ALLEY_BACK and -HOME_HALF <= lz <= HOME_HALF:
        return True
    return False


def main(path):
    parts, npcs, spawnloc, total = load(path)
    check(total is not None and total == len(parts), f"dump complete ({len(parts)} parts in SIT_World)")

    # ---------------- structure / counts
    starter = [p for p in parts if "/StarterHome/" in p["path"]]
    homes = {p["path"].split("/StarterHome/")[0] for p in starter}
    check(len(homes) == 1 and "Zone_1" in next(iter(homes)), f"exactly one StarterHome model, in district 1 ({homes})")
    check(len(starter) <= 110, f"starter home is composed of {len(starter)} parts (budget 110)")
    shack_models = {p["path"].rsplit("/", 1)[0] for p in parts if "Zone_1/" in p["path"] and any(t in p["path"] for t in ("Shack/", "Stall/", "House/", "Office/", "Garage/", "Landmark/"))}
    check(8 <= len(shack_models) <= 22, f"district 1 row structures: {len(shack_models)}")
    for z in range(1, 6):
        zp = [p for p in parts if zone_of(p) == z]
        notes.append(f"INFO district {z}: {len(zp)} parts, {sum(p['collide'] for p in zp)} collidable, "
                     f"{sum(p['touch'] for p in zp)} CanTouch, {sum(0 < p['transp'] < 1 for p in zp)} semi-transparent")
    touch = [p for p in parts if p["touch"]]
    check(all("MuckPatch" in p["path"] for p in touch), f"only mud hazards have CanTouch ({len(touch)} parts)")
    lights = [p for p in parts if "Bulb" in p["path"] or "Embers" in p["path"]]
    notes.append(f"INFO light-bearing parts: {len(lights)}")

    bounds = [p for p in parts if "/GameplayBounds/" in p["path"]]
    check(all(p["transp"] == 1 and p["collide"] and not p["query"] and not p["touch"] for p in bounds),
          f"{len(bounds)} GameplayBounds parts are invisible, collidable, non-query, non-touch")
    check(all(world_extent_y(p)[1] >= 55 for p in bounds), "every bounds wall is at least 55 studs tall")
    in_pen_tops = [world_extent_y(p)[1] for p in parts if p["collide"] and "/GameplayBounds/" not in p["path"]
                   and zone_of(p) and -PEN <= p["pos"][2] <= PEN and "RoadTunnel" not in p["path"]]
    check(max(in_pen_tops) < 40, f"tallest climbable collidable inside a district tops at {max(in_pen_tops):.1f} (< 40)")

    # Spawn
    sp_pos, sp_look = spawnloc
    check(abs(sp_pos[0] - (ZONES[0] + HOME_BACK + SPAWN_BACK)) < 0.01 and abs(sp_look[0] - 1) < 1e-3,
          f"SpawnLocation inside the starter room facing +X (pos {sp_pos}, look {sp_look})")

    for z, cx in enumerate(ZONES, 1):
        zparts = [p for p in parts if zone_of(p) == z]
        zb = [p for p in zparts if "/GameplayBounds/" in p["path"]]
        solid = [p for p in zparts if p["collide"] and (lambda lo, hi: lo < 5.5 and hi > 1.6)(*world_extent_y(p))]
        start = (cx + HOME_BACK + SPAWN_BACK, SPAWN_Z)
        gx0, gx1, gz0, gz1 = cx - 70, cx + 50, -200, 200

        # A: bounds only, lanes open
        g = Grid(gx0, gx1, gz0, gz1)
        for p in zb:
            g.mark_part(p, RADIUS)
        seen, edge = g.fill(start)
        check(not edge, f"[D{z}] A: bounds-only fill never reaches the map edge")
        outside = 0
        reach_cells = 0
        for c in range(len(seen)):
            if seen[c]:
                reach_cells += 1
                x, zz = g.xz(c)
                if not walkable_intended(x - cx, zz):
                    outside += 1
        check(outside == 0, f"[D{z}] A: all {reach_cells} reachable cells lie inside the designed corridor ({outside} outside)")
        # intended region (shrunk by radius+res) must be reachable -> bounds do not cut the walkway
        missing = 0
        for c in range(len(seen)):
            x, zz = g.xz(c)
            lx = x - cx
            inner = walkable_intended(lx - RADIUS - RES, zz) and walkable_intended(lx + RADIUS + RES, zz) and \
                walkable_intended(lx, zz - RADIUS - RES) and walkable_intended(lx, zz + RADIUS + RES)
            if inner and not seen[c] and not g.blocked[c]:
                missing += 1
        check(missing == 0, f"[D{z}] A: whole designed corridor is connected ({missing} unreachable cells)")
        blockers = [p for p in zb if "SidewalkBlocker" in p["path"]]
        for i, dz in enumerate(DROP_Z, 1):
            dx = cx + ROAD + (SIDE - ROAD) / 2
            c = g.idx(dx, dz)
            check(c is not None and seen[c], f"[D{z}] A: drop {i} at z={dz} is reachable")

        # B: bounds only, lanes lethal
        gb = Grid(gx0, gx1, gz0, gz1)
        for p in zb:
            gb.mark_part(p, RADIUS)
        gb.mark_rect(cx - ROAD + RADIUS * 0, cx + ROAD, -PEN - 5, PEN + 5)
        seenb, _ = gb.fill(start)
        east = 0
        for c in range(len(seenb)):
            if seenb[c]:
                x, zz = gb.xz(c)
                if x > cx:
                    east += 1
        check(east == 0, f"[D{z}] B: without entering the lanes the far side is unreachable ({east} cells)")
        drop_near = 0
        for dz in DROP_Z:
            dx = cx + ROAD + (SIDE - ROAD) / 2
            for c in range(len(seenb)):
                if seenb[c]:
                    x, zz = gb.xz(c)
                    if (x - dx) ** 2 + (zz - dz) ** 2 < 9.5 ** 2:
                        drop_near += 1
                        break
        check(drop_near == 0, f"[D{z}] B: no drop point can be completed from the home side ({drop_near})")

        # C: all solid geometry, lanes lethal -> barricades close the sidewalk (district 1 only has them)
        gc = Grid(gx0, gx1, gz0, gz1)
        for p in zb + solid:
            gc.mark_part(p, RADIUS)
        gc.mark_rect(cx - ROAD, cx + ROAD, -PEN - 5, PEN + 5)
        seenc, _ = gc.fill(start)
        maxz = 0
        for c in range(len(seenc)):
            if seenc[c]:
                x, zz = gc.xz(c)
                if x - cx < -ROAD:
                    maxz = max(maxz, abs(zz))
        if blockers:
            check(maxz < 48, f"[D{z}] C: west sidewalk barricades stop sidewalk walking at |z|={maxz:.1f} (< 48)")
        else:
            notes.append(f"INFO [D{z}] C: no sidewalk barricades in this district (west sidewalk reach |z|={maxz:.1f})")

        # D: all solid geometry, lanes open -> spawn to street, and everything reachable
        gd = Grid(gx0, gx1, gz0, gz1)
        for p in zb + solid:
            gd.mark_part(p, RADIUS)
        seend, edge_d = gd.fill(start)
        check(not edge_d, f"[D{z}] D: full-collision fill stays inside the district")
        for i, dz in enumerate(DROP_Z, 1):
            dx = cx + ROAD + (SIDE - ROAD) / 2
            c = gd.idx(dx, dz)
            check(c is not None and seend[c], f"[D{z}] D: drop {i} reachable with all collision on")
        # Straight exit corridor from spawn to the sidewalk: 3 studs wide, no solid geometry at all.
        blockers_in_path = []
        for p in solid:
            lo, hi = world_extent_y(p)
            if hi <= 1.15:
                continue
            for xi in range(int((start[0]) * 4), int((cx - SIDE + 1) * 4)):
                x = xi / 4
                hit = False
                for zz in (SPAWN_Z - 1.5, SPAWN_Z, SPAWN_Z + 1.5):
                    if footprint_contains(p, x, zz, 0):
                        hit = True
                        break
                if hit:
                    blockers_in_path.append(p["path"])
                    break
        check(not blockers_in_path, f"[D{z}] D: central exit path spawn->street is free of collision ({blockers_in_path[:4]})")
        # NPC prompt reachability (MaxActivationDistance 13; require a reachable cell within 11)
        for name, pos in npcs.items():
            if not (cx - 110 < pos[0] < cx + 110):
                continue
            best = 1e9
            ci, ck = int((pos[0] - gd.x0) / RES), int((pos[2] - gd.z0) / RES)
            span = int(12 / RES)
            for k in range(max(0, ck - span), min(gd.nz, ck + span)):
                for i in range(max(0, ci - span), min(gd.nx, ci + span)):
                    c = k * gd.nx + i
                    if seend[c]:
                        x, zz = gd.xz(c)
                        best = min(best, math.hypot(x - pos[0], zz - pos[2]))
            check(best < 11, f"[D{z}] D: {name} can be talked to (closest reachable point {best:.1f} studs)")

        # E: visible geometry only (no invisible walls): where would the player get out?
        ge = Grid(gx0, gx1, gz0, gz1)
        for p in solid:
            if "/GameplayBounds/" not in p["path"]:
                ge.mark_part(p, RADIUS)
        seene, edge_e = ge.fill(start)
        mouths = other = 0
        for c in range(len(seene)):
            if seene[c]:
                x, zz = ge.xz(c)
                lx = x - cx
                if not walkable_intended(lx, zz):
                    if abs(zz) > PEN and abs(lx) < ROAD:
                        mouths += 1
                    elif not (SIDE < lx < SIDE + 4 and -84 < zz < -66):  # enclosed guard nook
                        other += 1
        check(other == 0, f"[D{z}] E: visible geometry alone closes the block except the road-end tunnel mouths "
                          f"({mouths} tunnel cells, {other} other cells; invisible walls seal the mouths)")

        # Traffic covers the whole walkable length (no traffic-free crossing at the ends)
        check(TRAFFIC_HALF > PEN + 12, f"[D{z}] traffic runs z±{TRAFFIC_HALF}, beyond the sealed ends z±{PEN}")
        # Lanes fill the asphalt exactly: no safe shoulder between the outer lane and the kerb
        check(abs((max(LANE_OFFSETS) + LANE_WIDTH / 2) - ROAD) < 1e-6 and abs((min(LANE_OFFSETS) - LANE_WIDTH / 2) + ROAD) < 1e-6,
              f"[D{z}] lanes span the full asphalt width (no safe shoulder)")

    for n in notes:
        print(n)
    for f in failures:
        print(f)
    print(f"\n{len(notes)} ok/info, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
