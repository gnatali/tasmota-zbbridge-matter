---
paths:
  - "platformio_override.ini"
  - "user_config_override.h"
  - "patches/**"
  - ".github/**"
---
# Build du firmware

- Uniquement sur GitHub Actions, **pas en local** (toolchain lourde). Déclencheurs : tag `v*`
  (crée aussi la release) et lancement manuel. **Une PR ne déclenche rien** : lancer le build
  sur une branche avec
  `gh api -X POST repos/gnatali/tasmota32-zbgw03-matter/actions/workflows/build.yml/dispatches -f ref=<branche>`.
  L'API GraphQL n'est pas disponible depuis Claude Code : passer par `gh api` (REST) pour les PR.
- Le firmware est dans l'artefact `firmware` de l'exécution (`tasmota32-zbgw03-matter.bin`
  pour une mise à jour, `.factory.bin` pour un premier flash).
- Avant d'ajouter un correctif : vérifier qu'il s'applique sur `TASMOTA_REF` **avec les
  correctifs existants** (`git apply --check`), et commencer le fichier par un en-tête en
  commentaire qui explique pourquoi.
