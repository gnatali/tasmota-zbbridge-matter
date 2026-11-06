# Harnais de test : simule `tasmota` et `tcpclientasync`, pilote par des lignes sur stdin
#   RX <ip> <hex>     octets recus de l'appareil
#   OPEN <ip>         la connexion TCP aboutit        DROP <ip>   l'appareil coupe
#   ADV <ms>          avance le temps (every_50ms appele toutes les 50 ms)
#   MTR <json>        evenement MtrReceived            CMD <nom> <payload>  commande Tasmota
#   SENSOR            json_append() + web_sensor()     END
# Sorties : CONNECT, TX, CLOSE, CMD (MtrUpdate), PUB, RESP, APPEND, WEB, LOG ; READY apres chaque ligne
import json
import string

class MockTasmota
  var now, rules, cmds, drivers
  def init()  self.now = 100000  self.rules = {}  self.cmds = {}  self.drivers = []  end
  def millis()  return self.now  end
  def rtc()  return {"utc": 1793984000 + self.now / 1000}  end
  def add_driver(d)  self.drivers.push(d)  end
  def add_rule(t, f, id)  self.rules[t] = f  end
  def add_cmd(n, f)  self.cmds[n] = f  end
  def log(m, l)  print("LOG " + str(l) + " " + m)  end
  def publish_result(p, sub)  print("PUB " + p)  end
  def cmd(c, mute)
    print("CMD " + c)
    var p = json.load(c[10 ..])
    if p["Name"] == "Inconnu"  return {"MtrUpdate": "Invalid Device"}  end
    return {"MtrUpdate": p}
  end
  def resp_cmnd(s)  print("RESP " + s)  end
  def resp_cmnd_str(s)  print("RESP " + s)  end
  def resp_cmnd_done()  print("RESP Done")  end
  def response_append(s)  print("APPEND " + s)  end
  def web_send_decimal(s)  print("WEB " + s)  end
end
tasmota = MockTasmota()

class tcpclientasync
  static var socks = {}
  var ip, st, inbox
  def init()  self.inbox = bytes()  end
  def connect(ip, port)
    self.ip = ip
    tcpclientasync.socks[ip] = self
    print("CONNECT " + ip + " " + str(port))
    return true
  end
  def connected()  return self.st  end
  def available()  return size(self.inbox)  end
  def readbytes()  var b = self.inbox  self.inbox = bytes()  return b  end
  def write(b)
    # ecrit au plus 64 octets a la fois, pour tester les ecritures partielles
    var n = size(b) > 64 ? 64 : size(b)
    print("TX " + self.ip + " " + b[0 .. n - 1].tohex())
    return n
  end
  def close()
    print("CLOSE " + self.ip)
    self.st = false
  end
end

# Le driver est instancie ici comme dans autoexec.be : le fichier ne contient que les classes.
# Interpreteur avec le driver solidifie : les classes sont deja natives. Sinon, le source est
# compile en mode strict, comme load() dans Tasmota.
import global
if !global.contains("TuyaLocal")
  import strict
  compile("../tuya_local.be", "file")()
end
global.tuya_local = global.TuyaLocal()
var drv = global.tuya_local
print("READY")

def tick()  drv.every_50ms()  end

while true
  var line = input()
  if line == nil || line == "END"  break  end
  var sp = string.split(line, " ", 1)
  var op = sp[0]
  var arg = size(sp) > 1 ? sp[1] : ""
  if op == "RX"
    var a = string.split(arg, " ", 1)
    tcpclientasync.socks[a[0]].inbox .. bytes(a[1])
  elif op == "OPEN"
    tcpclientasync.socks[arg].st = true
  elif op == "DROP"
    tcpclientasync.socks[arg].st = false
  elif op == "ADV"
    var ms = int(arg)
    while ms > 0
      tasmota.now += 50
      ms -= 50
      tick()
    end
  elif op == "MTR"
    tasmota.rules["MtrReceived"](json.load(arg), "MtrReceived", nil)
  elif op == "CMD"
    var a = string.split(arg, " ", 1)
    tasmota.cmds[a[0]](a[0], 0, size(a) > 1 ? a[1] : "")
  elif op == "MEM"
    import gc
    gc.collect()
    print("MEM " + str(gc.allocated()))
  elif op == "SENSOR"
    drv.json_append()
    drv.web_sensor()
  end
  tick()
  print("READY")
end
