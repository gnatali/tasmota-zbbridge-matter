# Tasmota ZB-GW03 : Zigbee + Matter

Firmware Tasmota pour la passerelle **eWeLink ZB-GW03** (ESP32-D0WD-V3, 4 Mo de flash, sans
PSRAM, Ethernet LAN8720, module Zigbee **EFR32MG21** de Silicon Labs) qui ajoute **Matter**
au build Zigbee `tasmota32-zbbrdgpro`.

Aucun firmware Tasmota officiel ne combine les deux : `tasmota32-zbbrdgpro` a Zigbee sans
Matter, `tasmota32` a Matter sans Zigbee.

Le ZB-GW03 n'est **pas** un Sonoff ZBBridge Pro : celui-ci a un CC2652P (Texas Instruments,
protocole ZNP), le ZB-GW03 un EFR32MG21 (protocole EZSP), câblé sur d'autres broches. Ce
dépôt part du build ZBBridge Pro et passe Zigbee en EZSP (`user_config_override.h`).
L'environnement PlatformIO et le firmware s'appellent `tasmota32-zbgw03-matter`.

## Différences avec le build officiel `tasmota32-zbbrdgpro`

| Réglage | Officiel | Ce dépôt |
|---|---|---|
| Protocole Zigbee | ZNP (CC2652P) | EZSP (EFR32MG21) |
| Matter (`USE_MATTER_DEVICE`) | non | oui |
| Composant `espressif/mdns` | retiré | conservé (Matter s'annonce en mDNS) |
| Composant `espressif/fb_gfx` (caméra) | conservé | retiré |
| Partitions | `app1856k_fs1344k` | `app2880k_fs320k` (safeboot) |
| `OTA_URL` | firmware officiel | dernière release de ce dépôt |
| Firmware et flasheur du CC2652P dans le FS | oui | non (inutiles sur l'EFR32) |

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

- Onglet **Actions** → **Build firmware** → **Run workflow** : le `.bin` est disponible
  dans les artefacts de l'exécution.
- Pousser un tag `v*` publie le `.bin` dans les **Releases** :

  ```bash
  git tag v16.0.0.2-matter1
  git push --tags
  ```

## Installation

1. Sauvegarder la configuration : **Configuration → Backup**.
2. **Firmware Upgrade → Upgrade by file upload** avec `tasmota32-zbgw03-matter.bin`.
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
https://github.com/gnatali/tasmota32-zbgw03-matter/releases/latest/download/tasmota32-zbgw03-matter.bin
```

Un module qui a encore un firmware nommé `zbbrdgpro-matter` (versions `v16.0.0.2-matter1`
et précédentes) télécharge l'ancien nom de fichier, absent des nouvelles releases : le mettre
à jour une fois par **Upgrade by file upload**, ou avec l'adresse complète ci-dessus
(`OtaUrl https://github.com/...`, puis `Upgrade 1`).

Une fois, dans la console : `OtaUrl 1` (rétablit l'`OTA_URL` compilé ci-dessus ; un
firmware antérieur à cette version n'en a pas : saisir alors l'adresse complète,
`OtaUrl https://github.com/...`). Ensuite **Firmware Upgrade → Start upgrade**, ou
`Upgrade 1` dans la console, installe la dernière release.

Avec la disposition safeboot, `Upgrade 1` redémarre le module sur la partition `safeboot`,
qui télécharge ce `.bin`, l'écrit dans `app0` puis redémarre sur le nouveau firmware.
Les réglages (Zigbee, Matter, Wi-Fi) sont conservés.

## Modèle de broches et Ethernet

Le modèle (*template*) doit être celui du ZB-GW03, qui déclare l'Ethernet (LAN8720) et les
broches du module Zigbee. Pour la carte **v1.4** (testé : Zigbee démarre en EZSP), on reprend
celui de la v1.2 de [templates.blakadder.com](https://templates.blakadder.com/) :

```
Backlog Template {"NAME":"ZB-GW03-V1.4","GPIO":[0,0,3552,0,3584,0,0,0,5793,5792,320,544,5536,0,5600,0,0,0,0,5568,0,0,0,0,0,0,0,0,608,640,32,0,0,0,0,0],"FLAG":0,"BASE":1}; Module 0
```

| GPIO | Fonction |
|---|---|
| 2 / 4 | Zigbee TX / RX |
| 13 / 12 | Zigbee Rst 1 (reset) / Rst 2 (bootloader de l'EFR32) |
| 14 / 15 | LED / LED réseau |
| 16 | Alimentation de la puce Ethernet |
| 18 / 23 | Ethernet MDIO / MDC |
| 32 / 33 | I2C SCL / SDA (EEPROM en 0x50) |
| 34 | Bouton |

Pour une autre révision, vérifier le modèle correspondant. **Ne pas**
appliquer le modèle du Sonoff ZBBridge Pro (`Sonoff_ZBPro.autoconf`) : ses broches ne
correspondent pas, et Zigbee ne démarre plus (`ZIG: timeout, goto label 99`).

Avec le bon modèle, `ETH: Ethernet using RMII` au démarrage est normal. `Ethernet 1` /
`Ethernet 0` active ou coupe le port Ethernet (le module redémarre).

Au démarrage, Zigbee doit afficher `ZbState` avec `"Status":55` (version EZSP) puis
`ZIG: Zigbee started`. `ZIG: rebooting ZNP device` indique un firmware compilé en ZNP :
il ne peut pas parler à l'EFR32MG21.

## Remarques

Les commandes HTTP (`/cm?cmnd=...`) exigent un en-tête `Referer` tant que
`SetOption128` est actif.
