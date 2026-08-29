# Stack IA — installation

Une seule commande, dans le terminal WSL Ubuntu (clean install OK) :

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sofalost/stack-hugo/master/install-stack.sh)
```

Aucun prérequis Docker : le script n'installe/ne gère plus le conteneur 9router lui-même — c'est la fonction `sofalost` qui s'en charge (à la relance du shell, si un conteneur `9router` existe déjà). (`curl`/`git` absents ? Le script les installe.)

Pendant l'exécution, le script demande :
- si tu as déjà un **conteneur Docker `9router`** (o/N) — conditionne l'étape Skills ;
- le **mot de passe sudo** une seule fois (ensuite plus jamais).

## Ce que fait le script, étape par étape

1. **Skills** — si le dossier `skills-bundle/` n'est pas à côté du script : installe curl/git si besoin, clone ce repo (public, sans auth).
2. **Conteneur 9router ?** — demande si un conteneur Docker nommé `9router` existe déjà. Réponse gardée dans `HAS_9ROUTER`, utilisée à l'étape Skills. Si non : les skills 9router sont ignorés (rien d'autre n'est skippé).
3. **Sudo sans mot de passe** — enregistre `NOPASSWD` dans `/etc/sudoers.d/`. Plus jamais de mot de passe, ni pour ce script ni pour `sofalost`.
4. **Dépendances système** — curl, git, rsync, python3, build-essential, jq, ripgrep, gh (CLI GitHub), Node.js 22.
5. **Les 6 applis** — Claude Code, OpenClaw, Codex, OpenCode, Hermes, dsh + Scrapling MCP (via uv). Skip si déjà installées.
6. **Skills** — déploie les 33 skills dans 5 dossiers (claude, hermes, opencode, codex, agents). Les skills extraits des plugins Claude Code (frontend-design, ui-ux-pro-max, obsidian ×5) ne sont PAS déployés dans claude (déjà présents via les plugins), mais le sont dans les 4 autres dossiers. Visibles aussi dans **dsh** (le profil web désactive le plugin par défaut ; le script le réactive via `~/.dsh/profiles/web/cordis.patch.yml`) et dans **OpenClaw** (installés un par un via sa CLI).
   Si tu as répondu **oui** à l'étape 2 : télécharge en plus les 4 skills 9router depuis GitHub (9router, 9router-chat, 9router-image, 9router-tts).
7. **Plugins Claude Code** — installe sur Claude Code (uniquement — aucun mirroring vers les 5 autres CLI) les 7 plugins présents sur la machine de Hugo : frontend-design, obsidian, ui-ux-pro-max, superpowers, bitwize-music, phantom, claude-hud (+ configuration de sa statusLine).
8. **Fonction `sofalost`** — ajoutée dans `~/.bashrc` : update complet (Ubuntu + 6 applis + skills + image 9router avec données préservées si un conteneur existe déjà) puis menu de lancement 1-6.

Le script se termine par `exec bash` : le shell est rechargé automatiquement, pas besoin de le faire à la main.

## Après

```bash
sofalost       # update complet + menu de lancement (1-6)
```

La configuration des 6 applis sur 9router (base URL, clé API) et la gestion du conteneur lui-même ne sont plus faites par ce script — c'est entièrement à la charge de `sofalost`.
