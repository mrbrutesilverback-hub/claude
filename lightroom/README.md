# Nettoyage Fond — plugin Lightroom Classic

Lisse le fond (mur taché, plinthe, sol) de toutes les photos sélectionnées en un seul clic.
Pour chaque photo, le plugin crée un masque IA **« Sélectionner l'arrière-plan »**, recalculé sur
chaque image, puis y applique les réglages suivants (modifiables dans la fenêtre) :

| Réglage            | Défaut |
|--------------------|--------|
| Exposition         | +0,30  |
| Texture            | -100   |
| Clarté             | -100   |
| Netteté            | -100   |
| Réduction du bruit | +80    |
| Saturation         | -40    |

Tes derniers réglages sont mémorisés pour la prochaine utilisation.

## Prérequis

Lightroom Classic **13 ou plus récent** (l'API de masquage des plugins n'existe pas avant).

## Installation

1. Copie le dossier `NettoyageFond.lrplugin` où tu veux sur ton ordinateur (par ex. dans Documents).
2. Dans Lightroom Classic : **Fichier → Gestionnaire de modules externes** (Plug-in Manager).
3. Clique sur **Ajouter**, puis choisis le dossier `NettoyageFond.lrplugin`.
4. Vérifie que le plugin est marqué « Installé et en cours d'exécution ».

## Utilisation

1. Dans la Bibliothèque ou le Développement, sélectionne toutes les photos (Ctrl/Cmd + A).
2. **Fichier → Modules externes → Lisser l'arrière-plan des photos sélectionnées…**
   (aussi dans **Bibliothèque → Modules externes**).
3. Ajuste les curseurs si besoin, puis clique sur **Appliquer**.
4. Ne touche pas à Lightroom pendant le traitement : le plugin fait défiler les photos une à une
   dans le Développement. Tu peux l'arrêter avec la croix de la barre de progression.

**Conseil :** teste d'abord sur 2 ou 3 photos, et vérifie le rendu avant de lancer tout le shooting.

## Options

- **Nombre de passes** : `2` empile deux masques identiques pour doubler l'effet.
- **Attente IA** : temps laissé à Lightroom pour calculer le masque. Si certaines photos
  n'ont pas d'effet, augmente cette valeur (3 à 5 s).

## Annuler

Chaque photo garde l'historique des modifications. Pour tout enlever, supprime le masque
« Arrière-plan » dans le panneau Masquage, ou reviens en arrière dans l'Historique. Si tu relances
le plugin sur les mêmes photos, il **ajoute** un masque de plus.

## Limites

- Les taches très marquées (scotch au sol, traces orange) peuvent rester visibles : finis-les
  à l'outil **Supprimer** avec l'IA générative.
- Si le masque déborde sur les cheveux bouclés, retouche-le à la main (**Soustraire → Sujet**).
