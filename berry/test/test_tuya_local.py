"""Tests de bout en bout du driver tuya_local.be contre de faux appareils Tuya (fake_tuya.py).

Lancement : python3 test_tuya_local.py [chemin de l'interpreteur berry de test]
Le fichier /tuya.json est ecrit pour le test (configuration fictive).
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from fake_tuya import FakeDevice  # noqa: E402

BERRY = sys.argv[1] if len(sys.argv) > 1 else "berry"

K = {n: ("%016d" % i)[:16].replace("0", "k") for i, n in enumerate(
    ["fan", "clamp", "porch", "radio", "pergola", "gw"], start=1)}
K["fan"] = "Zq!(4.P;n+x-T]w~"   # caracteres speciaux, comme les vraies cles (cle fictive)

CONFIG = {"devices": [
    {"name": "Ventilateur", "id": "fan000000000000000000", "key": K["fan"], "ip": "10.0.0.18", "version": "3.5",
     "matter": [{"ep": "Ventilateur", "type": "fan", "dp": 60, "dp_speed": 62, "speed_max": 6},
                {"ep": "Lumiere ventilateur", "type": "light0", "dp": 20}]},
    {"name": "Pince", "id": "clamp0000000000000000", "key": K["clamp"], "ip": "10.0.0.80", "version": "3.5",
     "sensors": {"Energie": [131, 100, "kWh"], "Puissance": [133, 1, "W"], "Tension A": [101, 10, "V"]}},
    {"name": "Entree-Porche", "id": "porch0000000000000000", "key": K["porch"], "ip": "10.0.0.174", "version": "3.3",
     "matter": [{"ep": "Porche", "type": "light2"}]},
    {"name": "Recepteur radio", "id": "radio0000000000000000", "key": K["radio"], "ip": "10.0.0.15", "version": "3.5",
     "matter": [{"ep": "Radio 1", "type": "relay", "dp": 1}, {"ep": "Radio 2", "type": "relay", "dp": 2}]},
    {"name": "Pergola 1", "id": "perg00000000000000000", "key": K["pergola"], "ip": "10.0.0.31", "version": "3.4",
     "matter": [{"ep": "Pergola 1", "type": "light3"}]},
    {"name": "Gateway", "id": "gw0000000000000000000", "key": K["gw"], "ip": "10.0.0.180", "version": "3.3",
     "children": [
         {"name": "Prise Lisseur", "id": "plug00000000000000000", "cid": "00158d0000000001",
          "matter": [{"ep": "Prise Lisseur", "type": "relay_power", "dp": 1,
                      "dp_power": 19, "div_power": 10, "dp_voltage": 20, "div_voltage": 10,
                      "dp_current": 18, "div_current": 1000}]},
         {"name": "Temperature SdB", "id": "temp00000000000000000", "cid": "00158d0000000002",
          "matter": [{"ep": "Temperature SdB", "type": "temp", "dp": 1, "div": 10},
                     {"ep": "Humidite SdB", "type": "humidity", "dp": 2, "div": 10}]}]},
]}

DEVS = {
    "10.0.0.18": FakeDevice("fan000000000000000000", K["fan"], 3.5,
                            {"20": True, "23": 0, "60": False, "62": 2, "63": "forward"}),
    "10.0.0.80": FakeDevice("clamp0000000000000000", K["clamp"], 3.5,
                            {"101": 2350, "131": 2268703, "133": 592}),
    "10.0.0.174": FakeDevice("porch0000000000000000", K["porch"], 3.3,
                             {"20": False, "21": "white", "22": 1000, "23": 0}),
    "10.0.0.15": FakeDevice("radio0000000000000000", K["radio"], 3.5,
                            {"1": False, "2": False, "3": False, "4": False}),
    "10.0.0.31": FakeDevice("perg00000000000000000", K["pergola"], 3.4,
                            {"20": True, "21": "white", "22": 500, "24": "000003e803e8"}),
    "10.0.0.180": FakeDevice("gw0000000000000000000", K["gw"], 3.3, children={
        "00158d0000000001": {"1": False, "18": 0, "19": 0, "20": 2310},
        "00158d0000000002": {"1": 215, "2": 560, "4": 100}}),
}


class Harness:
    def __init__(self):
        self.p = subprocess.Popen(["stdbuf", "-oL", BERRY, "harness.be"], cwd=HERE, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, text=True, bufsize=1)
        self.out = []
        self.read()   # sortie du chargement

    def read(self):
        lines = []
        while True:
            l = self.p.stdout.readline()
            if not l:
                raise RuntimeError("berry s'est arrete :\n" + "\n".join(self.out[-30:] + lines))
            l = l.rstrip("\n")
            if l == "READY":
                break
            lines.append(l)
        self.out += lines
        return lines

    def send(self, line):
        self.p.stdin.write(line + "\n")
        self.p.stdin.flush()
        return self.read()

    def pump(self, lines, rounds=6):
        """Transmet les TX aux faux appareils et renvoie leurs reponses, jusqu'a stabilisation."""
        allout = list(lines)
        pending = list(lines)
        for _ in range(rounds):
            new = []
            for l in pending:
                if l.startswith("CONNECT "):
                    ip = l.split()[1]
                    DEVS[ip].reset_session()
                    new += self.send("OPEN " + ip)
                elif l.startswith("TX "):
                    _, ip, hx = l.split(" ", 2)
                    for r in DEVS[ip].feed(bytes.fromhex(hx)):
                        new += self.send("RX %s %s" % (ip, r.hex()))
            if not new:
                # vider les ecritures partielles en attente
                new = self.send("ADV 50")
                if not any(x.startswith("TX ") for x in new):
                    allout += new
                    break
            allout += new
            pending = new
        return allout

    def close(self):
        self.p.stdin.write("END\n")
        self.p.stdin.flush()
        self.p.wait(5)


