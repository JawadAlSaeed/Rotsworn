"""Shared helpers for build_sfx.py and check_sfx.py: render a cue from kit recordings, measure it.

A cue is one or more layers of real recordings from the sound-layer kit (audio/kit). A layer is
only cut, pitched by playback speed, filtered, delayed and mixed: nothing is synthesized.
"""
import json, os
from fractions import Fraction
import numpy as np
from scipy import signal
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
KIT = os.path.join(HERE, "audio", "kit")
RULES = os.path.join(HERE, "cue_rules.json")
SR = 48000          # the kit's rate; every step runs at it
OUT_SR = 44100      # what the game ships (16-bit mono PCM)
CEILING_DB = -1.0   # sample peak ceiling of a finished cue
MAX_LIMIT_DB = 6.0  # most gain reduction the peak limiter may apply
ONSET_DB = -40.0    # a cue "starts" at the first sample this far under its peak


def ms(v):
    return int(round(float(v) * SR / 1000.0))


def db(x):
    return 20.0 * np.log10(max(float(x), 1e-12))


def catalog():
    c = json.load(open(os.path.join(KIT, "catalog.json"), encoding="utf-8"))["sounds"]
    return {e["id"]: e for e in (c if isinstance(c, list) else c.values())}


def kit_credits():
    """kit id -> credit line, from the kit's CREDITS.md (Freesound and added files) and catalog."""
    out, packs = {}, {}
    for line in open(os.path.join(KIT, "CREDITS.md"), encoding="utf-8").read().splitlines():
        if not line.startswith("- "):
            continue
        body = line[2:]
        head, _, rest = body.partition(": ")
        if "/" in head and rest:
            out[head] = rest
        else:
            packs[body.split(", CC0")[0]] = body
    for k, e in catalog().items():
        if k not in out:
            out[k] = packs.get(e.get("credit", ""), e.get("credit", ""))
    return out


def rules():
    return json.load(open(RULES, encoding="utf-8"))


def load(path):
    x, sr = sf.read(path, always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        f = Fraction(SR, sr).limit_denominator(1000)
        x = signal.resample_poly(x, f.numerator, f.denominator)
    return x.astype(np.float64)


def onset(x, rel_db=ONSET_DB):
    pk = np.max(np.abs(x)) if len(x) else 0.0
    if pk <= 0:
        return 0
    return int(np.argmax(np.abs(x) > pk * 10 ** (rel_db / 20.0)))


def fade(x, n_in, n_out):
    x = x.copy()
    if n_in > 0 and len(x) > n_in:
        x[:n_in] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n_in))
    if n_out > 0 and len(x) > n_out:
        x[-n_out:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n_out))
    return x


def layer_audio(layer, cat):
    """One layer: the source recording cut, pitched, filtered, gained and trimmed to its onset."""
    sound = layer["sound"]
    if sound.startswith("synth:"):
        raise ValueError(f"'{sound}': synthesized sounds are not allowed, use a recording")
    if sound in cat:
        x = load(os.path.join(KIT, cat[sound]["file"]))
    else:
        p = sound if os.path.isabs(sound) else os.path.join(HERE, sound)
        if not os.path.exists(p):
            raise FileNotFoundError(f"'{sound}' is neither a kit id nor a file")
        x = load(p)
    x = x[ms(layer.get("start_ms", 0)):]
    if layer.get("len_ms"):
        x = fade(x[:ms(layer["len_ms"])], 0, ms(10))
    st = float(layer.get("pitch", 0))
    if st:
        # playback speed: +12 = twice as fast, an octave up (like a tape or sampler)
        f = Fraction(2 ** (-st / 12.0)).limit_denominator(400)
        x = signal.resample_poly(x, f.numerator, f.denominator)
    if layer.get("highpass_hz"):
        x = signal.sosfilt(signal.butter(4, float(layer["highpass_hz"]), "highpass", fs=SR, output="sos"), x)
    if layer.get("lowpass_hz"):
        x = signal.sosfilt(signal.butter(4, float(layer["lowpass_hz"]), "lowpass", fs=SR, output="sos"), x)
    x = x * 10 ** (float(layer.get("gain_db", 0)) / 20.0)
    on = onset(x)
    return x[max(0, on - ms(0.5)):]


# K-weighting (ITU-R BS.1770) at 48 kHz, so a low boom and a high click compare fairly.
_K1 = ([1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585])
_K2 = ([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621])


