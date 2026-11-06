#- tuya_local.be : pilotage local des appareils Tuya Wi-Fi depuis Tasmota (equivalent de LocalTuya)

  - Protocoles locaux Tuya 3.3, 3.4 et 3.5 (TCP 6668), sans le cloud
  - Sous-appareils Zigbee d'une passerelle Tuya (champ "cid")
  - Pont vers Matter : endpoints virtuels (v_relay, v_light2, v_fan...) pilotes par
    l'evenement MtrReceived et mis a jour par la commande MtrUpdate
  - Valeurs de mesure (pince amperemetrique...) dans les releves Tasmota et la page web

  Configuration : fichier /tuya.json (voir tuya.example.json et docs/tuya-local.fr.md)
  Commandes : TuyaStatus, TuyaSend <appareil>,<dp>,<valeur>, TuyaReload

  Necessite un firmware avec USE_BERRY_CRYPTO_AES_CBC (3.3, 3.4) et le correctif
  AES_GCM 128 bits avec AAD (3.5).

  Solidifie dans le firmware (custom_berry_solidify) : les classes sont alors en flash, en
  lecture seule, et deviennent des classes natives. D'ou trois regles :
  - pas de code au premier niveau hors des classes : le driver est instancie par autoexec.be
    (`global.tuya_local = TuyaLocal()`), pas par ce fichier ;
  - les modules (string, json, crypto) sont importes dans les methodes qui s'en servent ;
  - pas d'ecriture dans une variable statique (`static var`) : constantes uniquement.
  Le fichier reste chargeable tel quel avec load("tuya_local.be") sur un firmware qui ne
  l'embarque pas (meme instanciation ensuite).
-#

#################################################################################
# TuyaCodec : primitives du protocole (sans etat)
#################################################################################
#@ solidify:TuyaCodec,weak
class TuyaCodec
  # CRC-32 (polynome 0xEDB88320) par quartet : table constante de 16 entrees, sans calcul
  # au premier appel (une classe solidifiee est en lecture seule)
  static var CRC_NIBBLE = [0x00000000, 0x1DB71064, 0x3B6E20C8, 0x26D930AC, 0x76DC4190, 0x6B6B51F4,
                           0x4DB26158, 0x5005713C, 0xEDB88320, 0xF00F9344, 0xD6D6A3E8, 0xCB61B38C,
                           0x9B64C2B0, 0x86D3D2D4, 0xA00AE278, 0xBDBDF21C]
  # commandes envoyees sans l'en-tete de version "3.x" + 12 octets nuls
  static var NO_HEADER = [3, 4, 5, 9, 10, 16, 18, 64]

  static def crc32(b, len)
    var t = TuyaCodec.CRC_NIBBLE
    var crc = 0xFFFFFFFF
    var i = 0
    while i < len
      crc = crc ^ b[i]
      crc = t[crc & 0x0F] ^ ((crc >> 4) & 0x0FFFFFFF)
      crc = t[crc & 0x0F] ^ ((crc >> 4) & 0x0FFFFFFF)
      i += 1
    end
    return crc ^ 0xFFFFFFFF
  end

  static def hmac(key, data)
    import crypto
    return crypto.HMAC_SHA256(key).update(data).out()
  end

  static def pad(b)
    var n = 16 - (b.size() % 16)
    var r = b.copy()
    var i = 0
    while i < n  r.add(n, 1)  i += 1  end
    return r
  end

  static def unpad(b)
    var sz = b.size()
    if sz == 0  return b  end
    var n = b[sz - 1]
    if n < 1 || n > 16 || n > sz  return b  end
    return b[0 .. sz - n - 1]
  end

  # AES-128-ECB, bloc par bloc, avec AES-CBC et un IV nul
  static def ecb(key, data, enc)
    import crypto
    var out = bytes()
    var i = 0
    while i < data.size()
      var blk = data[i .. i + 15]
      if enc
        crypto.AES_CBC.encrypt1(key, bytes(-16), blk)
      else
        crypto.AES_CBC.decrypt1(key, bytes(-16), blk)
      end
      out .. blk
      i += 16
    end
    return out
  end

  static def version_header(ver)
    var h = bytes().fromstring(ver)
    h .. bytes(-12)
    return h
  end
end

