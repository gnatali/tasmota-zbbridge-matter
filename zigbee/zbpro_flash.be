#################################################################################
#
# zbpro_flash.be : diagnostic et reflash du CC2652P du Sonoff ZBBridge Pro
#
# Le .hex officiel (~500 Ko) ne tient pas dans le systeme de fichiers de 320 Ko :
# ce script ecrit un fichier .zbp compact (~185 Ko, voir hex2zbp.py).
#
# A placer dans le systeme de fichiers, avec cc2652_flasher.be (de Tasmota).
# Dans la console Berry :
#
#   import zbpro_flash as zf
#   zf.check()                                   # diagnostic, n'ecrit rien
#   zf.flash("SonoffZBPro_coord_20240710.zbp")   # efface et reprogramme le CC2652P
#
# Les deux arretent Zigbee : redemarrer Tasmota ensuite (commande Restart 1).
#
#################################################################################

class zbpro_flash
  static BLOCK = 128
  static FLASH_SIZE = 0x58000
  static CRC_SPLIT = 0x30000
  static CCFG_ADDR = 0x57FD8
  var fl

  def init()
  end

  # importe cc2652_flasher : arrete Zigbee et ouvre le port serie du CC2652P
  def flasher()
    if self.fl == nil
      import cc2652_flasher
      self.fl = cc2652_flasher
    end
    return self.fl
  end

  # nom du firmware d'apres le CRC32 de 0x00000-0x2FFFF
  static def firmware_name(crc)
    if   crc == "1598929A"  return "SonoffZBPro_coord_20220219"
    elif crc == "37E109F6"  return "SonoffZBPro_coord_20230507"
    elif crc == "D0D7B0AA"  return "SonoffZBPro_coord_20240710"
    end
    return "firmware inconnu (origine Sonoff, ou flash incomplet)"
  end

  static def ccfg_ok(b)
    var h = b.tohex()
    return h == "C508FEC5" || h == "C5FE08C5"
  end

  # redemarre le CC2652P en bootloader et affiche ce qu'il contient
  def check()
    var fl = self.flasher()
    fl.start()
    fl.ping()
    print(format("FLH: bootloader CC2652P OK, chip id 0x%08X", fl.cmd_get_chip_id()))
    var ccfg = fl.cmd_memory_read(self.CCFG_ADDR, 4)
    print("FLH: CCFG " + ccfg.tohex() + (self.ccfg_ok(ccfg) ? " (BSL sur DIO_8 bas : OK)" : " (inattendu)"))
    var crc = fl.cmd_crc32(0, self.CRC_SPLIT).tohex()
    print("FLH: CRC32 0x00000-0x2FFFF " + crc + " : " + self.firmware_name(crc))
  end

  # verifie le fichier avant tout effacement, renvoie [nombre de blocs, CRC 1, CRC 2]
  def check_file(f)
    var rec = 4 + self.BLOCK
    var total = f.size()
    f.seek(0)
    var hdr = f.readbytes(12)
    if size(hdr) != 12 || hdr[0..3].asstring() != "ZBP1" || (total - 12) % rec != 0
      raise "value_error", "fichier .zbp invalide"
    end
    var n = (total - 12) / rec
    var last = -1
    var ccfg_found = false
    var CCFG = self.CCFG_ADDR
    for i: 0 .. n - 1
      var b = f.readbytes(rec)
      var addr = b.get(0, 4)
      if size(b) != rec || addr <= last || addr % self.BLOCK != 0 || addr + self.BLOCK > self.FLASH_SIZE
        raise "value_error", format("bloc %i invalide (adresse 0x%06X)", i, addr)
      end
      last = addr
      if addr <= CCFG && CCFG + 4 <= addr + self.BLOCK
        var off = 4 + CCFG - addr
        ccfg_found = self.ccfg_ok(b[off .. off + 3])
      end
      if i % 32 == 0  tasmota.yield() end
    end
    if !ccfg_found
      raise "value_error", "CCFG absent ou incorrect : ce n'est pas un firmware ZBBridge Pro"
    end
    return [n, hdr[4..7].tohex(), hdr[8..11].tohex()]
  end

  def flash(filename)
    var f = open(filename, "rb")
    var erased = false
    try
      var info = self.check_file(f)
      var n = info[0]
      print(format("FLH: fichier OK, %i blocs. Effacement puis ecriture (quelques minutes, Tasmota ne repond plus)", n))
      var fl = self.flasher()
      fl.start()
      fl.ping()
      fl.flash_erase()
      erased = true
      f.seek(12)
      var rec = 4 + self.BLOCK
      for i: 0 .. n - 1
        var b = f.readbytes(rec)
        fl.flash_write(b.get(0, 4), b[4..])    # adresses croissantes : le CCFG est ecrit en dernier
        if i % 200 == 0  print(format("FLH: %i / %i", i, n)) end
        tasmota.yield()
      end
      f.close()
      f = nil
      var crc_lo = fl.cmd_crc32(0, self.CRC_SPLIT).tohex()
      var crc_hi = fl.cmd_crc32(self.CRC_SPLIT, self.FLASH_SIZE - self.CRC_SPLIT).tohex()
      if crc_lo != info[1] || crc_hi != info[2]
        raise "flash_error", f"verification echouee : CRC {crc_lo}/{crc_hi}, attendu {info[1]}/{info[2]}"
      end
      print(f"FLH: flash termine et verifie (CRC {crc_lo}/{crc_hi}). Redemarrer : Restart 1")
    except .. as e, m
      if f != nil  f.close() end
      print(f"FLH: ERREUR {e} - {m}")
      if erased
        print("FLH: tant que le flash n'est pas complet, le CC2652P reste en bootloader : relancer zf.flash()")
      else
        print("FLH: rien n'a ete efface")
      end
    end
  end
end

return zbpro_flash()
