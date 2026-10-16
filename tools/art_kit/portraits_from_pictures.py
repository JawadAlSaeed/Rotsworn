"""Big hero portraits from pictures (cards #140, #141): turns a painted picture of each hero into
the game's pixel art portrait.

Drop `<hero id>.png` (or .jpg / .webp) into tools/art_kit/sources/portraits/ (PROMPTS.md there has
the words to give an AI image tool), then run:

    python tools/art_kit/portraits_from_pictures.py            # every picture found
    python tools/art_kit/portraits_from_pictures.py alder      # one hero

Each picture is cropped to a tall BIG_W x BIG_H frame around the face (found automatically; a
`crops.json` next to the pictures can set it by hand: {"alder": [x, y, w, h]} in fractions of the
picture), shrunk, cut down to COLORS colours (k-means in OKLab, so the shading steps stay even),
cleaned of lone pixels, and saved to assets/sprites/portraits_big/<id>.png: the players screen
shows it.

The small face everywhere else in the game (party panels, turn order, party screen) is a square
FACE x FACE cut from the same picture, tighter around the eyes so they still read small:
`faces.json` next to the pictures sets it ({"alder": [x, y, size]}, fractions of the picture's
width and height, size a share of its width). It goes to assets/sprites/portraits_big/<id>_face.png.
Zoomed previews go to tools/art_kit/preview/portraits_big/.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(os.path.dirname(HERE))
SOURCES = os.path.join(HERE, "sources", "portraits")
OUT = os.path.join(PROJECT, "assets", "sprites", "portraits_big")
PREVIEW = os.path.join(HERE, "preview", "portraits_big")

BIG_W = 192
BIG_H = 288
COLORS = 64
FACE = 64
FACE_COLORS = 48
# The face's height as a share of the frame, and where its centre sits (share from the top).
FACE_SHARE = 0.42
FACE_CENTRE_Y = 0.42
EXTS = (".png", ".jpg", ".jpeg", ".webp")


# --- colour maths (sRGB <-> OKLab) -----------------------------------------------------------

def _to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _to_srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def rgb_to_oklab(rgb: np.ndarray) -> np.ndarray:
    lin = _to_linear(rgb)
    lms = lin @ np.array([[0.4122214708, 0.2119034982, 0.0883024619],
                          [0.5363325363, 0.6806995451, 0.2817188376],
                          [0.0514459929, 0.1073969566, 0.6299787005]])
    lms = np.cbrt(lms)
    return lms @ np.array([[0.2104542553, 1.9779984951, 0.0259040371],
                           [0.7936177850, -2.4285922050, 0.7827717662],
                           [-0.0040720468, 0.4505937099, -0.8086757660]])


def oklab_to_rgb(lab: np.ndarray) -> np.ndarray:
    lms = lab @ np.array([[1.0, 1.0, 1.0],
                          [0.3963377774, -0.1055613458, -0.0894841775],
                          [0.2158037573, -0.0638541728, -1.2914855480]])
    lms = lms ** 3
    lin = lms @ np.array([[4.0767416621, -1.2684380046, -0.0041960863],
                          [-3.3077115913, 2.6097574011, -0.7034186147],
                          [0.2309699292, -0.3413193965, 1.7076147010]])
    return _to_srgb(lin)


# --- steps -------------------------------------------------------------------------------------

def find_face(img: Image.Image) -> tuple[float, float, float] | None:
    """(centre x, centre y, height) of the biggest face found, in pixels; None if none."""
    try:
        import cv2
    except ImportError:
        return None
    if not hasattr(cv2, "CascadeClassifier"):  # OpenCV builds without the classic detector
        return None
    grey = np.asarray(img.convert("L"))
    best = None
    for name in ("haarcascade_frontalface_default.xml", "haarcascade_profileface.xml"):
        cascade = cv2.CascadeClassifier(os.path.join(cv2.data.haarcascades, name))
        faces = cascade.detectMultiScale(grey, scaleFactor=1.1, minNeighbors=5,
                                         minSize=(grey.shape[1] // 8, grey.shape[1] // 8))
        for x, y, w, h in faces:
            if best is None or w * h > best[2] * best[3]:
                best = (x, y, w, h)
    if best is None:
        return None
    x, y, w, h = best
    return x + w / 2.0, y + h / 2.0, float(h)


def crop_box(img: Image.Image, hero: str, crops: dict) -> tuple[int, int, int, int]:
    W, H = img.size
    aspect = BIG_W / BIG_H
    if hero in crops:
        fx, fy, fw, fh = crops[hero]
        return int(fx * W), int(fy * H), int((fx + fw) * W), int((fy + fh) * H)
    face = find_face(img)
    if face is not None:
        cx, cy, fh = face
        h = min(float(H), fh / FACE_SHARE)
        w = h * aspect
        if w > W:
            w = float(W)
            h = w / aspect
        x0 = min(max(cx - w / 2.0, 0.0), W - w)
        y0 = min(max(cy - h * FACE_CENTRE_Y, 0.0), H - h)
        return int(x0), int(y0), int(x0 + w), int(y0 + h)
    # No face found: the tallest 2:3 box, centred left to right, from the top.
    h = float(H)
    w = h * aspect
    if w > W:
        w = float(W)
        h = w / aspect
    x0 = (W - w) / 2.0
    return int(x0), 0, int(x0 + w), int(h)


def kmeans_palette(lab: np.ndarray, k: int, iters: int = 18, seed: int = 7) -> tuple[np.ndarray, np.ndarray]:
    """k colour centres (OKLab) and each pixel's centre index. Lightness counts double, so the
    shading steps stay apart."""
    weight = np.array([2.0, 1.0, 1.0])
    pts = lab * weight
    rng = np.random.default_rng(seed)
    # k-means++ start.
    centres = [pts[rng.integers(len(pts))]]
    for _ in range(1, k):
        d = np.min(((pts[:, None, :] - np.array(centres)[None]) ** 2).sum(-1), axis=1)
        centres.append(pts[rng.choice(len(pts), p=d / d.sum())])
    c = np.array(centres)
    for _ in range(iters):
        idx = np.argmin(((pts[:, None, :] - c[None]) ** 2).sum(-1), axis=1)
        for j in range(k):
            m = idx == j
            if m.any():
                c[j] = pts[m].mean(0)
    idx = np.argmin(((pts[:, None, :] - c[None]) ** 2).sum(-1), axis=1)
    return c / weight, idx


def despeckle(idx: np.ndarray) -> np.ndarray:
    """A pixel whose colour none of its 4 neighbours share takes the commonest neighbour colour."""
    out = idx.copy()
    H, W = idx.shape
    for y in range(H):
        for x in range(W):
            n = [idx[yy, xx] for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1))
                 if 0 <= yy < H and 0 <= xx < W]
            if idx[y, x] not in n:
                vals, counts = np.unique(n, return_counts=True)
                out[y, x] = vals[np.argmax(counts)]
    return out


def convert(path: str, hero: str, crops: dict) -> np.ndarray:
    img = Image.open(path).convert("RGB")
    box = crop_box(img, hero, crops)
    img = img.crop(box)
    # Shrink in two steps (a box filter, then a light sharpen) so edges stay crisp.
    img = img.resize((BIG_W * 2, BIG_H * 2), Image.LANCZOS).resize((BIG_W, BIG_H), Image.BOX)
    img = img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    img = ImageEnhance.Contrast(img).enhance(1.08)
    rgb = np.asarray(img, dtype=np.float64) / 255.0
    lab = rgb_to_oklab(rgb.reshape(-1, 3))
    centres, idx = kmeans_palette(lab, COLORS)
    idx = despeckle(idx.reshape(BIG_H, BIG_W))
    out_rgb = oklab_to_rgb(centres)[idx]
    out = np.zeros((BIG_H, BIG_W, 4), dtype=np.uint8)
    out[..., :3] = np.round(out_rgb * 255.0).astype(np.uint8)
    out[..., 3] = 255
    return out


def convert_face(path: str, box: list[float]) -> np.ndarray:
    """The small square face: shrunk straight from the picture (no despeckle, a little more
    contrast) so eyes and mouth survive at FACE pixels."""
    img = Image.open(path).convert("RGB")
    W, H = img.size
    x, y, size = box
    side = size * W
    img = img.crop((int(x * W), int(y * H), int(x * W + side), int(y * H + side)))
    img = img.resize((FACE, FACE), Image.LANCZOS)
    img = ImageEnhance.Contrast(img).enhance(1.12)
    rgb = np.asarray(img, dtype=np.float64) / 255.0
    centres, idx = kmeans_palette(rgb_to_oklab(rgb.reshape(-1, 3)), FACE_COLORS)
    out = np.zeros((FACE, FACE, 4), dtype=np.uint8)
    out[..., :3] = np.round(oklab_to_rgb(centres)[idx.reshape(FACE, FACE)] * 255.0).astype(np.uint8)
    out[..., 3] = 255
    return out


def save(name: str, arr: np.ndarray) -> None:
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    img = Image.fromarray(arr, "RGBA")
    img.save(os.path.join(OUT, "%s.png" % name))
    zoom = 2 if arr.shape[1] > FACE else 4
    img.resize((arr.shape[1] * zoom, arr.shape[0] * zoom), Image.NEAREST).save(os.path.join(PREVIEW, "%s.png" % name))


def main(argv: list[str]) -> int:
    crops_path = os.path.join(SOURCES, "crops.json")
    crops = json.load(open(crops_path)) if os.path.exists(crops_path) else {}
    faces_path = os.path.join(SOURCES, "faces.json")
    faces = json.load(open(faces_path)) if os.path.exists(faces_path) else {}
    found = {}
    for name in sorted(os.listdir(SOURCES)) if os.path.isdir(SOURCES) else []:
        base, ext = os.path.splitext(name)
        if ext.lower() in EXTS:
            found[base.lower()] = os.path.join(SOURCES, name)
    wanted = [a.lower() for a in argv] or sorted(found)
    if not wanted:
        print("no pictures in %s (see PROMPTS.md there)" % SOURCES)
        return 1
    status = 0
    for hero in wanted:
        if hero not in found:
            print("%-8s missing: put %s.png in %s" % (hero, hero, SOURCES))
            status = 1
            continue
        save(hero, convert(found[hero], hero, crops))
        print("%-8s ok  assets/sprites/portraits_big/%s.png" % (hero, hero))
        if hero in faces:
            save(hero + "_face", convert_face(found[hero], faces[hero]))
            print("%-8s ok  assets/sprites/portraits_big/%s_face.png" % (hero, hero))
        else:
            print("%-8s no face box in faces.json, small face skipped" % hero)
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