#################################################################################
# TuyaBinding : liaison entre des DP Tuya et un endpoint Matter virtuel
#################################################################################
#@ solidify:TuyaBinding,weak
class TuyaBinding
  var node            # TuyaNode (appareil ou sous-appareil) qui porte les DP
  var ep              # nom de l'endpoint Matter
  var type            # relay, relay_power, light0..3, fan, temp, humidity
  var c               # configuration (map)
  var pending         # true : le dernier MtrUpdate a ete refuse (endpoint absent), a renvoyer

  def init(node, conf)
    self.node = node
    self.c = conf
    self.ep = conf.find("ep", node.name)
    self.type = conf.find("type", "relay")
  end

  def dp(k, dflt)
    var v = self.c.find(k, dflt)
    return v != nil ? str(v) : nil
  end
  def num(k, dflt)
    return self.c.find(k, dflt)
  end

  # Matter -> Tuya : attributs MtrReceived -> map de DP a envoyer
  def to_tuya(a)
    import string
    var t = self.type
    var out = {}
    var st = self.node.dps
    if t == "fan"
      var dp_on = self.dp("dp", 60)
      var dp_speed = self.dp("dp_speed", 62)
      var smin = self.num("speed_min", 1)
      var smax = self.num("speed_max", 6)
      var pct = a.find("FanSpeed")
      if pct == nil && a.find("FanMode") != nil
        pct = [0, 33, 67, 100][int(a["FanMode"]) & 3]
      end
      if pct != nil
        pct = int(pct)
        if pct <= 0
          out[dp_on] = false
        else
          var s = (pct * smax + 99) / 100
          if s < smin  s = smin  end
          if s > smax  s = smax  end
          out[dp_on] = true
          out[dp_speed] = s
        end
      end
      return out
    end
    if a.contains("Power")
      out[self.dp("dp", t == "light0" || t == "light1" || t == "light2" || t == "light3" ? 20 : 1)] = bool(a["Power"])
    end
    if t == "light1" || t == "light2" || t == "light3"
      var bmin = self.num("bri_min", 10)
      var bmax = self.num("bri_max", 1000)
      var dp_mode = self.dp("dp_mode", 21)
      var dp_bri = self.dp("dp_bri", 22)
      var dp_col = self.dp("dp_colour", 24)
      var colour = (t == "light3") && (st.find(dp_mode) == "colour")
      if t == "light3" && (a.contains("Hue") || a.contains("Sat"))
        var hsv = self.hsv_get()
        if a.contains("Hue")  hsv[0] = (int(a["Hue"]) * 360 + 127) / 254  end
        if a.contains("Sat")  hsv[1] = (int(a["Sat"]) * 1000 + 127) / 254  end
        if a.contains("Bri")  hsv[2] = self.bri_to_raw(a["Bri"], 10, 1000)  end
        out[dp_mode] = "colour"
        out[dp_col] = string.format("%04x%04x%04x", hsv[0], hsv[1], hsv[2])
      elif a.contains("Bri")
        if colour
          var hsv = self.hsv_get()
          hsv[2] = self.bri_to_raw(a["Bri"], 10, 1000)
          out[dp_col] = string.format("%04x%04x%04x", hsv[0], hsv[1], hsv[2])
        else
          out[dp_bri] = self.bri_to_raw(a["Bri"], bmin, bmax)
          if t == "light3" && st.contains(dp_mode)  out[dp_mode] = "white"  end
        end
      end
      if t == "light2" && a.contains("CT")
        var cmin = self.num("ct_min", 153)       # mireds de la valeur Tuya 1000 (froid)
        var cmax = self.num("ct_max", 500)       # mireds de la valeur Tuya 0 (chaud)
        var ct = int(a["CT"])
        if ct < cmin  ct = cmin  end
        if ct > cmax  ct = cmax  end
        out[self.dp("dp_ct", 23)] = ((cmax - ct) * 1000 + (cmax - cmin) / 2) / (cmax - cmin)
        if st.contains(dp_mode) && st[dp_mode] != "white"  out[dp_mode] = "white"  end
      end
    end
    return out
  end

  def bri_to_raw(b, lo, hi)
    b = int(b)
    if b < 1  b = 1  end
    if b > 254  b = 254  end
    return lo + ((b - 1) * (hi - lo) + 126) / 253
  end
  def raw_to_bri(v, lo, hi)
    v = int(v)
    if v < lo  v = lo  end
    if v > hi  v = hi  end
    return 1 + ((v - lo) * 253 + (hi - lo) / 2) / (hi - lo)
  end

  # couleur Tuya (colour_data_v2) : "hhhhssssvvvv", h 0..360, s et v 0..1000
  def hsv_get()
    var s = self.node.dps.find(self.dp("dp_colour", 24))
    if type(s) == 'string' && size(s) == 12
      return [int("0x" + s[0..3]), int("0x" + s[4..7]), int("0x" + s[8..11])]
    end
    return [0, 1000, 1000]
  end

  # Tuya -> Matter : envoie a l'endpoint les attributs touches par `changed` (map de DP).
  # Si l'endpoint refuse (absent, cree apres le driver...), la liaison passe en attente et
  # TuyaLocal lui renvoie l'etat complet toutes les SYNC_RETRY ms. Renvoie false si refuse.
  def push(changed)
    import json
    var r = self.to_matter(changed)
    if r == nil  return true  end
    r["Name"] = self.ep
    var res = tasmota.cmd("MtrUpdate " + json.dump(r), true)
    var v = (type(res) == 'instance') ? res.find("MtrUpdate") : nil
    if type(v) == 'instance'
      if self.pending
        tasmota.log(f"TUY: endpoint Matter '{self.ep}' disponible, etat envoye", 2)
        self.pending = false
      end
      return true
    end
    if !self.pending                  # {"MtrUpdate":"Invalid Device"} ou rien : signale une fois
      var why = (v != nil) ? v : res
      tasmota.log(f"TUY: endpoint Matter '{self.ep}' : {why} (nouvel essai toutes les 30 s)", 2)
      self.pending = true
    end
    return false
  end

  # Tuya -> Matter : etat courant -> attributs MtrUpdate (nil si rien ne concerne cet endpoint)
  def to_matter(changed)
    var t = self.type
    var st = self.node.dps
    var r = {}
    var hit = false
    if t == "fan"
      var dp_on = self.dp("dp", 60)
      var dp_speed = self.dp("dp_speed", 62)
      if changed.contains(dp_on) || changed.contains(dp_speed)
        var smax = self.num("speed_max", 6)
        var on = st.find(dp_on, false)
        var s = int(st.find(dp_speed, 0))
        r["FanSpeed"] = (on && s > 0) ? (s * 100 + smax / 2) / smax : 0
        if on && r["FanSpeed"] == 0  r["FanSpeed"] = 1  end
        hit = true
      end
      return hit ? r : nil
    end
    if t == "temp" || t == "humidity"
      var d = self.dp("dp", t == "temp" ? 1 : 2)
      if changed.contains(d)
        var v = real(st[d]) / self.num("div", 10)
        r[t == "temp" ? "Temperature" : "Humidity"] = v
        hit = true
      end
      return hit ? r : nil
    end
    var dp_on = self.dp("dp", t == "light0" || t == "light1" || t == "light2" || t == "light3" ? 20 : 1)
    if changed.contains(dp_on)
      r["Power"] = st[dp_on] ? 1 : 0
      hit = true
    end
    if t == "relay_power"
      for k: [["dp_power", "ActivePower", "div_power"], ["dp_voltage", "Voltage", "div_voltage"], ["dp_current", "Current", "div_current"]]
        var d = self.dp(k[0])
        if d != nil && changed.contains(d)
          r[k[1]] = real(st[d]) / self.num(k[2], 1)
          hit = true
        end
      end
    end
    if t == "light1" || t == "light2" || t == "light3"
      var dp_mode = self.dp("dp_mode", 21)
      var dp_bri = self.dp("dp_bri", 22)
      var dp_col = self.dp("dp_colour", 24)
      var colour = (t == "light3") && (st.find(dp_mode) == "colour")
      if colour && (changed.contains(dp_col) || changed.contains(dp_mode))
        var hsv = self.hsv_get()
        r["Hue"] = (hsv[0] * 254 + 180) / 360
        r["Sat"] = (hsv[1] * 254 + 500) / 1000
        r["Bri"] = self.raw_to_bri(hsv[2], 10, 1000)
        hit = true
      elif !colour && (changed.contains(dp_bri) || changed.contains(dp_mode)) && st.contains(dp_bri)
        r["Bri"] = self.raw_to_bri(st[dp_bri], self.num("bri_min", 10), self.num("bri_max", 1000))
        if t == "light3"  r["Sat"] = 0  end
        hit = true
      end
      var dp_ct = self.dp("dp_ct", 23)
      if t == "light2" && changed.contains(dp_ct)
        var cmin = self.num("ct_min", 153)
        var cmax = self.num("ct_max", 500)
        r["CT"] = cmax - (int(st[dp_ct]) * (cmax - cmin) + 500) / 1000
        hit = true
      end
    end
    return hit ? r : nil
  end
