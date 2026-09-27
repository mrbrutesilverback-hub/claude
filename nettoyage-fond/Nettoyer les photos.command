#!/bin/bash
# Double-clic : nettoie le fond de toutes les photos d'un dossier (résultat dans « Nettoyé »).
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Library/Application Support/NettoyageFond"
VENV="$APP/venv"

echo "=== Nettoyage Fond ==="

if [ ! -f "$APP/.installe" ]; then
  echo "Première utilisation : installation des outils (5 à 10 minutes, une seule fois)..."
  mkdir -p "$APP"
  UV="$(command -v uv || true)"
  if [ -z "$UV" ]; then
    [ -x "$HOME/.local/bin/uv" ] || curl -LsSf https://astral.sh/uv/install.sh | sh
    UV="$HOME/.local/bin/uv"
  fi
  rm -rf "$VENV"
  "$UV" venv --python 3.12 "$VENV"
  "$UV" pip install --python "$VENV/bin/python" "rembg[cpu]" opencv-python-headless pillow numpy
  touch "$APP/.installe"
fi

FOLDER="$1"
if [ -z "$FOLDER" ]; then
  FOLDER=$(osascript -e 'POSIX path of (choose folder with prompt "Choisis le dossier des photos exportées de Lightroom :")') || exit 0
fi

"$VENV/bin/python" "$DIR/nettoyage_fond.py" "$FOLDER"
open "${FOLDER%/}/Nettoyé"
echo
echo "Fini ! Les photos sont dans le dossier « Nettoyé ». Tu peux fermer cette fenêtre."
