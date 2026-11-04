#!/usr/bin/env python3
"""Convertit un firmware CC2652P Intel HEX en fichier .zbp compact pour zbpro_flash.be.

Le .hex du ZBBridge Pro (~500 Ko) ne tient pas dans le systeme de fichiers de 320 Ko.
Le .zbp ne garde que les blocs de 128 octets non vides (~185 Ko).

Format .zbp (entiers little-endian sauf mention) :
  "ZBP1"                          4 octets
  CRC32 de 0x00000..0x2FFFF       4 octets big-endian, tels que renvoyes par le BSL
  CRC32 de 0x30000..0x57FFF       4 octets big-endian   (flash effacee = 0xFF)
  puis N blocs, par adresses croissantes (le CCFG, en fin de flash, est ecrit en dernier) :
    adresse                       4 octets
    donnees                       128 octets

Usage : python3 hex2zbp.py entree.hex sortie.zbp
"""
import sys
import zlib

FLASH_SIZE = 0x58000
CRC_SPLIT = 0x30000      # le BSL calcule sans souci un CRC sur 0x30000 octets
BLOCK = 128
CCFG_ADDR = 0x57FD8
CCFG_BSL_DIO8_LOW = bytes.fromhex("C508FEC5")   # 0xC5FE08C5 en little-endian


def read_hex(path):
    mem = bytearray(b"\xFF" * FLASH_SIZE)
    used = set()
    base = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line.startswith(":"):
                continue
            rec = bytes.fromhex(line[1:])
            n, addr, rtype = rec[0], (rec[1] << 8) | rec[2], rec[3]
            if len(rec) != n + 5 or sum(rec) & 0xFF:
                raise ValueError(f"ligne invalide : {line}")
            if rtype == 0:
                a = base + addr
                if a + n > FLASH_SIZE:
                    raise ValueError(f"adresse hors flash : 0x{a:06X}")
                mem[a:a + n] = rec[4:4 + n]
                used.update(range(a // BLOCK, (a + n - 1) // BLOCK + 1))
            elif rtype == 1:
                break
            elif rtype == 2:
                base = ((rec[4] << 8) | rec[5]) << 4
            elif rtype == 4:
                base = ((rec[4] << 8) | rec[5]) << 16
            else:
                raise ValueError(f"type d'enregistrement non gere : {rtype}")
    return mem, used


def main(src, dst):
    mem, used = read_hex(src)
    if mem[CCFG_ADDR:CCFG_ADDR + 4] != CCFG_BSL_DIO8_LOW:
        raise SystemExit("CCFG incorrect : le BSL n'est pas sur DIO_8 bas (pas un firmware ZBBridge Pro)")
    out = bytearray(b"ZBP1")
    crc_lo = zlib.crc32(mem[:CRC_SPLIT])
    crc_hi = zlib.crc32(mem[CRC_SPLIT:])
    out += crc_lo.to_bytes(4, "big") + crc_hi.to_bytes(4, "big")
    blocks = 0
    for b in sorted(used):
        data = mem[b * BLOCK:(b + 1) * BLOCK]
        if data == b"\xFF" * BLOCK:
            continue
        out += (b * BLOCK).to_bytes(4, "little") + data
        blocks += 1
    with open(dst, "wb") as f:
        f.write(out)
    print(f"{dst} : {blocks} blocs, {len(out)} octets, CRC32 {crc_lo:08X} / {crc_hi:08X}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
