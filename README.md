# Tasmota ZBBridge Pro : Zigbee + Matter

Firmware Tasmota pour le **Sonoff ZBBridge Pro** (ESP32-D0WD-V3, 4 Mo de flash, sans PSRAM)
qui ajoute **Matter** au build Zigbee officiel `tasmota32-zbbrdgpro`.

Aucun firmware Tasmota officiel ne combine les deux : `tasmota32-zbbrdgpro` a Zigbee sans
Matter, `tasmota32` a Matter sans Zigbee.

## Différences avec le build officiel `tasmota32-zbbrdgpro`

| Réglage | Officiel | Ce dépôt |
|---|---|---|
| Matter (`USE_MATTER_DEVICE`) | non | oui |
| Composant `espressif/mdns` | retiré | conservé (Matter s'annonce en mDNS) |
| Composant `espressif/fb_gfx` (caméra) | conservé | retiré |
| Partitions | `app1856k_fs1344k` | `app2880k_fs320k` (safeboot) |
| `OTA_URL` | firmware officiel | dernière release de ce dépôt |
| Fichiers du CC2652 dans le FS | oui | non |

L'image avec Matter fait environ 2 Mo (1984 Ko) : elle ne tient pas dans les 1856 Ko du build
officiel. Elle suppose un module déjà en disposition safeboot (`safeboot` 832K, `app0`
2880K, `spiffs` 320K), ce que l'on peut vérifier dans la console Berry :

```berry
import partition_core
for s: partition_core.Partition().slots print(s.label, s.sz / 1024) end
```

`OTA_URL` pointe sur la dernière release de ce dépôt, pour qu'un clic sur « Start upgrade »
ne remplace pas ce firmware par la version officielle sans Matter (voir
[Mise à jour OTA](#mise-à-jour-ota-depuis-github)).

## Version de Tasmota

Branche `development`, commit
[`a281cec`](https://github.com/arendst/Tasmota/commit/a281cece518b0031e22f2317ca7dbc530c934da1)
(16.0.0.2, 4 novembre 2026). Le workflow GitHub compile toujours ce commit ; pour suivre
une version plus récente, modifier `TASMOTA_REF` dans `.github/workflows/build.yml`.

## Compilation

### Sur GitHub

- Onglet **Actions** → **Build firmware** → **Run workflow** : le `.bin` est disponible
  dans les artefacts de l'exécution.
- Pousser un tag `v*` publie le `.bin` dans les **Releases** :

  ```bash
  git tag v16.0.0.2-matter1
  git push --tags
  ```

### Sous Windows

Prérequis : Git et Python 3.

```powershell
powershell -ExecutionPolicy Bypass -File .\build-zbbridge-matter.ps1
```

Le script clone Tasmota (`development`) dans `C:\tasmota-build`, installe PlatformIO
dans un environnement Python dédié et compile. Le premier build est long (20 à 40 min) :
`custom_sdkconfig` impose la recompilation des bibliothèques Arduino.

Avec le Python du Microsoft Store, Windows redirige les écritures dans AppData vers le
dossier privé de l'application. Le cache du gestionnaire de composants ESP-IDF y devient
invisible pour git (`git init --bare` échoue avec « unable to get current working
directory ») : le script place donc ce cache dans `C:\tasmota-build\idf-cache` via
`IDF_COMPONENT_CACHE_PATH`.

## Installation

1. Sauvegarder la configuration : **Configuration → Backup**.
2. **Firmware Upgrade → Upgrade by file upload** avec `tasmota32-zbbrdgpro-matter.bin`.
3. Vérifier Zigbee dans la console : `ZbInfo`.
4. Activer Matter : `SetOption151 1`, puis redémarrer.
5. Appairer depuis **Configuration → Matter** (QR code).

Sans PSRAM, Zigbee et Matter laissent peu de mémoire libre : surveiller `Heap` dans
`Status 4`. En cas de redémarrages pendant l'appairage, reflasher le firmware précédent
de la même façon.

## Mise à jour OTA depuis GitHub

Chaque tag `v*` publie dans les **Releases** :

- `tasmota32-zbbrdgpro-matter.bin` : le firmware ;
- `version.json` : `{"tag":"v16.0.0.2-matter2","build":12,...}`, où `build` est le numéro
  d'exécution du workflow, également inscrit dans le nom d'image du firmware
  (`Version` de `Status 2` : `16.0.0.2(zbbrdgpro-matter.12)`).

GitHub sert toujours la dernière release (ni brouillon, ni pré-release) à une adresse fixe,
que le module télécharge en HTTPS en suivant la redirection de GitHub :

```
https://github.com/gnatali/tasmota-zbbridge-matter/releases/latest/download/tasmota32-zbbrdgpro-matter.bin
```

Avec la disposition safeboot, `Upgrade 1` redémarre le module sur la partition `safeboot`,
qui télécharge ce `.bin`, l'écrit dans `app0` puis redémarre sur le nouveau firmware.
Les réglages (Zigbee, Matter, Wi-Fi) sont conservés.

### Mise à jour manuelle en un clic

Une fois, dans la console : `OtaUrl 1` (rétablit l'`OTA_URL` compilé ci-dessus ; un
firmware antérieur à cette version n'en a pas : saisir alors l'adresse complète,
`OtaUrl https://github.com/...`). Ensuite **Firmware Upgrade → Start upgrade**, ou
`Upgrade 1` dans la console, installe la dernière release.

### Mise à jour automatique

Tasmota ne vérifie jamais seul s'il existe une nouvelle version : le script
[`berry/github_ota.be`](berry/github_ota.be) s'en charge.

1. **Outils → Gestion du système de fichiers** : envoyer `github_ota.be`.
2. Dans le même écran, éditer (ou créer) `autoexec.be` et y ajouter :

   ```berry
   load("github_ota.be")
   ```

3. Redémarrer.

Chaque nuit à 3 h 30 (heure locale du module, réglée par `Timezone`), le script lit
`version.json` dans la dernière release et lance `Upgrade 1` si son `build` est supérieur
à celui du firmware installé. Il n'installe jamais une version plus ancienne. Commandes :

| Commande | Effet |
|---|---|
| `OtaCheck` | vérifie maintenant et installe si une version plus récente existe |
| `OtaCheck 0` | vérifie seulement : `{"installed":12,"latest":15,"tag":"...","update":true}` |

Un firmware sans numéro de build (compilé avec `build-zbbridge-matter.ps1`, ou antérieur
à cette version) compte comme le build 0 : il est remplacé par la dernière release à la
vérification suivante. Pour garder une compilation locale, retirer la ligne `load(...)`
de `autoexec.be`. L'heure se change dans la variable `cron` du script.

Publier une nouvelle version revient donc à pousser un tag ; les modules se mettent à
jour la nuit suivante :

```bash
git tag v16.0.0.2-matter2
git push --tags
```

Si une version pose problème, la retirer des Releases (ou la passer en pré-release)
rend « latest » la précédente, mais les modules déjà mis à jour n'y reviennent pas
d'eux-mêmes (pas de retour en arrière) : reflasher alors le `.bin` précédent par
**Upgrade by file upload**.

La vérification télécharge `version.json` en HTTPS, ce qui demande plusieurs dizaines de Ko de mémoire
libre : avec Zigbee et Matter, elle peut échouer si `Heap` est trop bas
(`OTA: version.json inaccessible` dans le journal) ; elle est retentée la nuit suivante.

## Remarques

Les commandes HTTP (`/cm?cmnd=...`) exigent un en-tête `Referer` tant que
`SetOption128` est actif.
