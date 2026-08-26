#!/usr/bin/env python3
# 9auto.py — wrapper : classe le prompt, applique le profil, relit l'état.
# Re-créé le 2026-08-26 avec 9mode.py (originaux perdus au cleanup du 24/08).
# Usage : python3 ~/.9mode/9auto.py "<le prompt de l'utilisateur, verbatim>"
import subprocess, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Mots-clés (insensible à la casse, FR+EN) → profil. Premier match gagne.
REGLES = [
    ("code-strict", ["spike", "prototype", "one-shot", "jetable"]),
    ("debug",       ["debug", "trace", "stack trace", "erreur intégrale", "log complet", "pourquoi ça casse"]),
    ("redaction",   ["explique", "vulgarise", "pedagog", "documente", "tutoriel", "rédige un guide", "expliquer à"]),
    ("citation",    ["cite", "verbatim", "restitue", "citation", "mot pour mot"]),
    ("brut",        ["sortie brute", "sans filtre", "reproduis exactement", "compare les sorties"]),
    ("lecture",     ["audit", "synthèse", "synthese", "résume", "lis les logs", "revue de code", "code review", "analyse le doc"]),
    ("code",        ["implémente", "implemente", "refactor", "écris le code", "code", "fonction", "script", "fix", "corrige", "test", "classe", "composant", "api"]),
]
BASIQUE = ["bonjour", "merci", "ça va", "ok", "oui", "non"]  # → baseline, pas de bascule utile

def classe(prompt):
    p = prompt.lower()
    if any(p.startswith(m) for m in BASIQUE) and len(p) < 30:
        return "baseline"
    for profil, mots in REGLES:
        if any(m in p for m in mots):
            return profil
    return "code"  # défaut raisonnable pour une session de dev

def main():
    prompt = " ".join(sys.argv[1:]) or "baseline"
    profil = classe(prompt)
    r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "9mode.py"), profil],
                       capture_output=True, text=True)
    out = (r.stdout or r.stderr).strip()
    print(f"Profil détecté : {profil}")
    print(out)

if __name__ == "__main__":
    main()
