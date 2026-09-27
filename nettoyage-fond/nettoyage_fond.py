#!/usr/bin/env python3
"""Nettoyage de fond façon Evoto : lisse les taches du mur / sol derrière le sujet
en gardant la couleur, les dégradés de lumière et le grain d'origine.

Principe :
  1. une IA (rembg) détoure le sujet ;
  2. on reconstruit une « plaque » de fond propre : moyenne lissée des couleurs du fond,
     en ignorant le sujet et les taches (deux passes robustes) ;
  3. on remet le grain fin de la photo d'origine sur la plaque pour éviter l'effet plastique ;
  4. on remplace le fond par cette plaque, avec une zone de transition autour du sujet
     pour ne pas abîmer les cheveux.

Usage : python3 nettoyage_fond.py DOSSIER_OU_PHOTOS... [-o SORTIE] [--force 1.0]
"""

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

EXTENSIONS = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".webp"}
WORK_SIZE = 768  # côté long de l'image de travail pour la plaque de fond


def gaussian(img, sigma):
    return cv2.GaussianBlur(img, (0, 0), sigmaX=sigma, sigmaY=sigma, borderType=cv2.BORDER_REFLECT)


def weighted_blur(img, weight, sigma):
    """Flou normalisé : moyenne locale des pixels de poids 1 uniquement (bouche aussi les trous)."""
    w = weight[..., None]
    num = gaussian(img * w, sigma) + 1e-3 * gaussian(img * w, sigma * 6)
    den = gaussian(weight, sigma)[..., None] + 1e-3 * gaussian(weight, sigma * 6)[..., None]
    return num / np.maximum(den, 1e-8)


def subject_alpha(image_rgb8, session):
    from rembg import remove

    mask = remove(Image.fromarray(image_rgb8), session=session, only_mask=True)
    return drop_islands(np.asarray(mask, dtype=np.float32) / 255.0)


def drop_islands(alpha):
    """Retire les petits îlots isolés du masque (l'IA prend parfois une tache pour le sujet)."""
    solid = (alpha > 0.5).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(solid, connectivity=8)
    if count <= 1:
        return alpha
    min_area = 0.002 * alpha.size
    big = np.zeros(count, bool)
    big[1:] = stats[1:, cv2.CC_STAT_AREA] >= min_area
    if not big.any():
        big[1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))] = True
    r = max(3, int(max(alpha.shape) / 150))
    zone = cv2.dilate(big[labels].astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1,) * 2))
    return alpha * zone


def stain_mask(img, plate, alpha, long_side):
    """Taches du fond (0..1, adouci) : zones qui s'écartent de la plaque propre, hors sujet.

    Les cheveux et les ombres collés au sujet sont gardés.
    """
    low = gaussian(img, max(1.5, long_side / 1500))
    dev = np.abs(low - plate).max(axis=2)
    bg = alpha < 0.02
    if not bg.any():
        return np.zeros_like(alpha)
    thr = max(0.008, 2.5 * float(np.median(dev[bg])))
    raw = ((dev > thr) & bg).astype(np.uint8)

    raw = cv2.morphologyEx(raw, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))  # enlève le bruit isolé

    count, labels, stats, _ = cv2.connectedComponentsWithStats(raw, connectivity=8)
    if count <= 1:
        return np.zeros_like(alpha)
    near = max(3, int(long_side / 400))
    subject = cv2.dilate((alpha > 0.3).astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * near + 1,) * 2))
    touching = np.zeros(count, bool)
    touching[np.unique(labels[(subject > 0) & (raw > 0)])] = True

    # Parmi les zones collées au sujet, on efface quand même les petites taches épaisses :
    # les mèches de cheveux sont trop fines pour survivre à l'ouverture, les ombres trop grandes.
    k = max(3, int(long_side / 700) | 1)
    thick = cv2.morphologyEx(raw, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))
    is_thick = np.zeros(count, bool)
    is_thick[np.unique(labels[thick > 0])] = True
    small = stats[:, cv2.CC_STAT_AREA] < (long_side / 40) ** 2

    remove = ~touching | (small & is_thick)
    remove[0] = False
    stains = remove[labels].astype(np.uint8)

    grow = max(3, int(long_side / 300))
    stains = cv2.dilate(stains, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * grow + 1,) * 2))
    return np.clip(gaussian(stains.astype(np.float32), grow * 0.5), 0.0, 1.0)


