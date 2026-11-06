---
paths:
  - "berry/**"
  - "**/*.be"
---
# Pièges connus (Berry sous Tasmota)

- Tasmota compile en **mode strict** (`comp_set_strict`) : dans une fonction ou un bloc, une
  affectation à un nom non déclaré est une erreur (`strict: no global 'x', did you mean 'var x'?`).
  Déclarer avec `var`, et créer une globale depuis une fonction avec `import global` puis
  `global.x = ...`. Au premier niveau du fichier chargé, `x = ...` reste permis et crée une
  globale (c'est ce que fait la dernière ligne du driver). Tester un fichier avec
  `import strict` en tête dans l'interpréteur de test.
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
