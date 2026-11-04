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

GitHub sert toujours la dernière release (ni brouillon, ni pré-release) à une adresse fixe,
que le module télécharge en HTTPS en suivant la redirection de GitHub :

```
https://github.com/gnatali/tasmota-zbbridge-matter/releases/latest/download/tasmota32-zbbrdgpro-matter.bin
```

Une fois, dans la console : `OtaUrl 1` (rétablit l'`OTA_URL` compilé ci-dessus ; un
firmware antérieur à cette version n'en a pas : saisir alors l'adresse complète,
`OtaUrl https://github.com/...`). Ensuite **Firmware Upgrade → Start upgrade**, ou
`Upgrade 1` dans la console, installe la dernière release.

Avec la disposition safeboot, `Upgrade 1` redémarre le module sur la partition `safeboot`,
qui télécharge ce `.bin`, l'écrit dans `app0` puis redémarre sur le nouveau firmware.
Les réglages (Zigbee, Matter, Wi-Fi) sont conservés.

## Dépannage : Zigbee ne démarre pas

Symptôme dans la console :

```
ETH: Ethernet using RMII
ZIG: rebooting ZNP device
ZIG: timeout, goto label 99
RSL: RESULT = {"ZbState":{"Status":99,"Message":"Abort"}}
```

et `ZbInfo` répond `{"Command":"Unknown"}`.

Le CC2652P ne répond pas parce que le pilote Ethernet a pris ses broches. Sur l'ESP32,
l'Ethernet RMII utilise des broches fixes (GPIO19, 21, 22, 25, 26, 27). Or le TX Zigbee du
ZBBridge Pro est sur GPIO19 et sa broche BSL sur GPIO22. Le module n'a pas de port
Ethernet. Tasmota ne démarre l'Ethernet que si le modèle (*template*) déclare une broche
`ETH MDC` ou `ETH MDIO` : la ligne `ETH: Ethernet using RMII` indique que le modèle
actif n'est pas celui du ZBBridge Pro.

Correction, dans la console :

```
Ethernet 0
```

(le module redémarre). Mieux, rétablir aussi le modèle officiel du ZBBridge Pro
(celui de `Sonoff_ZBPro.autoconf`) :

```
Backlog Template {"NAME":"Sonoff Zigbee Pro","GPIO":[0,0,576,0,480,0,0,0,0,1,1,5792,0,0,0,3552,0,320,5793,3584,0,640,608,32,0,0,0,0,0,1,0,0,0,0,0,0],"FLAG":0,"BASE":1}; Module 0
```

Au redémarrage, la ligne `ETH:` doit disparaître, et on doit voir `ZIG: Zigbee started`.

## Remarques

Les commandes HTTP (`/cm?cmnd=...`) exigent un en-tête `Referer` tant que
`SetOption128` est actif.
