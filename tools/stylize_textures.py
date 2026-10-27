#!/usr/bin/env python3
"""Stylize the Terrain3D texture sets with a nearest-colour quantizer.

Reads the photo-sourced originals from world/textures/source/ and writes the
stylized versions over world/textures/<name>_{albedo,normal}.png. Sand is left
alone. Re-run any time; the sources are never modified.

Channel packing (see world/textures/CREDITS.txt) is preserved:
  albedo  RGB = colour  -> snapped to a small per-texture palette (k-means in Oklab)
          A   = height  -> softened and stepped into a few terraces
  normal  RGB = normal  -> snapped to the nearest of a small set of directions
          A   = rough.  -> stepped into a few levels

All filtering wraps around the edges so the textures stay tileable.

Usage: python3 tools/stylize_textures.py [name ...]
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "world" / "textures" / "source"
DST = ROOT / "world" / "textures"

# name: (albedo colours, normal tilt rings, azimuths per ring)
SETS = {
	"main":  (6, 2, 6),
	"grass": (5, 2, 6),
	"dirt":  (6, 2, 6),
	"stone": (6, 2, 8),
	"snow":  (4, 1, 6),
}

BLUR_SIGMA = 2.0       # pre-blur before snapping, in pixels; larger = bigger flat patches
MAJORITY_PASSES = 2    # 3x3 mode filter passes on the palette index map to remove speckle
HEIGHT_STEPS = 6
ROUGHNESS_STEPS = 4
SEED = 1


# --- filtering (all wrap-around, so tiles stay seamless) ---------------------

def blur(img, sigma):
	"""Gaussian blur along the first two axes via FFT (inherently wraps)."""
	if sigma <= 0:
		return img
	h, w = img.shape[:2]
	fy = np.fft.fftfreq(h)[:, None]
	fx = np.fft.fftfreq(w)[None, :]
	kernel = np.exp(-2 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
	if img.ndim == 3:
		kernel = kernel[..., None]
	return np.real(np.fft.ifft2(np.fft.fft2(img, axes=(0, 1)) * kernel, axes=(0, 1)))


def majority(index, k, passes):
	"""3x3 mode filter on an integer label map."""
	for _ in range(passes):
		votes = np.zeros(index.shape + (k,), np.int8)
		onehot = np.eye(k, dtype=np.int8)[index]
		for dy in (-1, 0, 1):
			for dx in (-1, 0, 1):
				votes += np.roll(onehot, (dy, dx), axis=(0, 1))
		index = votes.argmax(axis=-1)
	return index


def steps(channel, n):
	"""Quantize a 0..1 channel into n evenly spaced levels across its own range."""
	lo, hi = np.percentile(channel, (1, 99))
	t = np.clip((channel - lo) / max(hi - lo, 1e-6), 0, 1)
	t = np.round(t * (n - 1)) / (n - 1)
	return lo + t * (hi - lo)


# --- colour space ------------------------------------------------------------

def srgb_to_linear(c):
	return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
	c = np.clip(c, 0, 1)
	return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
               [0.2119034982, 0.6806995451, 0.1073969566],
               [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
               [1.9779984951, -2.4285922050, 0.4505937099],
               [0.0259040371, 0.7827717662, -0.8086757660]])


def srgb_to_oklab(rgb):
	lms = srgb_to_linear(rgb) @ M1.T
	return np.cbrt(lms) @ M2.T


def oklab_to_srgb(lab):
	lms = (lab @ np.linalg.inv(M2).T) ** 3
	return linear_to_srgb(lms @ np.linalg.inv(M1).T)


# --- nearest-colour palette --------------------------------------------------

def kmeans(points, k, rng, iters=30):
	"""k-means++ seeded k-means; returns k centres."""
	centres = [points[rng.integers(len(points))]]
	for _ in range(k - 1):
		d = np.min(((points[:, None] - np.array(centres)[None]) ** 2).sum(-1), axis=1)
		centres.append(points[rng.choice(len(points), p=d / d.sum())])
	centres = np.array(centres)
	for _ in range(iters):
		label = nearest(points, centres)
		for i in range(k):
			members = points[label == i]
			if len(members):
				centres[i] = members.mean(axis=0)
	return centres


def nearest(points, palette):
	"""Index of the nearest palette entry (squared Euclidean) for each point."""
	d = (points[:, None, :] - palette[None, :, :]) ** 2
	return d.sum(-1).argmin(axis=1)


def nearest_map(img, palette):
	"""nearest() over an HxWxC image, chunked to bound memory."""
	flat = img.reshape(-1, img.shape[-1])
	out = np.empty(len(flat), np.int64)
	for s in range(0, len(flat), 1 << 16):
		out[s:s + (1 << 16)] = nearest(flat[s:s + (1 << 16)], palette)
	return out.reshape(img.shape[:2])


# --- per-map stylizers -------------------------------------------------------

def stylize_albedo(rgba, k, rng):
	lab = srgb_to_oklab(rgba[..., :3])
	soft = blur(lab, BLUR_SIGMA)

	sample = soft.reshape(-1, 3)[rng.choice(soft.shape[0] * soft.shape[1], 20000, replace=False)]
	palette = kmeans(sample, k, rng)
	palette = palette[np.argsort(palette[:, 0])]  # dark to light, for stable output

	index = majority(nearest_map(soft, palette), k, MAJORITY_PASSES)
	out = np.empty_like(rgba)
	out[..., :3] = oklab_to_srgb(palette[index])
	out[..., 3] = steps(blur(rgba[..., 3], BLUR_SIGMA), HEIGHT_STEPS)
	return out, palette


def normal_palette(n, rings, azimuths):
	"""Flat + `rings` rings of tilted directions, tilts picked from this map's own slope spread."""
	tilt = np.arccos(np.clip(n[..., 2], -1, 1)).ravel()
	percentiles = np.linspace(55, 92, rings) if rings > 1 else [75]
	dirs = [(0.0, 0.0, 1.0)]
	for r, theta in enumerate(np.percentile(tilt, percentiles)):
		offset = np.pi / azimuths * (r % 2)  # stagger alternate rings
		for a in range(azimuths):
			phi = 2 * np.pi * a / azimuths + offset
			dirs.append((np.sin(theta) * np.cos(phi), np.sin(theta) * np.sin(phi), np.cos(theta)))
	return np.array(dirs)


