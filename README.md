# Stack IA — installation

Une seule commande, dans le terminal WSL Ubuntu (clean install OK) :

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sofalost/stack-hugo/master/install-stack.sh)
```

Prérequis : **Docker Desktop** installé sur Windows, avec Settings → Resources → WSL Integration → « Integrate with my default WSL distro » activé. (`curl`/`git` absents ? Le script les installe.)

Pendant l'exécution, le script demande :
- le **mot de passe sudo** une seule fois (ensuite plus jamais) ;
- la **clé API 9router** à la fin : crée-la sur http://127.0.0.1:20128 (Dashboard → Keys).

## Ce que fait le script, étape par étape

1. **Skills** — si le dossier `skills-bundle/` n'est pas à côté du script : installe curl/git si besoin, clone ce repo.
2. **Docker** — vérifie que Docker est disponible (via Docker Desktop), sinon stoppe avec les instructions.
3. **Sudo sans mot de passe** — enregistre `NOPASSWD` dans `/etc/sudoers.d/`. Plus jamais de mot de passe.
4. **Dépendances système** — curl, git, rsync, python3, build-essential, jq, ripgrep, gh (CLI GitHub), Node.js 22.
5. **Les 6 applis** — Claude Code, OpenClaw, Codex, OpenCode, Hermes, dsh + Scrapling MCP (via uv). Skip si déjà installées.
6. **Conteneur 9router** — réseau `ai-network`, volume `9router-data`, image `decolua/9router` sur le port 20128. Backup des données dans `~/.9router-backup/` avant toute recréation ; restauration auto si le volume est vide ; rollback si la nouvelle image ne démarre pas.
7. **Démarrage + seed** — attend que 9router réponde, pré-crée les **12 combos** (9deepseek, 9fable, 9gemini, 9glm, 9gpt, 9haiku, 9kimi, 9minimax, 9opus, 9oxalpha, 9qwen, 9sonnet — modèles vides, à remplir dans le dashboard), déploie les **scripts 9mode** (`~/.9mode/9mode.py` + `9auto.py` : pilotage RTK/Caveman/Ponytail), ouvre le dashboard dans le navigateur.
8. **Skills** — déploie les 28 skills dans 5 dossiers (claude, hermes, opencode, codex, agents) + les 4 skills 9router téléchargés depuis GitHub + install dans OpenClaw. Les skills sont ainsi visibles aussi dans **dsh** (le profil web désactive le plugin par défaut ; le script le réactive via `~/.dsh/profiles/web/cordis.patch.yml`).
9. **Config des 6 applis** — tout pointe sur 9router, modèle par défaut **9haiku 256K** : Claude Code (+ plugin claude-hud), OpenClaw, Codex, OpenCode, Hermes, dsh. Backups `.bak-stack` avant chaque modification.
10. **Clé API** — te la demande, la valide, l'écrit dans toutes les configs + `~/.bashrc` (`CODEROUTER_API_KEY`).
11. **Fonction `sofalost`** — dans `~/.bashrc` : update complet (Ubuntu + 6 applis + skills + image 9router avec données préservées) puis menu de lancement 1-6.

## Après

```bash
exec bash      # recharge le shell
sofalost       # update complet + menu de lancement (1-6)
```
