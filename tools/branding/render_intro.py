"""Renders the "Developed by DragonRot" studio intro in true HD for the game (DESIGN.md 7.5).

    python tools/branding/render_intro.py "<path to the dragonrot-intro folder>"

The intro's original is a canvas animation (source/dragonrot-intro.html, 1280x720 logical, any
pixel density). Its exported MP4 was only 1888x998 at a low bitrate, so the game showed it soft
and out of shape. This plays a copy of the animation in a hidden browser (installed Chrome or Edge,
through Playwright), draws every frame at exactly 1920x1080, 60 frames a second, and encodes them
with the intro's own sound (dragonrot-intro.wav) to Ogg Theora, the format Godot plays:
assets/video/dragonrot_intro.ogv. The user's folder is only read.
Needs: pip install playwright (no browser download: it uses the installed Chrome or Edge), ffmpeg.
"""
import base64
import os
import shutil
import subprocess
import sys

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
WORK = os.path.join(HERE, "out", "intro")
FRAMES = os.path.join(WORK, "frames")
OUT = os.path.join(REPO, "assets", "video", "dragonrot_intro.ogv")
FPS = 60
DURATION_MS = 4000
# 1280x720 logical x 1.5 = 1920x1080 pixels.
PIXEL_SCALE = 1.5


def prepare_page(source_dir):
    """A copy of the animation that draws at PIXEL_SCALE and lets us draw any moment on demand."""
    page_dir = os.path.join(WORK, "page")
    if os.path.isdir(page_dir):
        shutil.rmtree(page_dir)
    shutil.copytree(os.path.join(source_dir, "source"), page_dir)
    path = os.path.join(page_dir, "dragonrot-intro.html")
    html = open(path, encoding="utf-8").read()
    patches = [
        ("const dpr = Math.min(2, window.devicePixelRatio || 1);", f"const dpr = {PIXEL_SCALE};"),
        ("requestAnimationFrame(frame);\n})();", "requestAnimationFrame(frame);\nwindow.__render = render;\nwindow.__ready = () => ready;\n})();"),
    ]
    for old, new in patches:
        if old not in html:
            sys.exit(f"the animation changed; cannot find: {old[:60]}")
        html = html.replace(old, new)
    open(path, "w", encoding="utf-8").write(html)
    return path


def browser_path():
    for path in (r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                 r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"):
        if os.path.exists(path):
            return path
    sys.exit("no Chrome or Edge found")


def render_frames(page_path):
    if os.path.isdir(FRAMES):
        shutil.rmtree(FRAMES)
    os.makedirs(FRAMES)
    count = DURATION_MS * FPS // 1000
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=browser_path(), headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 900})
        page.goto("file:///" + page_path.replace("\\", "/"))
        page.wait_for_function("window.__ready && window.__ready()", timeout=20000)
        for i in range(count):
            t = i * 1000.0 / FPS
            data = page.evaluate("t => { window.__render(t); return document.getElementById('c').toDataURL('image/png'); }", t)
            with open(os.path.join(FRAMES, f"{i:04d}.png"), "wb") as f:
                f.write(base64.b64decode(data.split(",", 1)[1]))
        browser.close()
    print(f"rendered {count} frames")


def encode(source_dir):
    wav = os.path.join(source_dir, "dragonrot-intro.wav")
    cmd = ["ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(FRAMES, "%04d.png"), "-i", wav,
           "-c:v", "libtheora", "-q:v", "10", "-pix_fmt", "yuv420p",
           "-c:a", "libvorbis", "-q:a", "6", "-shortest", OUT]
    subprocess.run(cmd, check=True)
    print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    source_dir = sys.argv[1]
    page_path = prepare_page(source_dir)
    render_frames(page_path)
    encode(source_dir)


if __name__ == "__main__":
    main()