end

#################################################################################
# TuyaNode : un appareil logique (appareil Wi-Fi ou sous-appareil de passerelle)
#################################################################################
#@ solidify:TuyaNode,weak
class TuyaNode
  var name, id, cid          # cid : identifiant du sous-appareil (nil pour un appareil Wi-Fi)
  var conn                   # TuyaDevice qui porte la connexion TCP
  var dps                    # dernier etat connu {"1": true, ...}
  var bindings               # list de TuyaBinding
  var sensors                # {"label": [dp, diviseur, unite]} : releves Tasmota
  var seen                   # millis de la derniere reception

  def init(conn, conf)
    self.conn = conn
    self.name = conf.find("name", conf.find("id"))
    self.id = conf.find("id")
    self.cid = conf.find("cid")
    self.dps = {}
    self.bindings = []
    self.sensors = conf.find("sensors", {})
    for m: conf.find("matter", [])
      self.bindings.push(TuyaBinding(self, m))
    end
  end

  # nouvelles valeurs recues de l'appareil
  def update(dps)
    import json
    var changed = {}
    for k: dps.keys()
      var ks = str(k)
      if self.dps.find(ks) != dps[k] || !self.dps.contains(ks)
        changed[ks] = dps[k]
      end
      self.dps[ks] = dps[k]
    end
    self.seen = tasmota.millis()
    if size(changed) == 0  return  end
    tasmota.log(f"TUY: {self.name} {json.dump(changed)}", 3)
    tasmota.publish_result(json.dump({"Tuya": {"Name": self.name, "Dps": changed}}), "RESULT")
    for b: self.bindings
      if b.pending
        b.push(self.dps)                # endpoint en attente : etat complet
      else
        b.push(changed)
      end
    end
  end

  def all_dps()
    var m = {}
    for k: self.dps.keys()  m[k] = self.dps[k]  end
    return m
  end
