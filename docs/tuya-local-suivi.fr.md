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
| Documentation utilisateur `docs/tuya-local.fr.md` | ✅ |
| Chargement différé dans `autoexec.be` (plantage au démarrage) | ✅ corrigé et documenté |
| **Mémoire** : il reste 34 Ko avec le driver | ⚠️ trop juste pour les 16 endpoints Matter → intégrer le driver au firmware |
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

## Mesures sur la passerelle

| Situation | `Heap` (`Status 4`) |
|---|---|
| Après mise à jour du firmware, avant le driver | 67 Ko |
| 30 s après le démarrage, juste avant de charger le driver | 74 Ko |
| Driver chargé, 12 appareils connectés, aucun endpoint Matter Tuya | **34 Ko** |

Le driver consomme donc environ 40 Ko (74 − 34 ; code compilé en RAM, état des appareils, tampons). Sur
l'hôte 64 bits, le seul code compilé du driver occupe 36 Ko ; sur l'ESP32, compter environ
20 à 25 Ko. Il n'y a pas eu de mesure après `Br tasmota.gc()`.

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

1. **Intégrer le driver au firmware (solidification)**, pour mettre son code en flash et
   regagner de l'ordre de 15 à 20 Ko de RAM.
   - Piste officielle : l'option `custom_berry_solidify = <URL du .be>` de PlatformIO
     (`pio-tools/solidify-from-url.py`). Elle télécharge le fichier, le solidifie dans
     `lib/libesp32/berry_custom` et l'enregistre dans `be_modtab.c`. Il faut que le fichier
     soit une classe marquée `#@ solidify:TuyaLocal,...` (ou un module), **sans
     instanciation au premier niveau**. L'instanciation passe dans `autoexec.be` (différée,
     comme aujourd'hui).
   - Autre piste : un correctif qui dépose le fichier dans `berry_custom/src/embedded`.
   - Vérifier : compilation, `Heap` avant et après, et que les tests passent toujours. Le
     harnais charge le fichier ; prévoir l'instanciation séparée.
2. **Matter** : créer les endpoints un par un (commencer par `Prise Lisseur` en v.Relay+Power,
   `Ventilateur` en v.Fan, `Entrée-Porche` en v.Light 2 CT), `Restart 1`, puis tester les
   deux sens avec Google Home en surveillant `Heap`.
3. **Réduire la RAM du driver** si besoin :
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
| `/tuya_local.be`, `/autoexec.be` | système de fichiers de la passerelle | driver et chargement différé |

Pour reprendre le développement, demander à Guillaume les fichiers dont la tâche a besoin.
Ne jamais les committer.