def mtr_updates(lines):
    return [json.loads(l[len("CMD MtrUpdate "):]) for l in lines if l.startswith("CMD MtrUpdate ")]


def find(updates, name):
    r = {}
    for u in updates:
        if u.get("Name") == name:
            r.update(u)
    return r


def main():
    with open("/tuya.json", "w") as f:
        json.dump(CONFIG, f)
    h = Harness()
    ok = 0

    # 1. connexion, negociation et etat initial de tous les appareils
    out = h.pump(h.send("ADV 50"))
    errs = [l for l in out if l.startswith("LOG 1") or "erreur" in l]
    assert not errs, errs
    up = mtr_updates(out)
    assert find(up, "Ventilateur") == {"Name": "Ventilateur", "FanSpeed": 0}, find(up, "Ventilateur")
    assert find(up, "Lumiere ventilateur")["Power"] == 1
    assert find(up, "Porche") == {"Name": "Porche", "Power": 0, "Bri": 254, "CT": 500}, find(up, "Porche")
    assert find(up, "Radio 1")["Power"] == 0 and find(up, "Radio 2")["Power"] == 0
    p1 = find(up, "Pergola 1")
    assert p1["Power"] == 1 and p1["Sat"] == 0 and p1["Bri"] == 126, p1
    pl = find(up, "Prise Lisseur")
    assert pl["Power"] == 0 and abs(pl["Voltage"] - 231.0) < 0.01, pl
    t = find(up, "Temperature SdB")
    assert abs(t["Temperature"] - 21.5) < 0.01, t
    assert abs(find(up, "Humidite SdB")["Humidity"] - 56.0) < 0.01
    for ip in ("10.0.0.18", "10.0.0.80", "10.0.0.15", "10.0.0.31"):
        assert any(e[0] == "session" for e in DEVS[ip].log), ip    # negociation 3.4/3.5 faite
    ok += 1
    print("OK 1 connexion + negociation + etat initial (6 appareils, 3.3/3.4/3.5, passerelle)")

    # 2. Matter -> ventilateur 3.5 : vitesse 50 % puis arret
    out = h.pump(h.send('MTR {"ep1":{"Ep":1,"Name":"Ventilateur","FanMode":2,"FanSpeed":50,"FanSpeed255":128}}'))
    fan = DEVS["10.0.0.18"]
    assert fan.dps["60"] is True and fan.dps["62"] == 3, fan.dps
    assert find(mtr_updates(out), "Ventilateur")["FanSpeed"] == 50
    out = h.pump(h.send('MTR {"ep1":{"Ep":1,"Name":"ventilateur","FanMode":0,"FanSpeed":0,"FanSpeed255":0}}'))
    assert fan.dps["60"] is False, fan.dps
    ok += 1
    print("OK 2 Matter -> ventilateur (3.5) : vitesse et arret, retour d'etat")

    # 3. Matter -> ampoule CCT 3.3 : allumage, luminosite, temperature de couleur
    porch = DEVS["10.0.0.174"]
    h.pump(h.send('MTR {"ep3":{"Ep":3,"Name":"Porche","Power":1}}'))
    assert porch.dps["20"] is True
    h.pump(h.send('MTR {"ep3":{"Ep":3,"Name":"Porche","Bri":127,"Dimmer":50}}'))
    assert porch.dps["22"] == 10 + (126 * 990 + 126) // 253, porch.dps
    out = h.pump(h.send('MTR {"ep3":{"Ep":3,"Name":"Porche","CT":153}}'))
    assert porch.dps["23"] == 1000, porch.dps
    assert find(mtr_updates(out), "Porche")["CT"] == 153
    ok += 1
    print("OK 3 Matter -> ampoule CCT (3.3) : on, luminosite, temperature")

    # 4. Matter -> projecteur RGB 3.4 : teinte/saturation puis luminosite en mode couleur
    perg = DEVS["10.0.0.31"]
    out = h.pump(h.send('MTR {"ep5":{"Ep":5,"Name":"Pergola 1","Hue":85,"Sat":254}}'))
    assert perg.dps["21"] == "colour", perg.dps
    assert perg.dps["24"][:8] == "%04x%04x" % ((85 * 360 + 127) // 254, 1000), perg.dps
    u = find(mtr_updates(out), "Pergola 1")
    assert u["Hue"] == 85 and u["Sat"] == 254, u
    h.pump(h.send('MTR {"ep5":{"Ep":5,"Name":"Pergola 1","Bri":254,"Dimmer":100}}'))
    assert perg.dps["24"][8:] == "03e8" and perg.dps["21"] == "colour", perg.dps
    ok += 1
    print("OK 4 Matter -> projecteur RGB (3.4) : couleur et luminosite")

    # 5. passerelle 3.3 : prise Zigbee (cid) commandee depuis Matter, mesures remontees
    gw = DEVS["10.0.0.180"]
    out = h.pump(h.send('MTR {"ep7":{"Ep":7,"Name":"Prise Lisseur","Power":1}}'))
    assert gw.children["00158d0000000001"]["1"] is True
    assert find(mtr_updates(out), "Prise Lisseur")["Power"] == 1
    # mise a jour spontanee de mesures par la passerelle
    push = gw.push({"cid": "00158d0000000001", "dps": {"19": 1234, "18": 5300}, "t": 2})
    out = h.pump(h.send("RX 10.0.0.180 " + push.hex()))
    u = find(mtr_updates(out), "Prise Lisseur")
    assert abs(u["ActivePower"] - 123.4) < 0.01 and abs(u["Current"] - 5.3) < 0.01, u
    ok += 1
    print("OK 5 passerelle Zigbee (3.3, cid) : commande et mesures")

    # 6. releves Tasmota de la pince amperemetrique
    out = h.send("SENSOR")
    app = [l for l in out if l.startswith("APPEND ")][0][len("APPEND "):]
    tele = json.loads("{" + app[1:] + "}")["Tuya"]["Pince"]
    assert abs(tele["Energie"] - 22687.03) < 0.01 and tele["Puissance"] == 592, tele
    assert any("Pince Tension A" in l and "235.0 V" in l for l in out if l.startswith("WEB ")), out
    ok += 1
    print("OK 6 releves SENSOR et page web (pince 3.5)")

    # 7. commande TuyaSend et TuyaStatus
    out = h.pump(h.send("CMD TuyaSend Recepteur radio,3,true"))
    assert DEVS["10.0.0.15"].dps["3"] is True
    out = h.send("CMD TuyaStatus")
    st = json.loads([l for l in out if l.startswith("RESP ")][0][5:])["TuyaStatus"]
    assert st["Recepteur radio"]["Connected"] and st["Recepteur radio"]["Dps"]["3"] is True, st
    assert st["Prise Lisseur"]["Dps"]["19"] == 1234
    ok += 1
    print("OK 7 TuyaSend / TuyaStatus")

    # 8. heartbeat toutes les 10 s, coupure, reconnexion avec nouvelle negociation
    hb0 = fan.hb
    out = h.pump(h.send("ADV 10500"))
    assert fan.hb > hb0, (fan.hb, hb0)
    out = h.send("DROP 10.0.0.18")
    out += h.send("ADV 100")
    assert any(l.startswith("CLOSE 10.0.0.18") for l in out), out
    out = h.pump(h.send("ADV 6000"))
    assert any(l.startswith("CONNECT 10.0.0.18") for l in out), out
    sessions = [e for e in fan.log if e[0] == "session"]
    assert len(sessions) >= 2, sessions
    h.pump(h.send('MTR {"ep1":{"Ep":1,"Name":"Ventilateur","FanMode":3,"FanSpeed":100,"FanSpeed255":255}}'))
    assert fan.dps["60"] is True and fan.dps["62"] == 6, fan.dps
    ok += 1
    print("OK 8 heartbeat, coupure et reconnexion (nouvelle cle de session)")

    # 9. appareil muet : deconnexion apres 35 s sans reponse
    radio_ip = "10.0.0.15"
    saved = DEVS[radio_ip].feed
    DEVS[radio_ip].feed = lambda d: []
    out = []
    for _ in range(8):
        out += h.pump(h.send("ADV 5000"))
    assert any("Recepteur radio" in l and "plus de reponse" in l for l in out), [l for l in out if "LOG" in l][-5:]
    DEVS[radio_ip].feed = saved
    ok += 1
    print("OK 9 detection d'un appareil muet")

    # 10. trame corrompue : rejetee sans planter
    bad = bytearray(gw.push({"cid": "00158d0000000002", "dps": {"1": 300}}))
    bad[-10] ^= 0xFF
    out = h.send("RX 10.0.0.180 " + bytes(bad).hex())
    assert any("CRC invalide" in l for l in out), out
    good = gw.push({"cid": "00158d0000000002", "dps": {"1": 199}})
    out = h.pump(h.send("RX 10.0.0.180 " + good.hex()))
    assert abs(find(mtr_updates(out), "Temperature SdB")["Temperature"] - 19.9) < 0.01
    ok += 1
    print("OK 10 trame corrompue rejetee, la suivante est traitee")

    # 11. trame recue en deux morceaux, puis deux trames dans le meme paquet (3.5)
    f1 = DEVS["10.0.0.18"].push({"protocol": 4, "t": 3, "data": {"dps": {"20": False}}})
    f2 = DEVS["10.0.0.18"].push({"protocol": 4, "t": 4, "data": {"dps": {"62": 4}}})
    out = h.send("RX 10.0.0.18 " + f1[:23].hex())
    assert not mtr_updates(out), out
    out = h.send("RX 10.0.0.18 " + f1[23:].hex())
    assert find(mtr_updates(out), "Lumiere ventilateur")["Power"] == 0, out
    out = h.send("RX 10.0.0.18 " + (f2 + f1).hex())
    assert find(mtr_updates(out), "Ventilateur")["FanSpeed"] == 67, mtr_updates(out)
    ok += 1
    print("OK 11 trame fragmentee et trames groupees")

    # 12. endpoint Matter absent : le refus de MtrUpdate est signale dans le journal
    h.close()
    cfg = json.loads(json.dumps(CONFIG))
    cfg["devices"][3]["matter"][0]["ep"] = "Inconnu"
    with open("/tuya.json", "w") as f:
        json.dump(cfg, f)
    h = Harness()
    out = h.pump(h.send("ADV 50"))
    assert any("endpoint Matter 'Inconnu' : Invalid Device" in l for l in out), [l for l in out if "LOG" in l]
    ok += 1
    print("OK 12 endpoint Matter absent signale")

    # 13. endpoint Matter cree apres le demarrage du driver : renvoi de l'etat complet toutes
    # les 30 s tant qu'il est refuse, signale une seule fois, puis plus rien une fois accepte
    def adv(ms):
        out = []
        for _ in range(ms // 10000):
            out += h.pump(h.send("ADV 10000"))
        return out
    out = adv(30000)
    assert find(mtr_updates(out), "Inconnu") == {"Name": "Inconnu", "Power": 0}, mtr_updates(out)
    assert not any("'Inconnu'" in l for l in out if l.startswith("LOG")), "refus signale deux fois"
    h.send("EPADD Inconnu")                       # l'endpoint est cree dans Configuration -> Matter
    out = adv(30000)
    assert find(mtr_updates(out), "Inconnu") == {"Name": "Inconnu", "Power": 0}, mtr_updates(out)
    assert any("endpoint Matter 'Inconnu' disponible" in l for l in out), [l for l in out if "LOG" in l]
    out = adv(30000)
    assert find(mtr_updates(out), "Inconnu") == {}, "endpoint accepte : plus de renvoi"
    push = DEVS["10.0.0.15"].push({"protocol": 4, "t": 5, "data": {"dps": {"1": True}}})
    out = h.pump(h.send("RX 10.0.0.15 " + push.hex()))
    assert find(mtr_updates(out), "Inconnu") == {"Name": "Inconnu", "Power": 1}, mtr_updates(out)
    ok += 1
    print("OK 13 endpoint Matter cree apres coup : etat envoye sans redemarrage")

    h.close()
    print("%d/13 scenarios OK" % ok)


if __name__ == "__main__":
    main()
