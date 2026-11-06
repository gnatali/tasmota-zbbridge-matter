# CLAUDE.md — tasmota32-zbgw03-matter

Firmware Tasmota maison pour la passerelle **eWeLink ZB-GW03** de Guillaume : Zigbee (EFR32 en
EZSP), Ethernet et **Matter**, plus un driver Berry qui pilote les appareils **Tuya en local**.
Échanges, commentaires, commits et documentation **en français**. Les README existent en
français et en anglais : toute modification de l'un se reporte dans l'autre.

**Chantier en cours** : appareils Tuya en local, branche `tuya-local-crypto`, PR #7. L'état,
les mesures faites sur la passerelle et les prochaines étapes sont dans
[docs/tuya-local-suivi.fr.md](docs/tuya-local-suivi.fr.md) : le lire avant de reprendre.

## Matériel (contraintes qui pèsent sur chaque choix)

- ESP32-D0WD, flash de 4 Mo, **pas de PSRAM**. Partitions : application 2880 Ko, système de
  fichiers 320 Ko (`esp32_partition_app2880k_fs320k.csv`). Firmware actuel : ~1992 Ko, il
  reste ~887 Ko en flash.
- **La RAM est la ressource critique** : ~67 Ko libres avec Zigbee + Matter, ~34 Ko avec en
  plus le driver Tuya et ses 12 appareils. Toute nouveauté se mesure avec `Heap` dans
  `Status 4` (en Ko).

## Dépôt

| Chemin | Rôle |
|---|---|
| `platformio_override.ini` | environnement `tasmota32-zbgw03-matter`, dérivé de `tasmota32-zbbrdgpro` + `USE_MATTER_DEVICE` |
| `user_config_override.h` | options de compilation (EZSP, `USE_BERRY_CRYPTO_AES_CBC`...) |
| `patches/*.patch` | correctifs appliqués sur Tasmota par le workflow (`git apply`), dans l'ordre alphabétique |
| `.github/workflows/build.yml` | build : clone Tasmota au commit `TASMOTA_REF`, tests du driver, correctifs, `pio run` |
| `berry/tuya_local.be` | driver Tuya local (protocoles 3.3/3.4/3.5, passerelle Tuya, pont Matter) |
| `berry/tuya.example.json` | exemple de configuration, **sans clés** |
| `berry/test/` | banc de test du driver (voir plus bas) |
| `docs/tuya-local.fr.md` | doc utilisateur du driver |
| `docs/tuya-local-suivi.fr.md` | suivi du chantier Tuya |

## Build

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

## Tests du driver Tuya

```bash
# Tasmota au commit du workflow (un clone partiel suffit)
git clone --filter=blob:none --no-checkout https://github.com/arendst/Tasmota.git tasmota && cd tasmota
git sparse-checkout set --no-cone 'lib/libesp32/berry/*' 'lib/libesp32/re1.5/*' \
  'lib/libesp32/berry_mapping/*' 'lib/libesp32/berry_int64/*' 'lib/libesp32/berry_custom/*' \
  'lib/lib_ssl/bearssl-esp8266/*'
git checkout <TASMOTA_REF du workflow> && cd ..
bash berry/test/run_tests.sh tasmota     # ecrit /tuya.json : conteneur ou CI uniquement
```

- `run_tests.sh` compile l'interpréteur Berry de Tasmota avec `testcrypto.c` (AES-CBC, AES-GCM
  avec AAD, HMAC-SHA256, MD5 sur le BearSSL de Tasmota). `crypto.be` reproduit l'API du module
  `crypto` de Tasmota, et `harness.be` simule `tasmota` et `tcpclientasync`, piloté par
  `test_tuya_local.py` ligne à ligne.
- Les faux appareils (`fake_tuya.py`) sont construits sur **TinyTuya**, et ont été validés
  contre le vrai client TinyTuya. C'est la référence du protocole : en cas de doute,
  comparer au source de TinyTuya (`tinytuya/core/XenonDevice.py`, `message_helper.py`).
- Toute évolution du driver vient avec un scénario de test. Le workflow lance les tests
  avant la compilation.

## Pièges connus (Berry sous Tasmota)

- Tasmota compile en **mode strict** (`comp_set_strict`) : pas de variable globale implicite
  (`global.x` ou une affectation de premier niveau dans le fichier chargé). Tester un fichier
  avec `import strict` en tête dans l'interpréteur de test.
- Entiers sur **32 bits** et flottants en **simple précision** : un compteur d'énergie
  divisé en flottant perd des décimales. Le driver formate les mesures en décimal exact à
  partir de l'entier (`TuyaLocal.scaled`).
- `bytes .. bytes` **ajoute en place** et modifie l'opérande de gauche ; `+` crée un nouvel
  objet.
- Dans une f-string, pas d'opérateur `!=` ou `=` entre accolades (`{x=}` sert au débogage) :
  calculer la valeur dans une variable d'abord.
- `crypto.AES_GCM(cle, iv [, aad])` : clé de 16 ou 32 octets **grâce au correctif** de ce
  dépôt ; un seul `encrypt` ou `decrypt` par instance dans le module de test.
- `tcpclientasync.connected()` renvoie `nil` pendant la connexion, puis `true` ou `false`.
- **Ne jamais charger le driver directement dans `autoexec.be`** : sans PSRAM, le charger
  pendant le démarrage de Zigbee et Matter fait planter l'ESP32. Après 4 plantages rapides,
  la protection anti-boucle démarre **sans Berry, donc sans Matter**, et **désactive toutes
  les règles**. Charger 30 s après le démarrage (voir `docs/tuya-local.fr.md`).
  `SetOption153 1` désactive `autoexec.be`.

## Secrets

Les clés locales Tuya (`key`), les identifiants (`id`, `node_id`/`cid`) et le vrai
`tuya.json` **ne vont jamais dans le dépôt** (`.gitignore` couvre `tuya.json`). Ils restent sur
le PC de Guillaume (`devices.json` et `snapshot.json` de TinyTuya) et sur la passerelle
(`/tuya.json`). Avant chaque commit qui touche `berry/` ou `docs/`, vérifier qu'aucune clé ni
aucun identifiant réel n'y figure. Les tests utilisent des valeurs fictives.