def loudness(x):
    """Loudest 100 ms of the cue, K-weighted, in LUFS-like units (short cues are padded to 100 ms)."""
    n = ms(100)
    y = np.concatenate([x, np.zeros(max(0, n - len(x)) + n)])
    y = signal.lfilter(*_K2, signal.lfilter(*_K1, y))
    p = np.convolve(y * y, np.ones(n) / n, mode="valid")[::ms(5)]
    return -0.691 + 10.0 * np.log10(max(float(p.max()), 1e-12))


def limit(x, ceiling_db, max_db):
    """Lookahead peak limiter (1.5 ms lookahead, 40 ms release), at most max_db of reduction."""
    c = 10 ** (ceiling_db / 20.0)
    need = np.minimum(1.0, c / np.maximum(np.abs(x), 1e-12))
    need = np.maximum(need, 10 ** (-max_db / 20.0))
    la = ms(1.5)
    pad = np.concatenate([need, np.ones(la)])
    g = np.lib.stride_tricks.sliding_window_view(pad, la + 1).min(axis=1)[:len(need)]
    g = np.convolve(np.concatenate([np.full(la, g[0]), g]), np.ones(la) / la, mode="valid")[:len(need)]
    rel = np.exp(-1.0 / (0.040 * SR))
    out = np.empty_like(g)
    cur = g[0]
    for i, v in enumerate(g):
        cur = v if v < cur else rel * cur + (1 - rel) * v
        out[i] = cur
    return x * out


def render(cue, target_lu, cat):
    """Mix a cue's layers and finish it: starts at once, clean tail, target loudness, peak ceiling.
    Returns (audio at OUT_SR, info)."""
    parts = []
    for layer in cue["layers"]:
        a = layer_audio(layer, cat)
        parts.append((ms(layer.get("at_ms", 0)), a))
    n = max(at + len(a) for at, a in parts)
    mix = np.zeros(n)
    for at, a in parts:
        mix[at:at + len(a)] += a
    mix = mix[max(0, onset(mix) - ms(0.5)):]
    if cue.get("len_ms"):
        mix = mix[:ms(cue["len_ms"])]
    else:
        env = np.sqrt(np.convolve(mix * mix, np.ones(ms(5)) / ms(5), mode="same"))
        live = np.nonzero(env > np.max(env) * 10 ** (-60 / 20.0))[0]
        mix = mix[:min(len(mix), (live[-1] if len(live) else len(mix)) + ms(5))]
    mix = fade(mix, ms(0.5), ms(cue.get("fade_ms", 30)))
    src = mix
    gain = target_lu - loudness(src)
    for _ in range(4):               # limiting costs some loudness: make it up, within the limiter's cap
        mix = src * 10 ** (gain / 20.0)
        over = db(np.max(np.abs(mix))) - CEILING_DB
        if over > MAX_LIMIT_DB:      # more than the limiter may take: turn the whole cue down
            mix = mix * 10 ** (-(over - MAX_LIMIT_DB) / 20.0)
        if over > 0:
            mix = limit(mix, CEILING_DB - 0.2, MAX_LIMIT_DB)
        short = target_lu - loudness(mix)
        if abs(short) < 0.2 or over > MAX_LIMIT_DB:
            break
        gain += short
    f = Fraction(OUT_SR, SR)
    out = signal.resample_poly(mix, f.numerator, f.denominator)
    pk = np.max(np.abs(out))
    if db(pk) > CEILING_DB:
        out = out * 10 ** ((CEILING_DB - 0.05 - db(pk)) / 20.0)
    return out, dict(sources=[l["sound"] for l in cue["layers"]])


def write(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sf.write(path, np.clip(x, -1.0, 1.0), OUT_SR, subtype="PCM_16")


def measure(path):
    """What check_sfx.py judges: format, length, start, rise, peak, loudness, clean ends."""
    info = sf.info(path)
    x = load(path)
    env = np.sqrt(np.convolve(x * x, np.ones(ms(2)) / ms(2), mode="same"))
    on = onset(x)
    raw, _ = sf.read(path, always_2d=True)
    return dict(
        rate=info.samplerate, channels=info.channels, subtype=info.subtype,
        len_ms=len(x) / SR * 1000.0,
        onset_ms=on / SR * 1000.0,
        rise_ms=(int(np.argmax(env)) - on) / SR * 1000.0,
        peak_db=db(np.max(np.abs(raw))),
        lu=loudness(x),
        head_db=db(np.max(np.abs(raw[:max(1, int(info.samplerate * 0.0002))]))),
        tail_db=db(np.max(np.abs(raw[-int(info.samplerate * 0.005):]))),
        dc=float(np.mean(raw)),
    )