end

#################################################################################
# TuyaDevice : connexion TCP vers un appareil Wi-Fi (ou une passerelle) et protocole
#################################################################################
#@ solidify:TuyaDevice,weak
class TuyaDevice : TuyaNode
  static var PORT = 6668
  static var ST_IDLE = 0
  static var ST_CONNECTING = 1
  static var ST_NEGO = 2
  static var ST_READY = 3

  var ip, ver, key, sess_key
  var tcp, state, rx, tx
  var seq, nonce
  var children                # {"cid": TuyaNode}
  var t_retry, retry_delay, t_hb, t_last_rx, t_state

  def init(conf)
    super(self).init(self, conf)
    self.ip = conf["ip"]
    self.ver = str(conf.find("version", "3.3"))
    self.key = bytes().fromstring(conf["key"])
    self.children = {}
    for c: conf.find("children", [])
      var n = TuyaNode(self, c)
      self.children[str(c["cid"])] = n
    end
    self.state = self.ST_IDLE
    self.rx = bytes()
    self.tx = bytes()
    self.seq = 1
    self.t_retry = 0
    self.retry_delay = 5000
  end

  def is_gateway()  return size(self.children) > 0  end
  def v34()  return self.ver == "3.4" || self.ver == "3.5"  end

  ###################### connexion ######################
  def close(reason)
    if self.tcp  self.tcp.close()  end
    self.tcp = nil
    if self.state != self.ST_IDLE
      tasmota.log(f"TUY: {self.name} ({self.ip}) deconnecte : {reason}", 2)
    end
    self.state = self.ST_IDLE
    self.rx = bytes()
    self.tx = bytes()
    self.sess_key = nil
    self.t_retry = tasmota.millis() + self.retry_delay
    self.retry_delay = self.retry_delay * 2
    if self.retry_delay > 60000  self.retry_delay = 60000  end
  end

  def connect()
    self.tcp = tcpclientasync()
    self.tcp.connect(self.ip, self.PORT)
    self.state = self.ST_CONNECTING
    self.t_state = tasmota.millis()
    self.seq = 1
  end

  def on_connected()
    import crypto
    tasmota.log(f"TUY: {self.name} ({self.ip}) connecte, protocole {self.ver}", 2)
    self.t_last_rx = tasmota.millis()
    self.t_hb = tasmota.millis()
    if self.v34()
      self.state = self.ST_NEGO
      self.t_state = tasmota.millis()
      self.sess_key = nil
      self.nonce = crypto.random(16)
      self.send_raw(3, self.nonce)
    else
      self.on_ready()
    end
  end

  def on_ready()
    self.state = self.ST_READY
    self.retry_delay = 5000
    self.query()
  end

  def loop()
    var now = tasmota.millis()
    if self.state == self.ST_IDLE
      if now >= self.t_retry  self.connect()  end
      return
    end
    var c = self.tcp.connected()
    if self.state == self.ST_CONNECTING
      if c == true
        self.on_connected()
      elif c == false || now - self.t_state > 10000
        self.close("connexion impossible")
        return
      end
      return
    end
    if c != true
      self.close("connexion fermee")
      return
    end
    # reception
    if self.tcp.available() > 0
      self.rx .. self.tcp.readbytes()
      self.t_last_rx = now
      self.parse()
      if self.tcp == nil  return  end
    end
    # emission en attente
    self.flush()
    if self.state == self.ST_NEGO && now - self.t_state > 5000
      self.close("negociation de cle sans reponse")
      return
    end
    if self.state == self.ST_READY
      if now - self.t_last_rx > 35000
        self.close("plus de reponse")
        return
      end
      if now - self.t_hb > 10000
        self.t_hb = now
        self.send(9, '{"gwId":"' + self.id + '","devId":"' + self.id + '"}')
      end
    end
  end

  def flush()
    if size(self.tx) > 0 && self.tcp
      var n = self.tcp.write(self.tx)
      if n > 0
        self.tx = (n >= size(self.tx)) ? bytes() : self.tx[n ..]
      end
    end
  end

  ###################### emission ######################
  def time_str()  return str(tasmota.rtc()['utc'])  end

  def query()
    if self.is_gateway()
      for n: self.children
        if self.v34()
          self.send(16, '{"cid":"' + n.cid + '"}')
        else
          self.send(10, '{"t":' + self.time_str() + ',"cid":"' + n.cid + '"}')
        end
      end
    elif self.v34()
      self.send(16, '{}')
    else
      self.send(10, '{"gwId":"' + self.id + '","devId":"' + self.id + '","uid":"' + self.id + '","t":"' + self.time_str() + '"}')
    end
  end

  # envoi de DP vers un appareil ou un sous-appareil (node)
  def set_dps(node, dps)
    import json
    if self.state != self.ST_READY
      tasmota.log(f"TUY: {node.name} non connecte, commande ignoree", 2)
      return false
    end
    var d = json.dump(dps)
    if node.cid != nil
      if self.v34()
        self.send(13, '{"protocol":5,"t":' + self.time_str() + ',"data":{"cid":"' + node.cid + '","ctype":0,"dps":' + d + '},"cid":"' + node.cid + '"}')
      else
        self.send(7, '{"t":' + self.time_str() + ',"cid":"' + node.cid + '","dps":' + d + '}')
      end
    elif self.v34()
      self.send(13, '{"protocol":5,"t":' + self.time_str() + ',"data":{"dps":' + d + '}}')
    else
      self.send(7, '{"devId":"' + self.id + '","uid":"' + self.id + '","t":"' + self.time_str() + '","dps":' + d + '}')
    end
    return true
  end

  def send(cmd, payload)
    self.send_raw(cmd, bytes().fromstring(payload))
  end

  def send_raw(cmd, p)
    var hdr = (TuyaCodec.NO_HEADER.find(cmd) == nil)
    var k = self.sess_key != nil ? self.sess_key : self.key
    var frame
    if self.ver == "3.5"
      var plain = hdr ? TuyaCodec.version_header(self.ver) + p : p
      frame = self.frame_6699(cmd, plain, k)
    elif self.ver == "3.4"
      var plain = hdr ? TuyaCodec.version_header(self.ver) + p : p
      frame = self.frame_55aa(cmd, TuyaCodec.ecb(k, TuyaCodec.pad(plain), true), k)
    else
      var body = TuyaCodec.ecb(k, TuyaCodec.pad(p), true)
      if hdr  body = TuyaCodec.version_header(self.ver) + body  end
      frame = self.frame_55aa(cmd, body, nil)
    end
    self.seq += 1
    self.tx .. frame
    self.flush()
  end

  def frame_55aa(cmd, body, hmac_key)
    var b = bytes()
    b.add(0x000055AA, -4)
    b.add(self.seq, -4)
    b.add(cmd, -4)
    b.add(size(body) + (hmac_key ? 36 : 8), -4)
    b .. body
    if hmac_key
      b .. TuyaCodec.hmac(hmac_key, b)
    else
      b.add(TuyaCodec.crc32(b, size(b)), -4)
    end
    b.add(0x0000AA55, -4)
    return b
  end

  def frame_6699(cmd, plain, k)
    import crypto
    var b = bytes()
    b.add(0x00006699, -4)
    b.add(0, -2)
    b.add(self.seq, -4)
    b.add(cmd, -4)
    b.add(12 + size(plain) + 16, -4)
    var iv = crypto.random(12)
    var g = crypto.AES_GCM(k, iv, b[4 .. 17])
    var ct = g.encrypt(plain)
    b .. iv
    b .. ct
    b .. g.tag()
    b.add(0x00009966, -4)
    return b
  end

  ###################### reception ######################
  def parse()
    while true
      var n = size(self.rx)
      if n < 4  return  end
      var pfx = self.rx.get(0, -4)
      if pfx != 0x000055AA && pfx != 0x00006699
        # resynchronisation : on cherche le prochain prefixe
        var i = 1
        while i <= n - 4
          var p = self.rx.get(i, -4)
          if p == 0x000055AA || p == 0x00006699  break  end
          i += 1
        end
        self.rx = (i <= n - 4) ? self.rx[i ..] : self.rx[n - 3 ..]
        continue
      end
      var total
      if pfx == 0x000055AA
        if n < 16  return  end
        total = 16 + self.rx.get(12, -4)
      else
        if n < 18  return  end
        total = 18 + self.rx.get(14, -4) + 4
      end
      if total < 24 || total > 4096
        self.close("trame invalide")
        return
      end
      if n < total  return  end
      var frame = self.rx[0 .. total - 1]
      self.rx = (n > total) ? self.rx[total ..] : bytes()
      try
        self.handle(frame)
      except .. as e, m
        tasmota.log(f"TUY: {self.name} erreur de decodage : {e} {m}", 2)
      end
      if self.tcp == nil  return  end
    end
  end

  # decode une trame complete -> (cmd, payload en clair sans code retour)
  def decode(frame)
    import crypto
    var k = self.sess_key != nil ? self.sess_key : self.key
    var total = size(frame)
    if frame.get(0, -4) == 0x00006699
      var cmd = frame.get(10, -4)
      var iv = frame[18 .. 29]
      var ct = frame[30 .. total - 21]
      var tag = frame[total - 20 .. total - 5]
      var g = crypto.AES_GCM(k, iv, frame[4 .. 17])
      var pt = g.decrypt(ct)
      if g.tag() != tag  raise "tag_error", "authentification GCM invalide"  end
      return [cmd, size(pt) >= 4 ? pt[4 ..] : bytes()]
    end
    var cmd = frame.get(8, -4)
    var use_hmac = self.v34()
    var end_len = use_hmac ? 36 : 8
    var signed = frame[0 .. total - end_len - 1]
    if use_hmac
      if TuyaCodec.hmac(k, signed) != frame[total - 36 .. total - 5]  raise "hmac_error", "HMAC invalide"  end
    else
      if TuyaCodec.crc32(signed, size(signed)) != frame.get(total - 8, -4)  raise "crc_error", "CRC invalide"  end
    end
    var body = (total - end_len > 20) ? frame[20 .. total - end_len - 1] : bytes()     # apres le code retour
    if size(body) == 0  return [cmd, body]  end
    if use_hmac
      body = TuyaCodec.unpad(TuyaCodec.ecb(k, body, false))
      return [cmd, body]
    end
    if size(body) >= 15 && body[0..2].asstring() == self.ver
      body = body[15 ..]
    end
    if size(body) == 0 || size(body) % 16 != 0  return [cmd, bytes()]  end
    return [cmd, TuyaCodec.unpad(TuyaCodec.ecb(k, body, false))]
  end

  def handle(frame)
    import json
    var r = self.decode(frame)
    var cmd = r[0]
    var p = r[1]
    if cmd == 4
      self.nego_step2(p)
      return
    end
    if size(p) == 0  return  end
    if self.v34() && size(p) >= 15 && p[0..2].asstring() == self.ver
      p = p[15 ..]
    end
    var s = p.asstring()
    if s[0] != '{'  return  end
    var m = json.load(s)
    if m == nil
      tasmota.log(f"TUY: {self.name} JSON invalide : {s}", 3)
      return
    end
    var data = m.find("data")
    var dps = m.find("dps")
    var cid = m.find("cid")
    if type(data) == 'instance' && classname(data) == 'map'
      if dps == nil  dps = data.find("dps")  end
      if cid == nil  cid = data.find("cid")  end
    end
    if dps == nil  return  end
    var node = self
    if cid != nil
      node = self.children.find(str(cid))
      if node == nil
        tasmota.log(f"TUY: {self.name} sous-appareil inconnu cid={cid}", 3)
        return
      end
    end
    node.update(dps)
  end

  ###################### negociation de cle (3.4 / 3.5) ######################
  def nego_step2(p)
    import crypto
    if self.state != self.ST_NEGO || size(p) < 48
      self.close("negociation : reponse inattendue")
      return
    end
    var remote = p[0 .. 15]
    if TuyaCodec.hmac(self.key, self.nonce) != p[16 .. 47]
      self.close("negociation : cle locale incorrecte ?")
      return
    end
    self.send_raw(5, TuyaCodec.hmac(self.key, remote))
    var x = bytes(-16)
    var i = 0
    while i < 16
      x[i] = self.nonce[i] ^ remote[i]
      i += 1
    end
    if self.ver == "3.4"
      self.sess_key = TuyaCodec.ecb(self.key, x, true)
    else
      self.sess_key = crypto.AES_GCM(self.key, self.nonce[0 .. 11]).encrypt(x)
    end
    self.on_ready()
  end

  def nodes()
    var l = [self]
    for c: self.children  l.push(c)  end
    return l
  end
