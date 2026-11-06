---
paths:
  - "berry/**"
---
# Tests du driver Tuya

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
