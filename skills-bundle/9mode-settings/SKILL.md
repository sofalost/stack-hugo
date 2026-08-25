---
name: 9mode-settings
description: Use at the start of every user turn to apply RTK/Caveman/Ponytail settings via 9auto.py. Triggers whenever a new user prompt arrives, before any other action — these are global 9router settings (docker, port 20128) controlling tool-output compression (RTK), LLM-output style (Caveman), and code style (Ponytail).
---

# 9mode-settings

## Pourquoi

RTK, Caveman et Ponytail sont trois leviers GLOBAUX du 9router (affectent tous
les clients : autres sessions, crons planifiés). Chacun a un booléen ET un
niveau indépendants — `cavemanEnabled=False` n'efface pas `cavemanLevel`, un
OFF est un vrai filtre coupé, pas un niveau bas. Le pilotage réel est déjà
codé dans `~/.9mode/9mode.py` (garde cron + bail expirant 45 min + filet
60 min) et `~/.9mode/9auto.py` (wrapper : classe, applique, relit). Cette
skill ne duplique pas cette logique — elle pointe vers les scripts.

## Étape 1 — à chaque nouveau prompt, avant tout le reste

```
python3 ~/.9mode/9auto.py "<le prompt de l'utilisateur, verbatim>"
```

Citer la ligne de sortie telle quelle en tête de réponse, ex :
```
Settings : profil=code | RTK on, Caveman lite, Ponytail full
```

**Interdit absolu : annoncer un settings sans avoir lancé le script.**
Réciter de mémoire = faux positif déjà constaté (réglages annoncés, jamais
appliqués). 9auto.py relit l'état après application précisément pour ça —
ne pas court-circuiter la relecture.

Les réglages dépendent de la TÂCHE, pas du modèle 9router utilisé — il
n'existe aucune matrice par modèle. Toute doc qui prétend le contraire est
périmée.

## Les 8 profils

Source de vérité : `python3 ~/.9mode/9mode.py profils`.

| Profil | RTK | Caveman | Ponytail | Quand |
|---|---|---|---|---|
| baseline | on | lite | lite | défaut permanent |
| lecture | on | full | lite | audit, synthèse longue, lecture de logs/doc |
| code | on | lite | full | implémentation, refactor, gros diff |
| code-strict | on | full | ultra | spike, prototype jetable, one-shot |
| debug | OFF | OFF | lite | debug fin, trace d'erreur à lire intégralement |
| redaction | on | OFF | OFF | explication pédagogique, doc, texte lu tel quel |
| brut | OFF | OFF | OFF | sortie non filtrée : comparer, reproduire |
| citation | OFF | OFF | lite | citer/restituer fidèlement, verbatim, légal |

## Fin de tâche longue

Rendre le baseline dès la fin d'un gros bloc de code plutôt que compter sur
le bail :
```
python3 ~/.9mode/9mode.py baseline
```

## Pitfalls

- **"REFUS : le cron '<nom>' tourne dans les 3 min"** → NE PAS passer
  `--forcer`. Rester au baseline, le dire en une ligne.
- **"9router injoignable"** → dire que les settings n'ont pas été appliqués,
  ne rien inventer. Ne JAMAIS `stop`/`rm` le conteneur 9router (seul accès
  de l'utilisateur à ses providers IA). Restart toléré, suppression jamais
  sans confirmation explicite.
- **"Settings : appliqués mais RELECTURE IMPOSSIBLE"** → traiter comme
  incertain, étiqueter le doute.
- **Concurrence** : d'autres clients du 9router peuvent changer ces mêmes
  réglages en parallèle. `9auto.py` est idempotent (PATCH seulement si la
  valeur change) donc un double appel est sans danger, mais l'affichage
  d'une session peut être périmé si un autre client a rebasculé entre-temps.
  `python3 ~/.9mode/9mode.py etat` tranche. Ne jamais demander la permission
  de basculer : appliquer, puis signaler en une ligne.