end

#################################################################################
# TuyaLocal : driver Tasmota
#################################################################################
#@ solidify:TuyaLocal,weak
class TuyaLocal
  static var CONFIG = "/tuya.json"
  static var SYNC_RETRY = 30000   # ms entre deux renvois aux endpoints Matter qui ont refuse
  var devices                 # list de TuyaDevice
  var by_ep                   # {nom d'endpoint Matter en minuscules: TuyaBinding}
  var t_sync                  # millis du dernier renvoi

  def init()
    self.devices = []
    self.by_ep = {}
    self.t_sync = tasmota.millis()
    self.load_config()
    tasmota.add_driver(self)
    tasmota.add_rule("MtrReceived", /v -> self.on_matter(v), self)
    tasmota.add_cmd("TuyaStatus", /cmd, idx, payload -> self.cmd_status())
    tasmota.add_cmd("TuyaSend", /cmd, idx, payload -> self.cmd_send(payload))
    tasmota.add_cmd("TuyaReload", /cmd, idx, payload -> self.cmd_reload())
  end

  def load_config()
    import string
    import json
    for d: self.devices  d.close("rechargement")  end
    self.devices = []
    self.by_ep = {}
    var conf
    try
      var f = open(self.CONFIG, "r")
      conf = json.load(f.read())
      f.close()
    except .. as e, m
      tasmota.log(f"TUY: lecture de {self.CONFIG} impossible : {m}", 1)
      return
    end
    if conf == nil
      tasmota.log(f"TUY: {self.CONFIG} n'est pas un JSON valide", 1)
      return
    end
    for c: conf.find("devices", [])
      if c.find("enabled", true) == false  continue  end
      if !c.contains("ip") || !c.contains("key") || !c.contains("id")
        tasmota.log(f"TUY: appareil incomplet ignore : {c.find('name')}", 1)
        continue
      end
      var d = TuyaDevice(c)
      self.devices.push(d)
      for n: d.nodes()
        for b: n.bindings
          self.by_ep[string.tolower(b.ep)] = b
        end
      end
    end
    tasmota.log(f"TUY: {size(self.devices)} appareil(s), {size(self.by_ep)} endpoint(s) Matter", 2)
  end

  def every_50ms()
    for d: self.devices
      try
        d.loop()
      except .. as e, m
        tasmota.log(f"TUY: {d.name} erreur : {e} {m}", 2)
        d.close("erreur interne")
      end
    end
    var now = tasmota.millis()
    if now - self.t_sync >= self.SYNC_RETRY
      self.t_sync = now
      try
        self.sync_pending()
      except .. as e, m
        tasmota.log(f"TUY: renvoi vers Matter : {e} {m}", 2)
      end
    end
  end

  # renvoie l'etat complet aux endpoints Matter qui ont refuse un MtrUpdate : un endpoint cree
  # alors que le driver tourne recoit ainsi l'etat de l'appareil sans redemarrage
  def sync_pending()
    for d: self.devices
      for n: d.nodes()
        for b: n.bindings
          if b.pending  b.push(n.dps)  end
        end
      end
    end
  end

  # evenement MtrReceived : {"ep9":{"Ep":9,"Name":"Lumiere","Power":1}}
  def on_matter(v)
    import string
    import json
    if type(v) != 'instance'  return  end
    for k: v.keys()
      var a = v[k]
      if type(a) != 'instance'  continue  end
      var name = a.find("Name")
      if name == nil  continue  end
      var b = self.by_ep.find(string.tolower(name))
      if b == nil  continue  end
      var dps = b.to_tuya(a)
      if size(dps) > 0
        tasmota.log(f"TUY: Matter '{name}' -> {b.node.name} {json.dump(dps)}", 3)
        b.node.conn.set_dps(b.node, dps)
      end
    end
  end

  def find_node(name)
    import string
    name = string.tolower(name)
    for d: self.devices
      for n: d.nodes()
        if string.tolower(n.name) == name || n.id == name  return n  end
      end
    end
    return nil
  end

  # TuyaSend <appareil>,<dp>,<valeur JSON>   ex : TuyaSend Ventilateur,60,true
  def cmd_send(payload)
    import string
    import json
    var a = string.split(payload, ",", 2)
    if size(a) < 3  return tasmota.resp_cmnd_str("Syntaxe : TuyaSend <appareil>,<dp>,<valeur>")  end
    var n = self.find_node(self.trim(a[0]))
    if n == nil  return tasmota.resp_cmnd_str("Appareil inconnu")  end
    var v = json.load(a[2])
    if v == nil  v = a[2]  end
    var dps = {}
    dps[str(int(a[1]))] = v
    if n.conn.set_dps(n, dps)
      tasmota.resp_cmnd_done()
    else
      tasmota.resp_cmnd_str("Appareil non connecte")
    end
  end

  def trim(s)
    var i = 0
    var j = size(s) - 1
    while i <= j && s[i] == ' '  i += 1  end
    while j >= i && s[j] == ' '  j -= 1  end
    return i <= j ? s[i .. j] : ""
  end

  def cmd_status()
    import json
    var r = {}
    for d: self.devices
      for n: d.nodes()
        r[n.name] = {"Connected": d.state == d.ST_READY, "Ip": d.ip, "Version": d.ver, "Dps": n.all_dps()}
      end
    end
    tasmota.resp_cmnd(json.dump({"TuyaStatus": r}))
  end

  def cmd_reload()
    self.load_config()
    tasmota.resp_cmnd_done()
  end

  # mesures (capteurs) dans le releve SENSOR
  def json_append()
    import json
    var parts = []
    for d: self.devices
      for n: d.nodes()
        if size(n.sensors) == 0  continue  end
        var m = []
        for l: n.sensors.keys()
          var s = n.sensors[l]
          var v = n.dps.find(str(s[0]))
          if v != nil
            m.push(json.dump(l) + ":" + (type(v) == 'int' ? self.scaled(v, size(s) > 1 ? s[1] : 1) : json.dump(v)))
          end
        end
        if size(m) > 0  parts.push(json.dump(n.name) + ":{" + m.concat(",") + "}")  end
      end
    end
    if size(parts) > 0
      tasmota.response_append(',"Tuya":{' + parts.concat(",") + '}')
    end
  end

  # entier Tuya / diviseur (puissance de 10) en decimal exact : 2268703 / 100 -> "22687.03"
  # (pas de flottant : Berry calcule en simple precision sur l'ESP32)
  def scaled(v, div)
    import string
    if div == nil || div <= 1  return str(v)  end
    var dec = 0
    var d = div
    while d > 1 && d % 10 == 0  d /= 10  dec += 1  end
    if d != 1  return string.format("%.3f", real(v) / div)  end
    var neg = v < 0
    if neg  v = -v  end
    var r = str(v / div) + "." + string.format("%0" + str(dec) + "d", v % div)
    return neg ? "-" + r : r
  end

  def web_sensor()
    var msg = ""
    for d: self.devices
      for n: d.nodes()
        if size(n.sensors) == 0  continue  end
        for l: n.sensors.keys()
          var s = n.sensors[l]
          var v = n.dps.find(str(s[0]))
          if v == nil  continue  end
          var unit = size(s) > 2 ? s[2] : ""
          var txt = type(v) == 'int' ? self.scaled(v, size(s) > 1 ? s[1] : 1) : str(v)
          msg += f"{{s}}{n.name} {l}{{m}}{txt} {unit}{{e}}"
        end
      end
    end
    if size(msg) > 0  tasmota.web_send_decimal(msg)  end
  end
end
