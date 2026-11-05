# Tasmota pour l'eWeLink ZB-GW03 : Zigbee + Matter

**Français** · [English](README.md)

Firmware Tasmota pour la passerelle Zigbee **eWeLink ZB-GW03**. Un seul build fait tourner
**Zigbee** (coordinateur, protocole EZSP) et **Matter** : la passerelle s'appaire avec
Google Home, Apple Maison, Home Assistant ou tout autre contrôleur Matter.

Aucun firmware Tasmota officiel n'a les deux : `tasmota32-zbbrdgpro` a Zigbee sans Matter,
`tasmota32` a Matter sans Zigbee.

Deux variantes sont fournies : le firmware **complet** (`tasmota32-zbgw03-matter`) et une
version **lite** (`tasmota32-zbgw03-matter-lite`), réduite à Zigbee, Matter et aux actions
directes entre appareils, pour laisser plus de mémoire libre. Voir [Version lite](#version-lite).

## Sommaire

- [Matériel](#matériel)
- [Différences avec le build officiel](#différences-avec-le-build-officiel)
- [Version lite](#version-lite)
- [Téléchargement](#téléchargement)
- [Première installation par le port série](#première-installation-par-le-port-série)
- [Mise à jour depuis un Tasmota existant](#mise-à-jour-depuis-un-tasmota-existant)
- [Configuration](#configuration)
- [Mise à jour OTA](#mise-à-jour-ota)
- [Compilation](#compilation)
- [Dépannage](#dépannage)
- [Crédits et licence](#crédits-et-licence)

## Matériel

| Élément | Composant |
|---|---|
| Microcontrôleur | ESP32-D0WD-V3, 4 Mo de flash, sans PSRAM |
| Zigbee | Module EFR32MG21 (Silicon Labs, firmware EmberZNet, protocole EZSP) |
| Ethernet | Puce LAN8720 (RMII) |
| Divers | EEPROM I2C en 0x50, bouton, 2 LED |

Testé sur une carte **ZB-GW03 v1.4** (révision gravée sur le circuit), avec EmberZNet
6.7.10.0 (EZSP v8) et Google Home comme contrôleur Matter.

Le ZB-GW03 n'est **pas** un Sonoff ZBBridge Pro. Le ZBBridge Pro a un CC2652P (Texas
Instruments, protocole ZNP) ; le ZB-GW03 a un EFR32MG21 (protocole EZSP), câblé sur d'autres
broches. Tasmota ne compile qu'un des deux protocoles : un firmware de ZBBridge Pro ne peut
pas dialoguer avec le module Zigbee du ZB-GW03.

## Différences avec le build officiel

Ce build part de l'environnement officiel `tasmota32-zbbrdgpro` et modifie :

| Réglage | Officiel `tasmota32-zbbrdgpro` | Ce dépôt |
|---|---|---|
| Protocole Zigbee | ZNP (CC2652P) | EZSP (EFR32MG21) |
| Matter (`USE_MATTER_DEVICE`) | non | oui |
| Composant `espressif/mdns` | retiré | conservé (Matter s'annonce en mDNS) |
| Composant `espressif/fb_gfx` (caméra) | conservé | retiré |
| Partitions | `app1856k_fs1344k` | `app2880k_fs320k` (safeboot) |
| `OTA_URL` | firmware officiel | dernière release de ce dépôt |
| Firmware et flasheur du CC2652P dans le système de fichiers | oui | non (inutiles sur l'EFR32) |
| Date des événements Matter (appuis de bouton) | secondes sur 32 bits | millisecondes sur 64 bits, comme le veut Matter (voir [Bouton Zigbee dans Google Home](#bouton-zigbee-dans-google-home)) |

Avec Matter, l'image fait environ 2 Mo (environ 1990 Ko). Elle ne tient pas dans les 1856 Ko
de la disposition officielle, d'où la disposition **safeboot** : `safeboot` 832 Ko, `app0`
2880 Ko, `spiffs` 320 Ko. Sur un module qui a déjà Tasmota, on la vérifie dans la console
Berry :

```berry
import partition_core
for s: partition_core.Partition().slots print(s.label, s.sz / 1024) end
```

## Version lite

`tasmota32-zbgw03-matter-lite` s'adresse à une passerelle qui ne fait que **Zigbee**,
**Matter** et des **actions directes entre appareils**, en **Wi-Fi**. Sans PSRAM, chaque
fonction retirée rend un peu de mémoire à Zigbee et Matter.

| Conservé | Retiré |
|---|---|
| Zigbee (EZSP), y compris `ZbBind` | Ethernet (Wi-Fi seulement) |
| Matter (mDNS, IPv6) | Émulation Hue et WeMo (Alexa) |
| Règles (`Rule1 on ZbReceived#... do ...`) | Minuteries (Timers) et lever/coucher du soleil |
| Device Groups (`DevGroupSend`) | Extensions MQTT : déclencheurs de règles sur des sujets MQTT, découverte Tasmota (le client MQTT lui-même fait partie du cœur de Tasmota) |
| Interface web, Berry, client HTTPS | Autoconf et gestionnaire d'extensions |
| Mise à jour OTA (vers la version lite) | InfluxDB, pont TCP (ZHA ou Zigbee2MQTT par TCP), I2C et ses capteurs, SPI |
| | Pilotes de matériel absent du ZB-GW03 : rubans de LED et puces d'éclairage, Sonoff RF/SC, Tuya MCU, variateurs PWM, compteurs, DS18x20, DHT, ADC, pont série, visualiseur de GPIO |

Mesuré sur Tasmota 16.0.0.2 : l'image lite fait environ 1780 Ko au lieu d'environ 1990 Ko,
et sa RAM statique est inférieure d'environ 4 Ko (60,4 Ko au lieu de 64,4 Ko). S'y ajoute la
mémoire que les fonctions retirées réservent pendant le fonctionnement (Ethernet, écoute UDP
de Hue/WeMo...) : la vérifier avec `Heap` dans `Status 4`.

Mêmes partitions que le firmware complet : on passe de l'un à l'autre par une simple mise à
jour (envoi de fichier ou OTA), les réglages sont conservés. Les appareils Zigbee sont
enregistrés dans le système de fichiers, pas dans l'EEPROM I2C : retirer l'I2C ne les perd
pas.

Le firmware complet reste celui à utiliser pour l'Ethernet, les minuteries, Home Assistant
par MQTT ou Alexa.

Sans MQTT, lancer aussi `SetOption3 0` (désactive MQTT) : le module arrête de chercher à se
connecter à un broker.

## Téléchargement

La [dernière release](https://github.com/gnatali/tasmota32-zbgw03-matter/releases/latest)
fournit :

| Fichier | Usage |
|---|---|
| `tasmota32-zbgw03-matter.factory.bin` | Firmware complet : première installation par le port série, écrite à l'adresse `0x0` (bootloader, table de partitions, safeboot et firmware) |
| `tasmota32-zbgw03-matter.bin` | Firmware complet : mise à jour d'un module qui a déjà Tasmota en disposition safeboot (envoi de fichier ou OTA) |
| `tasmota32-zbgw03-matter-lite.factory.bin` | [Version lite](#version-lite) : première installation par le port série |
| `tasmota32-zbgw03-matter-lite.bin` | Version lite : mise à jour (envoi de fichier ou OTA) |

Les releases jusqu'à `v16.0.0.2-matter2` ne contiennent que le `.bin`, et la version lite
n'est que dans les releases suivantes. Chaque exécution du workflow **Build firmware**
(onglet **Actions**) fournit tous les fichiers dans son artefact `firmware` (connexion GitHub
requise, conservé 90 jours).

Les étapes ci-dessous citent les fichiers du firmware complet ; pour la version lite,
prendre les fichiers `-lite`.

## Première installation par le port série

Nécessaire si la passerelle a encore le firmware eWeLink, ou si sa flash n'est pas dans la
disposition safeboot ci-dessus.

1. Ouvrir le boîtier et brancher un adaptateur USB-série 3,3 V (CP2102, CH340...) sur les
   pastilles du port série de l'ESP32 : TX de l'adaptateur → RX de l'ESP32, RX de
   l'adaptateur → TX de l'ESP32, GND → GND. Alimenter si possible la carte par sa propre
   alimentation USB : la sortie 3,3 V des petits adaptateurs est souvent trop faible pour le
   Wi-Fi de l'ESP32 (redémarrages par *brownout*).
2. Relier **IO0** à GND pendant la mise sous tension, pour passer en mode téléchargement.
3. Installer esptool (`pip install esptool`), puis sauvegarder toute la flash (elle contient
   le firmware d'origine) :

   ```bash
   esptool --port /dev/ttyUSB0 --baud 460800 read_flash 0 0x400000 zb-gw03-sauvegarde.bin
   ```

4. Effacer, puis écrire l'image factory (repasser en mode téléchargement avant chaque
   commande si nécessaire) :

   ```bash
   esptool --port /dev/ttyUSB0 erase_flash
   esptool --port /dev/ttyUSB0 --baud 460800 write_flash 0x0 tasmota32-zbgw03-matter.factory.bin
   ```

   Sous Windows, le port s'appelle `COM3`, `COM5`...

5. Couper puis remettre l'alimentation. Tasmota crée un point d'accès Wi-Fi
   `tasmota-XXXXXX-XXXX` : s'y connecter, ouvrir `http://192.168.4.1` et saisir les réglages
   Wi-Fi.
6. Continuer avec [Configuration](#configuration).

## Mise à jour depuis un Tasmota existant

Si le module a déjà Tasmota en disposition safeboot :

1. Sauvegarder la configuration : **Configuration → Backup Configuration**.
2. **Firmware Upgrade → Upgrade by file upload** avec `tasmota32-zbgw03-matter.bin`.
3. Continuer avec [Configuration](#configuration).

## Configuration

### Modèle de broches

Le modèle (*template*) déclare les broches du module Zigbee, l'Ethernet, les LED, le bouton et
l'I2C. Pour la carte **v1.4**, le modèle v1.2 de
[templates.blakadder.com](https://templates.blakadder.com/) fonctionne tel quel (testé) :

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

Pour une autre révision de carte, vérifier le modèle correspondant. **Ne pas** appliquer le
modèle du Sonoff ZBBridge Pro (`Sonoff_ZBPro.autoconf`) : ses broches ne correspondent pas, et
Zigbee ne démarre plus.

### Zigbee

Au démarrage, la console doit afficher :

```
ZIG: Resetting EZSP device
RSL: RESULT = {"ZbState":{"Status":1,"Message":"EFR32 EZSP booted",...}}
RSL: RESULT = {"ZbState":{"Status":55,"Version":"6.7.10.0","Protocol":8,"Stack":2}}
RSL: RESULT = {"ZbState":{"Status":0,"Message":"Started"}}
ZIG: Zigbee started
```

`ZbInfo` liste les appareils connus. `ZbPermitJoin 1` ouvre l'appairage pendant 60 secondes ;
`ZbName` renomme un appareil. Tasmota ne gère que la version 8 du protocole EZSP.

### Ethernet

Firmware complet uniquement : la version lite est en Wi-Fi seulement.

Avec le modèle ci-dessus, `ETH: Ethernet using RMII` au démarrage est normal. `Ethernet 1` /
`Ethernet 0` active ou coupe le port Ethernet (le module redémarre).

Pas encore testé sur la v1.4 : si la liaison ne s'établit pas avec un câble branché, une
configuration ESPHome de la communauté pour la v1.4 utilise l'horloge en sortie sur GPIO17 et
l'adresse PHY 1, soit `Backlog EthType 0; EthAddress 1; EthClockMode 3`.

### Matter

1. Activer Matter : `SetOption151 1`, puis `Restart 1`.
2. Appairer depuis **Configuration → Matter** (QR code ou code d'appairage manuel) avec le
   contrôleur Matter.

Sans PSRAM, Zigbee et Matter laissent environ 70 à 100 Ko de mémoire libre : surveiller
`Heap` dans `Status 4`.

### Bouton Zigbee dans Google Home

Tasmota ne présente pas un bouton Zigbee à Matter, mais il peut créer un **bouton virtuel**
Matter qu'une règle déclenche à chaque appui. Testé avec un Sonoff SNZB-01P et Google Home.

1. Dans la console, appuyer sur le bouton : la ligne `ZbReceived` donne son adresse courte
   (`0x922D` ci-dessous) et la valeur de chaque type d'appui. Pour le SNZB-01P : `Power` 2
   pour un appui simple, 1 pour un double appui, 0 pour un appui long.
2. **Configuration → Matter** : ajouter un appareil de type **v.Generic Switch/Button**,
   nommé par exemple `Perron`.
3. Relier le bouton Zigbee au bouton virtuel :

   ```
   Rule1 on ZbReceived#0x922D#Power=2 do MtrUpdate {"Name":"Perron","Presses":1} endon on ZbReceived#0x922D#Power=1 do MtrUpdate {"Name":"Perron","Presses":2} endon on ZbReceived#0x922D#Power=0 do MtrUpdate {"Name":"Perron","Presses":3} endon
   Rule1 1
   ```

   Le bouton virtuel ne connaît que les appuis répétés (1 à 5) : l'appui long arrive comme un
   triple appui.
4. `Restart 1`, pour que le contrôleur Matter s'abonne au nouveau bouton.
5. Dans Google Home : **Automatisations → Ajouter → Pour la maison**, déclencheur
   **« Interrupteur ou bouton pressé »**, puis le bouton et le type d'appui.

Tasmota date chaque événement Matter en secondes, alors que Matter attend des millisecondes :
un appui semble dater de janvier 1970, et Google Home le reçoit sans lancer l'automatisation.
Ce dépôt corrige ce point (`patches/matter-event-timestamp-ms.patch`), à partir de la release
`v16.0.0.2-matter4`. Avec `WebLog 3`, un appui affiche `MTR: +Add_Event` (événements du
bouton) puis `MTR: <Sub_Data` (envoi au contrôleur).

## Mise à jour OTA

GitHub sert toujours la dernière release (ni brouillon, ni pré-release) à une adresse fixe,
que le module télécharge en HTTPS en suivant la redirection de GitHub :

```
https://github.com/gnatali/tasmota32-zbgw03-matter/releases/latest/download/tasmota32-zbgw03-matter.bin
```

Cette adresse est compilée dans le firmware (`OTA_URL`), pour que **Start upgrade** ne
remplace jamais ce firmware par un firmware officiel sans Matter. Une fois, dans la console :
`OtaUrl 1` (rétablit l'`OTA_URL` compilé). Ensuite **Firmware Upgrade → Start upgrade**, ou
`Upgrade 1` dans la console, installe la dernière release.

Avec la disposition safeboot, `Upgrade 1` redémarre le module sur la partition `safeboot`, qui
télécharge le `.bin`, l'écrit dans `app0` puis redémarre sur le nouveau firmware. Les réglages
(Wi-Fi, modèle, Zigbee, Matter) sont conservés.

La version lite a sa propre adresse, compilée de la même façon : une mise à jour OTA garde la
variante installée.

```
https://github.com/gnatali/tasmota32-zbgw03-matter/releases/latest/download/tasmota32-zbgw03-matter-lite.bin
```

Pour changer de variante par OTA : `OtaUrl` suivi de l'adresse de l'autre variante, puis
`Upgrade 1`. Une fois sur la nouvelle variante, `OtaUrl 1` rétablit sa propre adresse
compilée.

Un module qui a encore un firmware nommé `zbbrdgpro-matter` (release `v16.0.0.2-matter1` et
précédentes) demande un ancien nom de fichier, absent des nouvelles releases. Le mettre à jour
une fois par **Upgrade by file upload**, ou avec
`OtaUrl https://github.com/gnatali/tasmota32-zbgw03-matter/releases/latest/download/tasmota32-zbgw03-matter.bin`
puis `Upgrade 1`.

## Compilation

Le firmware est compilé par GitHub Actions (`.github/workflows/build.yml`) :

- **Actions → Build firmware → Run workflow** compile les deux firmwares ; les fichiers sont dans
  l'artefact `firmware` de l'exécution.
- Pousser un tag `v*` les publie aussi dans une **Release** :

  ```bash
  git tag v16.0.0.2-matter3
  git push --tags
  ```

Le workflow compile un commit fixe de Tasmota : branche `development`, commit
[`a281cec`](https://github.com/arendst/Tasmota/commit/a281cece518b0031e22f2317ca7dbc530c934da1)
(16.0.0.2, 4 novembre 2026). Pour suivre une version plus récente, modifier `TASMOTA_REF` dans
le workflow.

| Fichier | Rôle |
|---|---|
| `platformio_override.ini` | Environnement `tasmota32-zbgw03-matter` : étend `tasmota32-zbbrdgpro`, ajoute Matter, fixe les partitions, l'`OTA_URL` et les composants. Environnement `tasmota32-zbgw03-matter-lite` : idem, sans `FIRMWARE_ZBBRDGPRO`, avec `FIRMWARE_ZBGW03_LITE` |
| `user_config_override.h` | Remplace ZNP par EZSP ; pour la version lite, définit le contenu du firmware (bloc `FIRMWARE_ZBGW03_LITE`). Copié dans `tasmota/` avant la compilation |
| `patches/*.patch` | Correctifs appliqués au code de Tasmota avant la compilation ; le code Berry de Matter est régénéré à partir des sources pendant la compilation |
| `.github/workflows/build.yml` | Clone Tasmota, copie les deux fichiers, applique les correctifs, compile, publie |

Pour compiler en local : cloner Tasmota au même commit, copier `platformio_override.ini` à sa
racine et `user_config_override.h` dans son dossier `tasmota/`, appliquer les correctifs
(`git -C tasmota apply ../patches/*.patch`), puis lancer `pio run -e tasmota32-zbgw03-matter` (complet) ou
`pio run -e tasmota32-zbgw03-matter-lite` (lite).

En changeant `TASMOTA_REF`, vérifier que chaque correctif s'applique encore : le workflow
s'arrête sinon. Un correctif devenu inutile (corrigé dans Tasmota) se supprime.

## Dépannage

| Symptôme | Cause et correction |
|---|---|
| `ZIG: rebooting ZNP device` puis `timeout, goto label 99` | Firmware compilé en ZNP (ZBBridge Pro) : installer ce firmware |
| `ZIG: Resetting EZSP device` puis timeout | Modèle de broches incorrect : appliquer le modèle du ZB-GW03 |
| `WIF: WifiManager active`, adresse `192.168.4.1` | Réglages perdus (par exemple après plusieurs coupures rapides) : se connecter au point d'accès `tasmota-...`, puis restaurer une sauvegarde avec **Configuration → Restore Configuration** |
| Ni réseau, ni LED | Lire le log série à 115200 bauds sur la pastille TX de l'ESP32 |
| Commandes HTTP (`/cm?cmnd=...`) refusées | Envoyer un en-tête `Referer` tant que `SetOption128` est actif |

## Crédits et licence

- [Tasmota](https://github.com/arendst/Tasmota) de Theo Arends et ses contributeurs, publié
  sous licence GNU GPL v3.0 : les firmwares de ce dépôt sont compilés à partir de ses sources,
  avec les fichiers de configuration ci-dessus.
- Modèle du ZB-GW03 : [templates.blakadder.com](https://templates.blakadder.com/).

Ce dépôt est publié sous licence GNU GPL v3.0, comme Tasmota : voir [LICENSE](LICENSE).
