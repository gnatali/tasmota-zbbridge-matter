# Suivi du chantier : appareils Tuya en local

Dernière mise à jour : **6 novembre 2026**. Branche `tuya-local-crypto`, PR #7 (non fusionnée).

## Objectif

Piloter depuis la ZB-GW03, **sans le cloud Tuya et sans flasher les appareils**, les appareils
Tuya Wi-Fi et les sous-appareils Zigbee de la passerelle Tuya, et les présenter à **Matter**
(Google Home). C'est l'équivalent de LocalTuya pour Home Assistant, mais sur la passerelle.

## État

| Étape | État |
|---|---|
| Crypto Berry : `USE_BERRY_CRYPTO_AES_CBC` + correctif `berry-aes-gcm-128-aad.patch` | ✅ compilé, en service sur la passerelle |
| Driver `berry/tuya_local.be` : protocoles 3.3 / 3.4 / 3.5, passerelle Tuya (`cid`) | ✅ **testé sur les vrais appareils** : 5 appareils Wi-Fi et 7 sous-appareils connectés, valeurs correctes |
| Banc de test (12 scénarios) dans le workflow | ✅ passe en CI |
| **Solidification du driver** (`custom_berry_solidify`, correctif `berry-solidify-all-classes.patch`) | ✅ banc de test : 12/12 sur le driver source **et** sur le driver solidifié ; ✅ build du firmware (2015 Ko) ; ✅ sur la passerelle : **48 Ko libres avec les 12 appareils connectés** (34 Ko avant), le driver consomme ~23 Ko au lieu de ~40 |
| Documentation utilisateur `docs/tuya-local.fr.md` | ✅ |
| Chargement différé dans `autoexec.be` (plantage au démarrage) | ✅ corrigé et documenté |
| **Mémoire** avec les 12 appareils connectés : 34 Ko libres avec le driver chargé depuis le système de fichiers, **48 Ko** avec le driver solidifié | ✅ ~14 Ko de marge en plus ; coût des endpoints Matter à mesurer |
| Endpoints Matter et essais dans Google Home | ⏳ pas commencé |
| Pergola 1 et 2 (projecteurs RGB) | ⏳ absentes du scan : IP et version inconnues, désactivées dans `tuya.json` |
| Migration des contrôleurs LED Zigbee Bureau et Salon sur la ZB-GW03 | ⏳ décidée, pas faite |

## Historique

