---
paths:
  - "berry/**"
  - "**/*.be"
---
# Pièges connus (Berry sous Tasmota)

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
