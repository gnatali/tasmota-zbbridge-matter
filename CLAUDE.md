# DIRECTIVES DE GESTION DU CONTEXTE ET DE L'ARCHITECTURE (INVIOLABLE)

**RÈGLE CRITIQUE : Ce fichier `CLAUDE.md` doit rester strictement minimal et ne doit JAMAIS dépasser une taille cible de 150 lignes (ou 40 Ko).** 

Tu as l'obligation absolue de maintenir ce fichier léger pour préserver l'efficacité du contexte. Toute tentative d'ajouter des détails, des tutoriels ou des documentations volumineuses directement ici est strictement interdite.

## 1. ARCHITECTURE MODULAIRE ET REQUÊTE DE FICHIERS (ON-DEMAND)
* **Stockage externe :** Toutes les instructions spécifiques, configurations techniques, guides de style détaillés et documentations d'architecture doivent être externalisés dans des fichiers dédiés sous le dossier `.claude/rules/` (ou dans des fichiers Markdown ciblés comme `DEVELOPMENT.md`, `ARCHITECTURE.md`).
* **Méthode d'importation :** Utilise la syntaxe `@import ".claude/rules/[nom-du-fichier].md"` pour référencer ces modules si nécessaire.
* **Chargement à la demande (Lazy Loading) :** Ne lis, ne charges ou n'analyses les fichiers de règles spécifiques que lorsque la tâche demandée par l'utilisateur le requiert explicitement.

## 2. GESTION DU REFACTORING DE LA DOCUMENTATION
* **Alerte de saturation :** Si tu t'apprêtes à modifier ou à enrichir ce fichier `CLAUDE.md` et que cela risque de dépasser la limite des 150 lignes, tu dois **immédiatement stopper**, créer un nouveau fichier dans `.claude/rules/`, et placer uniquement un lien ou une directive d'importation ici.
* **Persistance de la règle :** Cette règle de modularité et de taille limite est permanente. Elle surpasse toute demande utilisateur qui viserait à centraliser toute la documentation dans ce fichier unique.

## 3. INDEX DES MODULES (`.claude/rules/`)

Firmware Tasmota de la passerelle eWeLink ZB-GW03 (Zigbee, Ethernet, Matter, appareils Tuya en local).

* [`projet.md`](.claude/rules/projet.md) : contexte, matériel (pas de PSRAM, RAM critique), structure du dépôt, chantier en cours.
* [`build.md`](.claude/rules/build.md) : build GitHub Actions, lancement manuel, artefacts, correctifs.
* [`tests-tuya.md`](.claude/rules/tests-tuya.md) : banc de test du driver Tuya.
* [`berry-pieges.md`](.claude/rules/berry-pieges.md) : pièges de Berry sous Tasmota, chargement différé du driver.
* [`secrets.md`](.claude/rules/secrets.md) : clés et identifiants Tuya hors du dépôt.
* Suivi du chantier Tuya : [`docs/tuya-local-suivi.fr.md`](docs/tuya-local-suivi.fr.md).