def clean_background(img, alpha, force=1.0, protect=0.5):
    """img : float32 RGB 0..1 ; alpha : float32 0..1 (1 = sujet)."""
    h, w = alpha.shape
    long_side = max(h, w)

    # --- Plaque de fond propre, calculée en basse résolution ---
    scale = WORK_SIZE / long_side
    sw, sh = max(1, round(w * scale)), max(1, round(h * scale))
    small = cv2.resize(img, (sw, sh), interpolation=cv2.INTER_AREA)
    a_small = cv2.resize(alpha, (sw, sh), interpolation=cv2.INTER_AREA)

    k = max(3, int(WORK_SIZE * 0.012) | 1)
    subject = cv2.dilate((a_small > 0.05).astype(np.uint8), np.ones((k, k), np.uint8))
    weight = 1.0 - subject.astype(np.float32)

    sigma = WORK_SIZE / 45 * force
    plate = weighted_blur(small, weight, sigma)
    # 2e passe : on ignore les taches (pixels trop différents de la plaque).
    for _ in range(2):
        dev = np.abs(small - plate).max(axis=2)
        bg_dev = dev[weight > 0]
        thr = max(0.02, 2.5 * float(np.median(bg_dev)) if bg_dev.size else 0.05)
        plate = weighted_blur(small, weight * (dev < thr), sigma)

    plate = cv2.resize(plate, (w, h), interpolation=cv2.INTER_CUBIC)

    # --- Détection des taches en pleine résolution ---
    stains = stain_mask(img, plate, alpha, long_side)

    # --- Grain fin d'origine, écrêté, et retiré sur les taches pour ne pas les faire revenir ---
    grain_sigma = max(1.0, long_side / 3000)
    detail = img - gaussian(img, grain_sigma)
    bg = alpha < 0.05
    ref = np.abs(detail[bg]) if bg.any() else np.abs(detail)
    limit = 3.0 * float(np.median(ref)) + 1e-4
    plate = plate + np.clip(detail, -limit, limit) * (1.0 - stains[..., None])

    # --- Masque de remplacement : tout le fond, avec une marge douce autour du sujet ---
    margin = max(3, int(long_side * 0.008 * protect))
    grown = cv2.dilate((alpha > 0.03).astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * margin + 1,) * 2))
    keep = gaussian(np.maximum(grown.astype(np.float32), alpha), margin * 0.8)
    # Les taches isolées dans la marge sont quand même effacées.
    keep = keep * (1.0 - stains)
    keep = np.maximum(keep, alpha)[..., None]

    out = img * keep + plate * (1.0 - keep)
    return np.clip(out, 0.0, 1.0)


def load(path):
    im = Image.open(path)
    im = ImageOps.exif_transpose(im)
    info = {"icc_profile": im.info.get("icc_profile"), "exif": im.info.get("exif")}
    return np.asarray(im.convert("RGB")), info


def save(path, rgb8, info):
    kwargs = {}
    if info.get("icc_profile"):
        kwargs["icc_profile"] = info["icc_profile"]
    suffix = path.suffix.lower()
    if suffix in (".jpg", ".jpeg"):
        kwargs.update(quality=97, subsampling=0)
        if info.get("exif"):
            kwargs["exif"] = info["exif"]
    Image.fromarray(rgb8).save(path, **kwargs)


def collect(inputs):
    files = []
    for p in map(Path, inputs):
        if p.is_dir():
            files += sorted(f for f in p.iterdir() if f.suffix.lower() in EXTENSIONS and not f.name.startswith("."))
        elif p.suffix.lower() in EXTENSIONS:
            files.append(p)
    return files


def main():
    parser = argparse.ArgumentParser(description="Nettoie le fond des photos (façon Evoto).")
    parser.add_argument("inputs", nargs="+", help="photos ou dossiers de photos")
    parser.add_argument("-o", "--output", help="dossier de sortie (défaut : sous-dossier « Nettoyé »)")
    parser.add_argument("--force", type=float, default=1.0, help="intensité du lissage (0.5 = léger, 2 = très lisse)")
    parser.add_argument("--marge", type=float, default=0.5, help="marge protégée autour du sujet (1 = plus large, protège mieux les cheveux)")
    parser.add_argument("--modele", default="isnet-general-use", help="modèle rembg de détourage")
    args = parser.parse_args()

    files = collect(args.inputs)
    if not files:
        sys.exit("Aucune photo trouvée (jpg, png, tif, webp).")

    from rembg import new_session

    print("Chargement de l'IA de détourage (le premier lancement télécharge le modèle)...")
    session = new_session(args.modele)

    for i, path in enumerate(files, 1):
        out_dir = Path(args.output) if args.output else path.parent / "Nettoyé"
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / path.name
        print(f"[{i}/{len(files)}] {path.name}", flush=True)
        try:
            rgb8, info = load(path)
            alpha = subject_alpha(rgb8, session)
            result = clean_background(rgb8.astype(np.float32) / 255.0, alpha, args.force, args.marge)
            save(out_path, (result * 255.0 + 0.5).astype(np.uint8), info)
        except Exception as exc:  # une photo ratée ne bloque pas le lot
            print(f"   ERREUR : {exc}", flush=True)

    print("Terminé.")


if __name__ == "__main__":
    main()