1. **Recherche** : aucun équivalent de LocalTuya n'existe pour Tasmota. Le protocole est décrit par
   TinyTuya (`PROTOCOL.md`). Le Berry de Tasmota avait le TCP, MD5 et HMAC-SHA256, mais ni
   l'AES-ECB (`AES_CBC` existe, mais doit être activé à la compilation) ni l'AES-128-GCM avec
   AAD (`AES_GCM` n'acceptait que des clés de 32 octets, sans AAD).
2. **Scan** des appareils (`tinytuya scan`) : deux en 3.3, trois en 3.5. Il y a aussi 9
   appareils Zigbee sur la passerelle Tuya.
3. **Décision** : la passerelle Tuya garde ses sous-appareils, pilotés à travers elle. Seules
   les lumières Zigbee (contrôleurs LED Bureau et Salon) seront migrées sur la ZB-GW03.
4. **Crypto** : correctif `AES_GCM` (clés de 16 octets, 4ᵉ argument AAD optionnel), vérifié
   contre la bibliothèque `cryptography` (40 cas), puis option `AES_CBC`.
5. **Driver et banc de test**, puis PR #7. Le workflow (lancé à la main) passe : 12/12 tests,
   firmware de 1992 Ko.
6. **Sur la passerelle** : `load("tuya_local.be")` directement dans `autoexec.be` a fait
   planter l'ESP32 au démarrage. Après 4 plantages, la protection anti-boucle a démarré sans
   Berry (`Br` → `Unknown`, `/bc` introuvable, Matter absent) et a désactivé les règles.
   Correction : chargement 30 s après le démarrage, s'il reste au moins 60 Ko. Depuis, tout
   fonctionne.
7. **Solidification** (étape 1 ci-dessous) : le driver est intégré au firmware par
   `custom_berry_solidify = ../berry/tuya_local.be`. Ce qu'il a fallu changer :
   - le script de Tasmota (`pio-tools/solidify-from-url.py`) n'enregistrait dans
     `be_modtab.c` que la **première** classe d'un fichier : correctif
     `berry-solidify-all-classes.patch`, pour les cinq classes du driver ;
   - une classe solidifiée est en lecture seule : la table CRC, calculée au premier appel
     dans une `static var`, est remplacée par une table constante de 16 entrées (CRC par
     quartet, vérifiée contre `zlib.crc32` et la valeur de référence `0xCBF43926`) ;
   - plus de code au premier niveau : imports dans les méthodes, instanciation dans
     `autoexec.be` (`global.tuya_local = TuyaLocal()`), qui charge encore `tuya_local.be`
     si le firmware ne contient pas le driver ;
   - le banc de test solidifie le driver comme le build (`berry_port`, `coc`) et rejoue les
     12 scénarios sur les classes natives. Le C généré fait ~206 Ko de source.
   - **Build** (exécution 11, commit `df4ed7d`) : firmware de 2 063 295 octets (2015 Ko,
     +22,8 Ko), soit exactement la hausse de `.rodata` (676 464 → 699 280 octets). La RAM
     statique ne bouge pas (DRAM 65 948 → 65 980 octets, +32). Il reste ~865 Ko en flash.

## Mesures sur la passerelle

| Situation | `Heap` (`Status 4`) |
|---|---|
| Après mise à jour du firmware, avant le driver | 67 Ko |
| 30 s après le démarrage, juste avant de charger le driver | 74 Ko |
| Driver chargé, 12 appareils connectés, aucun endpoint Matter Tuya | **34 Ko** |
| **Driver solidifié** (firmware 2015 Ko, 6 novembre) : juste avant de démarrer le driver | 71 Ko |
| **Driver solidifié** : driver démarré, 3 appareils connectés | 61 Ko |
| **Driver solidifié** : driver démarré, **12 appareils connectés** (endpoint Matter `Entrée-Porche` créé) | **48 Ko** |

Avec les 12 appareils connectés, le driver consommait environ **40 Ko** chargé depuis le
système de fichiers (74 − 34 : code compilé en RAM, état des appareils, tampons), et environ
**23 Ko** solidifié (71 − 48 : état et tampons seulement). La solidification a donc retiré
**~17 Ko** de code de la RAM ; il reste **48 Ko libres au lieu de 34** (+14 Ko, le heap de
départ étant 3 Ko plus bas : 71 contre 74 Ko). L'état seul coûte ~23 Ko pour 12 appareils,
soit ~2 Ko par appareil en moyenne : il croît avec le nombre d'appareils connectés et de DP
reçus (pince : 22 DP, passerelle : 7 sous-appareils). Avec 3 appareils, 10 Ko (71 → 61).
Les 48 Ko incluent l'endpoint Matter `Entrée-Porche`. Il n'y a pas eu de mesure après
`Br tasmota.gc()`.

## Inventaire (sans clés ni identifiants : voir `tuya.json` sur la passerelle)

**Appareils Wi-Fi**

| Appareil | Protocole | Rôle dans `tuya.json` |
|---|---|---|
| Ventilateur | 3.5 | `fan` (DP 60/62, vitesses 1-6) + `light0` (DP 20) |
| Récepteur radio (4 canaux 433 MHz) | 3.5 | 4 × `relay` (DP 1 à 4) |
| Entrée-Porche (ampoule LSC CCT) | 3.3 | `light2` (DP 20/21/22/23) |
| A:Eau B:Chfg C:Cuisine (pince 3 circuits) | 3.5 | `sensors` : tension, courant, puissance et énergie par circuit et au total |
| Gateway (passerelle Zigbee Tuya) | 3.3 | porte les sous-appareils |
| Pergola 1, Pergola 2 (projecteurs LSC RGB) | ? | `light3` (DP 20/21/22/24), `"enabled": false` |

**Sous-appareils Zigbee de la passerelle Tuya** : luminaires terrasse, Prise Lisseur et Relais
zigbee Cuisine (`relay_power`, DP 1/18/19/20) ; Interrupteur Terrasse et Chauffage
(`relay`) ; Temperature SdB (`temp` DP 1 et `humidity` DP 2, diviseur 10) ; Capteur de
température et d'humidité (`temp` DP 103 et `humidity` DP 101, diviseur 100).

**À migrer sur la ZB-GW03** : contrôleurs LED Bureau et Salon (E2-ZR), qui passeront en
endpoints Matter `z_light2` ou `z_light1`.

## Prochaines étapes (par priorité)

1. ~~**Solidifier le driver**~~ : fait et mesuré, 48 Ko libres avec les 12 appareils au lieu
   de 34 (voir les mesures). Le seuil de 60 Ko d'`autoexec.be` reste adapté (71 Ko avant le
   démarrage du driver, ~23 Ko consommés ensuite).
2. **Matter** : créer les endpoints un par un (commencer par `Prise Lisseur` en v.Relay+Power,
   `Ventilateur` en v.Fan, `Entrée-Porche` en v.Light 2 CT), `Restart 1`, puis tester les
   deux sens avec Google Home en surveillant `Heap`.
3. **Réduire la RAM du driver** (~23 Ko d'état pour 12 appareils) si les endpoints Matter
   ne laissent pas assez de marge :
   - ne garder dans `dps` que les DP utilisés par une liaison ou un capteur (la pince en
     envoie 22, les prises 11) ;
   - limiter `publish_result` (un message MQTT par changement, la pince en envoie souvent).
4. **Pergola 1 et 2** : les allumer, refaire `tinytuya scan`, renseigner `ip` et `version`,
   puis retirer `"enabled": false`.
5. **Migrer Bureau et Salon** sur la ZB-GW03 (procédure dans `docs/tuya-local.fr.md`).
6. **Fusionner la PR #7** une fois Matter validé, puis créer un tag `v*` pour publier la
   release.

## À vérifier côté passerelle

- `Rule1` : la protection anti-boucle a désactivé les règles. Vérifier que `Rule1 1` a été
  refait (bouton Zigbee « Perron » dans Google Home).
- La cause exacte du plantage n'a pas été relevée (`Status 12` non collecté). Le chargement
  différé suffit, mais si un plantage revient, `Status 12` est la première chose à demander.

## Fichiers hors dépôt

| Fichier | Où | Contenu |
|---|---|---|
| `devices.json`, `snapshot.json` | PC de Guillaume (sortie de `tinytuya wizard` / `scan`) | clés locales, identifiants, IP, versions |
| `/tuya.json` | système de fichiers de la passerelle | configuration réelle, **avec les clés** |
| `/autoexec.be` | système de fichiers de la passerelle | démarrage différé du driver (`/tuya_local.be` n'est plus nécessaire avec le driver solidifié) |

Pour reprendre le développement, demander à Guillaume les fichiers dont la tâche a besoin.
Ne jamais les committer.
