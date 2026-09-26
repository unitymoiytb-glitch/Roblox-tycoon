"""Approximate preview renderer for the generated scene (NOT Roblox's renderer).

Ray-casts the part dump from tools/tests/scene_dump.lua with numpy: boxes, balls and
cylinders, sun light + shadows, the starter-room bulb as a shadowed point light,
sky occlusion for ambient, distance haze and a light colour grade that mimics the
game's Lighting settings. It is meant for judging composition, scale and readability
of camera views, not exact materials or Roblox lighting.

Usage: python3 tools/render_preview.py scene.txt out_dir [view ...]
"""
import math
import os
import sys

import numpy as np
from PIL import Image

EPS = 1e-4
SUN_DIR = np.array([-0.75, 0.47, 0.47])  # late afternoon; assumed west-south-west
SUN_DIR = SUN_DIR / np.linalg.norm(SUN_DIR)
SUN_COL = np.array([1.0, 0.88, 0.72]) * 1.05
AMB_IN = np.array([76, 66, 58]) / 255 * 0.9
AMB_OUT = np.array([125, 112, 98]) / 255 * 0.95
HAZE = np.array([225, 205, 178]) / 255
SKY_TOP = np.array([150, 172, 204]) / 255


def load(path):
    parts, home = [], None
    for line in open(path, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if f[0] == "PART" and len(f) >= 13:
            if float(f[9]) >= 0.95:
                continue
            pos = np.array(list(map(float, f[3].split(","))))
            r = list(map(float, f[4].split(",")))
            R = np.array(r).reshape(3, 3)
            size = np.array(list(map(float, f[5].split(","))))
            parts.append(dict(name=f[1], c=pos, R=R, h=size / 2, shape=f[10],
                              col=np.array(list(map(int, f[11].split(",")))) / 255.0, mat=f[12],
                              refl=float(f[13]) if len(f) > 13 else 0.0))
        elif f[0] == "CAMHOME":
            home = (np.array(list(map(float, f[1].split(",")))), np.array(list(map(float, f[2].split(",")))))
    return parts, home


def intersect(p, o, d, want_normal=True):
    """Ray/shape intersection. o: (3,) or (N,3); d: (N,3). Returns t (N,), normal (N,3) or None."""
    R, c, h = p["R"], p["c"], p["h"]
    ol = (o - c) @ R
    dl = d @ R
    n = d.shape[0]
    t = np.full(n, np.inf)
    nl = np.zeros((n, 3)) if want_normal else None
    if ol.ndim == 1:
        ol = np.broadcast_to(ol, (n, 3))
    if p["shape"] == "Ball":
        r = float(np.min(h))
        b = np.einsum("ij,ij->i", ol, dl)
        cc = np.einsum("ij,ij->i", ol, ol) - r * r
        disc = b * b - cc
        ok = disc >= 0
        sq = np.sqrt(np.where(ok, disc, 0))
        t0 = -b - sq
        t1 = -b + sq
        tt = np.where(t0 > EPS, t0, t1)
        ok &= tt > EPS
        t = np.where(ok, tt, np.inf)
        if want_normal:
            hp = ol + dl * np.where(ok, tt, 0)[:, None]
            nl = hp / r
    elif p["shape"] == "Cylinder":
        r = float(min(h[1], h[2]))
        hx = float(h[0])
        oy, oz, dy, dz = ol[:, 1], ol[:, 2], dl[:, 1], dl[:, 2]
        a = dy * dy + dz * dz
        b = oy * dy + oz * dz
        cc = oy * oy + oz * oz - r * r
        disc = b * b - a * cc
        ok = (disc >= 0) & (a > 1e-12)
        sq = np.sqrt(np.where(ok, disc, 0))
        asafe = np.where(a > 1e-12, a, 1)
        t0 = (-b - sq) / asafe
        t1 = (-b + sq) / asafe
        side = np.full(n, np.inf)
        for tt in (t1, t0):
            x = ol[:, 0] + dl[:, 0] * tt
            good = ok & (tt > EPS) & (np.abs(x) <= hx)
            side = np.where(good, tt, side)
        # caps
        cap = np.full(n, np.inf)
        dx = np.where(np.abs(dl[:, 0]) > 1e-12, dl[:, 0], 1e-12)
        for s in (-1, 1):
            tt = (s * hx - ol[:, 0]) / dx
            y = oy + dy * tt
            z = oz + dz * tt
            good = (tt > EPS) & (y * y + z * z <= r * r)
            cap = np.where(good & (tt < cap), tt, cap)
        t = np.minimum(side, cap)
        if want_normal:
            hp = ol + dl * np.where(np.isfinite(t), t, 0)[:, None]
            isCap = cap <= side
            nl = np.stack([np.where(isCap, np.sign(hp[:, 0]), 0), np.where(isCap, 0, hp[:, 1] / r), np.where(isCap, 0, hp[:, 2] / r)], axis=1)
    else:
        with np.errstate(divide="ignore", invalid="ignore"):
            inv = 1.0 / np.where(np.abs(dl) > 1e-12, dl, 1e-12)
            t1 = (-h - ol) * inv
            t2 = (h - ol) * inv
        tmin3 = np.minimum(t1, t2)
        tmax3 = np.maximum(t1, t2)
        tmin = tmin3.max(axis=1)
        tmax = tmax3.min(axis=1)
        ok = (tmax >= np.maximum(tmin, EPS))
        tt = np.where(tmin > EPS, tmin, tmax)
        t = np.where(ok, tt, np.inf)
        if want_normal:
            axis = np.argmax(tmin3, axis=1)
            sgn = -np.sign(dl[np.arange(n), axis])
            nl = np.zeros((n, 3))
            nl[np.arange(n), axis] = sgn
    if want_normal:
        nw = nl @ R.T
        return t, nw
    return t, None


def bound_radius(p):
    return float(np.linalg.norm(p["h"]))


def candidates(parts, o, d, maxdist):
    """Per part, mask of rays that pass within its bounding sphere (origin single point or per-ray)."""
    for i, p in enumerate(parts):
        rad = bound_radius(p)
        oc = p["c"] - o
        if oc.ndim == 1:
            tc = d @ oc
            dist2 = oc @ oc - tc * tc
        else:
            tc = np.einsum("ij,ij->i", oc, d)
            dist2 = np.einsum("ij,ij->i", oc, oc) - tc * tc
        m = (dist2 <= rad * rad) & (tc > -rad) & (tc - rad < maxdist)
        if m.any():
            yield i, p, m


def cast(parts, o, d, maxdist=np.inf, want_normal=True, any_hit=False):
    n = d.shape[0]
    tbest = np.full(n, np.inf)
    idx = np.full(n, -1)
    nbest = np.zeros((n, 3))
    lim = maxdist if np.isscalar(maxdist) else np.max(maxdist)
    for i, p, m in candidates(parts, o, d, lim):
        sub_o = o if o.ndim == 1 else o[m]
        t, nw = intersect(p, sub_o, d[m], want_normal and not any_hit)
        better = t < tbest[m]
        if not np.isscalar(maxdist):
            better &= t < maxdist[m]
        if better.any():
            sel = np.where(m)[0][better]
            tbest[sel] = t[better]
            idx[sel] = i
            if want_normal and not any_hit:
                nbest[sel] = nw[better]
    return tbest, idx, nbest


def hashnoise(pts, scale):
    q = np.floor(pts * scale)
    v = np.sin(q[:, 0] * 12.9898 + q[:, 1] * 78.233 + q[:, 2] * 37.719) * 43758.5453
    return v - np.floor(v)


def shade(parts, hit_p, n, idx, lights, view_d):
    m = idx.shape[0]
    col = np.stack([parts[i]["col"] for i in idx]) if m else np.zeros((0, 3))
    mats = [parts[i]["mat"] for i in idx]
    neon = np.array([mt == "Neon" for mt in mats])
    # face the normal toward the viewer
    flip = np.einsum("ij,ij->i", n, view_d) > 0
    n = np.where(flip[:, None], -n, n)
    # material texture
    tex = np.ones(m)
    matarr = np.array(mats)
    for name, sc, amp in (("CorrodedMetal", 2.5, 0.16), ("Ground", 2.0, 0.18), ("Mud", 2.0, 0.2), ("Fabric", 3.0, 0.08),
                          ("Concrete", 1.5, 0.12), ("Brick", 1.0, 0.18), ("Asphalt", 2.0, 0.1), ("Pavement", 1.2, 0.12),
                          ("Wood", 4.0, 0.12), ("DiamondPlate", 3.0, 0.1), ("LeafyGrass", 1.0, 0.25)):
        mm = matarr == name
        if mm.any():
            tex[mm] = 1 - amp / 2 + amp * hashnoise(hit_p[mm], sc)
    mm = matarr == "WoodPlanks"
    if mm.any():
        stripes = (np.floor(hit_p[mm, 1] * 1.6 + hit_p[mm, 0] * 0.05) % 2)
        tex[mm] = 0.86 + 0.12 * stripes + 0.08 * hashnoise(hit_p[mm], 3)
    mm = matarr == "CorrodedMetal"
    if mm.any():  # vertical corrugation ribs
        rib = 0.5 + 0.5 * np.sin((hit_p[mm, 0] + hit_p[mm, 2]) * 7.0)
        tex[mm] *= 0.9 + 0.12 * rib
    base = col * tex[:, None]
    origin = hit_p + n * 0.03
    # sun
    ndl = np.clip(n @ SUN_DIR, 0, 1)
    lit = ndl > 0
    sun = np.zeros(m)
    if lit.any():
        t, _, _ = cast(parts, origin[lit], np.broadcast_to(SUN_DIR, (lit.sum(), 3)).copy(), 400, False, True)
        s = np.where(np.isfinite(t), 0.0, 1.0)
        sun[lit] = ndl[lit] * s
    # sky visibility (ambient)
    up = np.broadcast_to(np.array([0, 1.0, 0]), (m, 3)).copy()
    t, _, _ = cast(parts, origin, up, 60, False, True)
    skyvis = np.where(np.isfinite(t), 0.18, 1.0)
    amb = AMB_IN[None, :] + AMB_OUT[None, :] * skyvis[:, None] * (0.55 + 0.45 * np.clip(n[:, 1], 0, 1))[:, None]
    light = amb + SUN_COL[None, :] * sun[:, None] * 0.95
    for lp, lc, lr, lb in lights:
        dv = lp - origin
        dist = np.linalg.norm(dv, axis=1)
        near = dist < lr
        if not near.any():
            continue
        ld = dv[near] / dist[near][:, None]
        t, _, _ = cast(parts, origin[near], ld, dist[near] - 0.4, False, True)
        vis = ~np.isfinite(t)
        fall = (1 - dist[near] / lr) ** 2
        ndl2 = np.clip(np.einsum("ij,ij->i", n[near], ld), 0, 1)
        contrib = np.zeros((m, 3))
        contrib[near] = (lc[None, :] * (lb * 1.25 * fall * ndl2 * vis)[:, None])
        light = light + contrib
    out = base * light
    out[neon] = np.clip(col[neon] * 1.6, 0, 1.4)
    return out


def grade(img):
    img = np.clip(img, 0, None)
    img = img / (1 + img * 0.25) * 1.2  # soft tonemap
    lum = img @ np.array([0.299, 0.587, 0.114])
    img = lum[..., None] + (img - lum[..., None]) * 1.11  # saturation
    img = (img - 0.5) * 1.13 + 0.5 + 0.015  # contrast + brightness
    img = img * (np.array([255, 238, 218]) / 255)
    return np.clip(img, 0, 1)


def render_view(parts, lights, cam, target, fov=70, W=800, H=450, ortho=None):
    if ortho:
        (x0, x1, z0, z1) = ortho
        xs = np.linspace(x0, x1, W)
        zs = np.linspace(z0, z1, H)
        X, Z = np.meshgrid(xs, zs)
        o = np.stack([X.ravel(), np.full(X.size, 300.0), Z.ravel()], axis=1)
        d = np.broadcast_to(np.array([0, -1.0, 0]), o.shape).copy()
        t, idx, n = cast_multi(parts, o, d)
    else:
        f = target - cam
        f /= np.linalg.norm(f)
        r = np.cross(f, [0, 1, 0])
        r /= np.linalg.norm(r)
        u = np.cross(r, f)
        th = math.tan(math.radians(fov) / 2)
        ys, xs = np.mgrid[0:H, 0:W]
        px = ((xs + 0.5) / W * 2 - 1) * th * W / H
        py = (1 - (ys + 0.5) / H * 2) * th
        d = f[None, :] + px.ravel()[:, None] * r[None, :] + py.ravel()[:, None] * u[None, :]
        d /= np.linalg.norm(d, axis=1)[:, None]
        o = cam
        t, idx, n = cast(parts, o, d, 700)
    hit = np.isfinite(t)
    img = np.zeros((d.shape[0], 3))
    # sky
    sky_t = np.clip(d[:, 1], 0, 1)[:, None]
    img[:] = HAZE[None, :] * (1 - sky_t) + SKY_TOP[None, :] * sky_t
    if hit.any():
        oo = o[hit] if o.ndim == 2 else o
        hp = oo + d[hit] * t[hit][:, None]
        col = shade(parts, hp, n[hit], idx[hit], lights, d[hit])
        if not ortho:
            fog = 1 - np.exp(-t[hit] * 0.0042)
            col = col * (1 - fog[:, None]) + HAZE[None, :] * 0.92 * fog[:, None]
        img[hit] = col
    img = grade(img).reshape(H, W, 3)
    return Image.fromarray((img * 255).astype(np.uint8))


def cast_multi(parts, o, d):
    # orthographic: per-ray origins
    return cast(parts, o, d, 700)


def main():
    scene, out_dir = sys.argv[1], sys.argv[2]
    views = sys.argv[3:] or ["spawn", "doorway", "alley", "street", "top"]
    parts, home = load(scene)
    os.makedirs(out_dir, exist_ok=True)
    hp, look = home
    lights = []
    for p in parts:
        if p["name"] == "BareBulb":
            lights.append((p["c"], np.array([255, 190, 120]) / 255, 20.0, 1.6))
        if p["name"] == "Embers":
            lights.append((p["c"], np.array([255, 140, 60]) / 255, 7.0, 1.2))
    cx = -400.0
    cams = {
        # Client intro camera: 2.6 studs behind the spawn, 2.6 up, looking 40 studs out of the door.
        "spawn": (hp - look * 4.6 + np.array([0, 3.4, 2.2]), hp + look * 40 + np.array([0, 0.8, 0.6]), 70),
        # Intro shot A (establishing, diagonal from the back-right corner) -> tweens to "spawn" (shot B).
        "spawnA": (hp - look * 4.7 + np.array([0, 3.6, 6.3]), hp + look * 18.9 + np.array([0, -0.5, -12.2]), 70),
        # Default follow camera once control returns (pulled in by the back wall).
        "doorway": (hp - look * 5.0 + np.array([0, 2.4, 0]), hp + look * 30 + np.array([0, 0.5, 0]), 70),
        # Standing at the alley mouth next to Raju, looking across the road.
        "alley": (np.array([cx - 32, 6.0, -1.0]), np.array([cx + 25, 4.0, 6.0]), 70),
        # Standing on the west sidewalk looking down the road with the railway in the middle.
        "rail": (np.array([cx - 24, 6.5, 40]), np.array([cx + 2, 3.0, -40]), 70),
        # Mid-crossing view down the road.
        "street": (np.array([cx - 10, 5.5, 12]), np.array([cx + 2, 3.5, -60]), 70),
        # Elevated establishing shot of the block.
        "aerial": (np.array([cx + 60, 60, -80]), np.array([cx - 15, 0, 5]), 60),
    }
    parts_near = [p for p in parts if abs(p["c"][0] - cx) - bound_radius(p) < 260]
    for v in views:
        if v == "top":
            img = render_view(parts_near, lights, None, None, W=420, H=1600, ortho=(cx - 75, cx + 55, -240, 240))
        else:
            cam, tgt, fov = cams[v]
            img = render_view(parts_near, lights, np.array(cam, float), np.array(tgt, float), fov)
        path = os.path.join(out_dir, f"preview_{v}.png")
        img.save(path)
        print("wrote", path)


if __name__ == "__main__":
    main()
