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
| `OTA_URL` | firmware officiel | vide |
| Fichiers du CC2652 dans le FS | oui | non |

L'image avec Matter fait environ 1,85 Mo : elle ne tient pas dans les 1856 Ko du build
officiel. Elle suppose un module déjà en disposition safeboot (`safeboot` 832K, `app0`
2880K, `spiffs` 320K), ce que l'on peut vérifier dans la console Berry :

```berry
import partition_core
for s: partition_core.Partition().slots print(s.label, s.sz / 1024) end
```

`OTA_URL` est vide pour qu'un clic sur « Start upgrade » ne remplace pas ce firmware par
la version officielle sans Matter.

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

Les commandes HTTP (`/cm?cmnd=...`) exigent un en-tête `Referer` tant que
`SetOption128` est actif.
