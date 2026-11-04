# github_ota.be : mise a jour automatique du firmware depuis les Releases GitHub
#
# Chaque nuit, lit version.json dans la derniere release du depot et, si son numero
# de build est plus recent que celui du firmware en cours, lance la mise a jour OTA
# (le module redemarre en safeboot, telecharge le .bin puis redemarre).
#
# Installation : envoyer ce fichier dans le systeme de fichiers du module
# (Outils -> Gestion du systeme de fichiers) et ajouter dans autoexec.be :
#   load("github_ota.be")
#
# Commandes ajoutees :
#   OtaCheck     verifie maintenant et installe si une version plus recente existe
#   OtaCheck 0   verifie seulement, sans rien installer

import json
import string

class GithubOta
  var repo      # depot GitHub qui publie les releases
  var image     # CODE_IMAGE_STR du firmware, suivi de ".<build>" dans les releases
  var bin       # nom du firmware dans les releases
  var cron      # frequence de verification (secondes minutes heures jour mois jour_semaine)

  def init()
    self.repo  = "gnatali/tasmota-zbbridge-matter"
    self.image = "zbbrdgpro-matter"
    self.bin   = "tasmota32-zbbrdgpro-matter.bin"
    self.cron  = "0 30 3 * * *"       # tous les jours a 3h30, heure locale du module

    tasmota.remove_cron("github_ota")
    tasmota.add_cron(self.cron, / -> self.check(true), "github_ota")
    tasmota.add_cmd("OtaCheck", / cmd, idx, payload -> self.cmd_check(payload))
  end

  def release_url(file)
    return "https://github.com/" + self.repo + "/releases/latest/download/" + file
  end

  # Numero de build du firmware en cours : "16.0.0.2(zbbrdgpro-matter.12)" -> 12
  # 0 pour un firmware sans numero (compilation locale, ou anterieure a ce script)
  def local_build()
    var version = tasmota.cmd("Status 2", true)['StatusFWR']['Version']
    var marker = self.image + "."
    var i = string.find(version, marker)
    if i < 0 return 0 end
    var s = version[i + size(marker) ..]
    var j = string.find(s, ")")
    if j > 0 s = s[0 .. j - 1] end
    return int(s)
  end

  # Contenu de version.json de la derniere release, ou nil en cas d'echec
  def remote_info()
    var cl = webclient()
    cl.set_follow_redirects(true)     # github.com redirige vers le stockage des releases
    cl.begin(self.release_url("version.json"))
    var code = cl.GET()
    var body = (code == 200) ? cl.get_string() : nil
    cl.close()
    if body == nil
      log(f"OTA: version.json inaccessible (HTTP {code})", 2)
      return nil
    end
    var info = json.load(body)
    if !isinstance(info, map)
      log("OTA: version.json invalide", 2)
      return nil
    end
    return info
  end

  def check(install)
    var info
    try
      info = self.remote_info()
    except .. as e, m
      log(f"OTA: erreur {e} {m}", 2)
    end
    if info == nil return nil end

    var local = self.local_build()
    var remote = int(info.find('build', 0))
    var tag = info.find('tag', '?')
    log(f"OTA: build installe {local}, derniere release {remote} ({tag})", 2)

    if install && remote > local
      log(f"OTA: mise a jour vers {tag}", 2)
      tasmota.cmd("OtaUrl " + self.release_url(self.bin))
      tasmota.cmd("Upgrade 1")
    end
    return {'installed': local, 'latest': remote, 'tag': tag, 'update': remote > local}
  end

  def cmd_check(payload)
    var r = self.check(payload != "0")
    if r == nil
      tasmota.resp_cmnd_error()
    else
      tasmota.resp_cmnd(json.dump(r))
    end
  end
end

github_ota = GithubOta()
