#!/usr/bin/env python3
# 9mode.py — pilote les settings globaux du 9router (RTK / Caveman / Ponytail)
# Re-créé le 2026-08-26 (originaux perdus lors du cleanup du 24/08).
# Usage :
#   9mode.py etat                    — lit l'état courant
#   9mode.py profils                 — liste les 8 profils
#   9mode.py <profil>                — applique un profil (baseline, code, ...)
#   9mode.py set <cle> <val>         — force une clé (rtkEnabled, cavemanLevel...)
#   9mode.py baseline                — retour au profil par défaut
# Auth : header x-9r-cli-token = sha256(machine-id + "9r-cli-auth" + cli-secret)[:16]
# (logique inverseée du middleware Next du conteneur, fichiers dans le volume).
import json, sys, subprocess, hashlib, urllib.request

URL = "http://127.0.0.1:20128/api/settings"

PROFILS = {
    #            rtk,        caveman,          ponytail
    "baseline":    {"rtkEnabled": True,  "cavemanEnabled": True,  "cavemanLevel": "lite", "ponytailEnabled": True,  "ponytailLevel": "lite"},
    "lecture":     {"rtkEnabled": True,  "cavemanEnabled": True,  "cavemanLevel": "full", "ponytailEnabled": True,  "ponytailLevel": "lite"},
    "code":        {"rtkEnabled": True,  "cavemanEnabled": True,  "cavemanLevel": "lite", "ponytailEnabled": True,  "ponytailLevel": "full"},
    "code-strict": {"rtkEnabled": True,  "cavemanEnabled": True,  "cavemanLevel": "full", "ponytailEnabled": True,  "ponytailLevel": "ultra"},
    "debug":       {"rtkEnabled": False, "cavemanEnabled": False, "cavemanLevel": "lite", "ponytailEnabled": True,  "ponytailLevel": "lite"},
    "redaction":   {"rtkEnabled": True,  "cavemanEnabled": False, "cavemanLevel": "lite", "ponytailEnabled": False, "ponytailLevel": "lite"},
    "brut":        {"rtkEnabled": False, "cavemanEnabled": False, "cavemanLevel": "lite", "ponytailEnabled": False, "ponytailLevel": "lite"},
    "citation":    {"rtkEnabled": False, "cavemanEnabled": False, "cavemanLevel": "lite", "ponytailEnabled": True,  "ponytailLevel": "lite"},
}

def token():
    """x-9r-cli-token : sha256(machine-id + sel + cli-secret)[:16]."""
    def read(path):
        return subprocess.run(["docker", "exec", "9router", "cat", path],
                              capture_output=True, text=True).stdout.strip()
    mid = read("/app/data/machine-id")
    sec = read("/app/data/auth/cli-secret")
    if not mid or not sec:
        return None
    return hashlib.sha256((mid + "9r-cli-auth" + sec).encode()).hexdigest()[:16]

def api(method="GET", body=None):
    t = token()
    if not t:
        return None, "9router injoignable (docker exec 9router impossible)"
    req = urllib.request.Request(URL, method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"x-9r-cli-token": t, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.load(r), None
    except Exception as e:
        return None, f"9router injoignable ({e})"

def etat():
    d, err = api()
    if err: return print("ERREUR:", err)
    print(json.dumps({k: d.get(k) for k in
        ["rtkEnabled", "cavemanEnabled", "cavemanLevel",
         "ponytailEnabled", "ponytailLevel"]}, indent=1))

def profil_courant(d):
    """Cherche quel profil correspond à l'état courant (None sinon)."""
    for nom, p in PROFILS.items():
        if all(d.get(k) == v for k, v in p.items()):
            return nom
    return None

def applique(nom):
    p = PROFILS[nom]
    d, err = api()  # relecture : PATCH uniquement si la valeur change
    if err: return print("ERREUR:", err)
    delta = {k: v for k, v in p.items() if d.get(k) != v}
    if delta:
        _, err = api("PATCH", delta)
        if err: return print("ERREUR:", err)
    d2, err = api()  # relecture après application (ne pas court-circuiter)
    if err:
        return print(f"Settings : appliqués mais RELECTURE IMPOSSIBLE ({err})")
    print(f"Settings : profil={nom} | RTK {'on' if d2['rtkEnabled'] else 'off'},"
          f" Caveman {'off' if not d2['cavemanEnabled'] else d2['cavemanLevel']},"
          f" Ponytail {'off' if not d2['ponytailEnabled'] else d2['ponytailLevel']}")

def main():
    if len(sys.argv) < 2:
        return etat()
    cmd = sys.argv[1]
    if cmd == "etat": return etat()
    if cmd == "profils":
        print(f"{'profil':<12} RTK      Caveman   Ponytail")
        for n, p in PROFILS.items():
            rtk = "on" if p["rtkEnabled"] else "OFF"
            cav = p["cavemanLevel"] if p["cavemanEnabled"] else "OFF"
            pon = p["ponytailLevel"] if p["ponytailEnabled"] else "OFF"
            print(f"{n:<12} {rtk:<8} {cav:<9} {pon}")
        return
    if cmd == "set":
        if len(sys.argv) < 4: return print("usage: set <cle> <val>")
        _, err = api("PATCH", {sys.argv[2]: sys.argv[3]})
        return print("OK" if not err else f"ERREUR: {err}")
    if cmd in PROFILS: return applique(cmd)
    print(f"Profil inconnu : {cmd}. Profils : {', '.join(PROFILS)}")

if __name__ == "__main__":
    main()