def stylize_normal(rgba, rings, azimuths):
	n = rgba[..., :3] * 2 - 1
	n = blur(n, BLUR_SIGMA)
	n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-8

	palette = normal_palette(n, rings, azimuths)
	# For unit vectors, nearest by Euclidean distance == largest dot product.
	index = majority(nearest_map(n, palette), len(palette), MAJORITY_PASSES)
	out = np.empty_like(rgba)
	out[..., :3] = palette[index] * 0.5 + 0.5
	out[..., 3] = steps(blur(rgba[..., 3], BLUR_SIGMA), ROUGHNESS_STEPS)
	return out


# --- io ----------------------------------------------------------------------

def load(path):
	return np.asarray(Image.open(path).convert("RGBA"), np.float64) / 255.0


def save(rgba, path):
	Image.fromarray(np.round(np.clip(rgba, 0, 1) * 255).astype(np.uint8)).save(path)


def main(names):
	for name in names:
		k, rings, azimuths = SETS[name]
		rng = np.random.default_rng(SEED)

		albedo, palette = stylize_albedo(load(SRC / f"{name}_albedo.png"), k, rng)
		save(albedo, DST / f"{name}_albedo.png")
		save(stylize_normal(load(SRC / f"{name}_normal.png"), rings, azimuths), DST / f"{name}_normal.png")

		swatch = " ".join("#%02x%02x%02x" % tuple(np.round(c * 255).astype(int)) for c in oklab_to_srgb(palette))
		print(f"{name:6s} {k} colours, {1 + rings * azimuths} normals  {swatch}")


if __name__ == "__main__":
	names = sys.argv[1:] or list(SETS)
	unknown = [n for n in names if n not in SETS]
	if unknown:
		sys.exit(f"unknown texture set(s): {', '.join(unknown)} (sand is intentionally excluded)")
	main(names)
