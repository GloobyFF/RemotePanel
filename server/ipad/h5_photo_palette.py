"""Photo-derived color tokens for offline H5-lite previews (no live imports)."""
import colorsys
from PIL import Image


def luminance(rgb):
    values = [v / 255 for v in rgb]
    values = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values]
    return sum(v * w for v, w in zip(values, (.2126, .7152, .0722)))


def contrast(a, b):
    x, y = sorted((luminance(a), luminance(b)))
    return (y + .05) / (x + .05)


def palette(photo, index):
    sample = photo.copy()
    sample.thumbnail((160, 160))
    quantized = sample.quantize(colors=8, method=Image.Quantize.MEDIANCUT)
    table = quantized.getpalette()
    samples = [{'rgb': table[c * 3:c * 3 + 3], 'pixels': n}
               for n, c in sorted(quantized.getcolors(), reverse=True)]
    # Dominant sample is the actual most populous quantized color, not a preset hue.
    dominant = samples[0]['rgb']
    h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in dominant))
    bg = tuple(round(v * 255) for v in colorsys.hls_to_rgb(h, .22 if index % 3 == 0 else .32, min(.48, max(.12, s))))
    # Keep the dominant photo-derived background, then choose a readable ink.
    # Some light source photos need dark type; forcing cream would fail WCAG.
    light_ink = (255, 249, 237)
    dark_ink = (28, 25, 22)
    fg = light_ink if contrast(light_ink, bg) >= contrast(dark_ink, bg) else dark_ink
    if contrast(fg, bg) < 4.5:
        fg = (255, 255, 255) if luminance(bg) < .35 else (20, 20, 20)
    muted = tuple(round(.72 * a + .28 * b) for a, b in zip(fg, bg))
    if contrast(muted, bg) < 4.5:
        muted = fg
    assert contrast(fg, bg) >= 4.5 and contrast(muted, bg) >= 4.5
    return {'background': bg, 'foreground': fg, 'muted': muted,
            'dominant': dominant, 'samples': samples,
            'foreground_contrast': contrast(fg, bg), 'muted_contrast': contrast(muted, bg)}
