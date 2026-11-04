"""Key the flat-colour Mivo logo off its cream background into transparent PNGs.

Source: usemivo-website/public/images/mivo-logo-1024.png (raster only; swap in the
original vector for the final print run). Writes a light-background version (brand
colours) and a dark-background version (wordmark #E29A50, meerkat #FAF3E8).
"""
import numpy as np
from PIL import Image

SRC = "/Users/pranshuraithatha/usemivo-website/public/images/mivo-logo-1024.png"
im = np.asarray(Image.open(SRC).convert("RGB")).astype(float)
bg = im[5, 5]
fg = {"word": im[520, 690], "dot": im[422, 486], "cat": im[400, 690]}
print("bg", bg, {k: v for k, v in fg.items()})

h, w, _ = im.shape
best_res = np.full((h, w), 1e9)
alpha = np.zeros((h, w))
cls = np.zeros((h, w), dtype=int)
names = list(fg)
for i, n in enumerate(names):
    d = fg[n] - bg
    a = np.clip(((im - bg) @ d) / (d @ d), 0, 1)
    res = np.linalg.norm(im - (bg + a[..., None] * d), axis=2)
    better = res < best_res
    best_res[better] = res[better]
    alpha[better] = a[better]
    cls[better] = i

alpha[alpha < 0.04] = 0
ys, xs = np.where(alpha > 0)
box = (xs.min() - 6, ys.min() - 6, xs.max() + 7, ys.max() + 7)

def render(colors, out):
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    for i, n in enumerate(names):
        m = cls == i
        rgba[m, :3] = colors[n]
    rgba[..., 3] = (alpha * 255).round()
    img = Image.fromarray(rgba).crop(box)
    img = img.resize((img.width * 2, img.height * 2), Image.LANCZOS)
    img.save(out)
    print(out, img.size)

render({n: fg[n].astype(np.uint8) for n in names}, "assets/logo-light.png")
render({"word": (0xE2, 0x9A, 0x50), "dot": (0xD4, 0x87, 0x2A), "cat": (0xFA, 0xF3, 0xE8)}, "assets/logo-dark.png")
