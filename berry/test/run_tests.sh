#!/usr/bin/env bash
# Tests du driver tuya_local.be, hors de la passerelle.
#
# Compile un interpreteur Berry (celui de Tasmota) avec un module crypto natif sur le BearSSL
# de Tasmota (AES-CBC, AES-GCM avec AAD comme le correctif, HMAC-SHA256, MD5), puis joue les
# scenarios de test_tuya_local.py contre de faux appareils Tuya construits sur TinyTuya.
#
# Usage : berry/test/run_tests.sh <depot Tasmota>
# Ecrit /tuya.json (configuration fictive) : a lancer dans un conteneur ou une CI.
set -euo pipefail

TASMOTA=$(cd "${1:?usage: run_tests.sh <depot Tasmota>}" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

LIB="$TASMOTA/lib/libesp32"
SSL="$TASMOTA/lib/lib_ssl/bearssl-esp8266/src"

# Berry de Tasmota (le Makefile attend ses voisins re1.5, berry_mapping...)
for d in berry re1.5 berry_mapping berry_int64 berry_custom; do cp -r "$LIB/$d" "$WORK/"; done
cd "$WORK/berry"
rm -f berry.exe
sed -i 's|    bvm \*vm = be_vm_new(); /\* create a virtual machine instance \*/|&\n    { extern void be_test_crypto_init(bvm*); be_test_crypto_init(vm); }|' default/berry.c
grep -q be_test_crypto_init default/berry.c
make -j"$(nproc)" >/dev/null 2>&1 || true      # l'edition de liens echoue (symbole de test), les .o suffisent

# BearSSL + module crypto de test
mkdir -p "$WORK/obj"
for f in symcipher/aes_small_cbcenc symcipher/aes_small_cbcdec symcipher/aes_small_dec symcipher/aes_small_enc \
         symcipher/aes_common symcipher/aes_small_ctr aead/gcm hash/ghash_ctmul32 mac/hmac hash/sha2small \
         hash/md5 codec/enc32be codec/dec32be codec/enc32le codec/dec32le codec/ccopy; do
  gcc -w -O1 -c -I"$SSL" -I"$SSL/.." "$SSL/$f.c" -o "$WORK/obj/$(basename "$f").o"
done
gcc -w -O1 -c -I"$SSL" -I"$SSL/.." -I"$WORK/berry/src" "$HERE/testcrypto.c" -o "$WORK/obj/testcrypto.o"
gcc $(find src default ../re1.5 ../berry_mapping/src ../berry_int64/src -name '*.o') "$WORK"/obj/*.o -lm -o "$WORK/berry-test"

python3 -c "import tinytuya" 2>/dev/null || pip install -q tinytuya
cd "$HERE"
python3 -I test_tuya_local.py "$WORK/berry-test"
