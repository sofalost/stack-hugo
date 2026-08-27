#!/usr/bin/env bash
# ============================================================================
# Stack IA de Hugo — installateur pour potes (WSL2 Ubuntu)
# Usage : bash <(curl -fsSL https://raw.githubusercontent.com/sofalost/stack-hugo/master/install-stack.sh)
# (le script se suffit à lui-même : il clone le repo public sofalost/stack-hugo
# pour récupérer les 33 skills si besoin)
# Ce que fait le script : 1) installe tout (6 applis, skills, conteneur 9router)
# 2) configure les 6 applis sur 9router 3) à la fin, demande la clé API et
# termine la config 4) ajoute la fonction `sofalost` dans ~/.bashrc.
# Prérequis : Windows + Docker Desktop avec intégration WSL activée.
# ============================================================================
set -uo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skills-bundle"
REPO="https://github.com/sofalost/stack-hugo.git"

# Log complet de l'install (à envoyer à Hugo en cas de problème).
LOG_FILE="$HOME/stack-hugo-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo ""
echo "════════ install-stack.sh — $(date '+%Y-%m-%d %H:%M:%S') ════════"

# Même en cas d'échec (die), le pote sait où est le log à envoyer.
trap '[ $? -ne 0 ] && printf "\033[1;33m→ Log complet : %s\033[0m\n" "$LOG_FILE"' EXIT

WARN_COUNT=0
say()  { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✅ %s\033[0m\n' "$*"; }
warn() { WARN_COUNT=$((WARN_COUNT+1)); printf '\033[1;33m⚠️ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m❌ %s\033[0m\n' "$*" >&2; exit 1; }

# Ce script cible Ubuntu/Debian (apt-get) sous WSL2 — échec clair et tôt sinon.
if ! command -v apt-get >/dev/null 2>&1; then
  die "Script prévu pour Ubuntu/Debian (WSL2). OS détecté : $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo inconnu)."
fi

# Chaque section continue en cas d'échec non fatal, comme la vraie sofalost.
# set -e est volontairement absent : on veut un installateur robuste, pas un
# installateur qui meurt à la première commande inconnue.

# ============================================================================
# Pré-requis — Skills : bundle local ou clonage du repo (public, sans gh)
# ============================================================================
if [ ! -d "$BUNDLE_DIR" ]; then
  # Dépendances minimales AVANT tout usage de curl/git : sur un Ubuntu clean,
  # ils sont absents au démarrage du script (installés à l'étape 2, trop tard).
  if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    echo "Entre ton mot de passe sudo pour installer curl + git :"
    sudo -v || die "sudo refusé."
    sudo apt-get update -y >/dev/null 2>&1
    sudo apt-get install -y curl git >/dev/null 2>&1 || die "Impossible d'installer curl/git (requis pour cloner le repo)."
  fi
  say "Skills : clonage du repo sofalost/stack-hugo (public, sans auth)"
  rm -rf /tmp/stack-hugo
  git clone --depth 1 "$REPO" /tmp/stack-hugo \
    && BUNDLE_DIR="/tmp/stack-hugo/skills-bundle" \
    && NMODE_DIR="/tmp/stack-hugo/9mode" \
    && ok "Repo cloné (33 skills + scripts 9mode)." \
    || die "Clonage sofalost/stack-hugo échoué (réseau ?)."
fi
[ -d "$BUNDLE_DIR" ] || die "Skills introuvables (bundle ou repo)."

NR_URL="http://127.0.0.1:20128"
# Version pinée pour les NOUVELLES installs (dernière vérifiée bonne, 2026-08-14).
# Les conteneurs existants et sofalost restent sur :latest (chemin d'upgrade).
NR_TAG="0.5.55"
# Volume des données 9router (clés API, config) — le même pour tout le script,
# que le conteneur existe déjà ou soit (re)créé : les données survivent toujours.
NR_VOL="9router-data"
NR_RUN_ARGS=(--restart always --network ai-network -p 20128:20128 -v "$NR_VOL":/app/data)
# Dossier 9mode (9mode.py + 9auto.py) : à côté du script ou cloné avec le repo.
NMODE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/9mode"

# Sauvegarde les données de /app/data du conteneur vers ~/.9router-backup/
# (couvre le cas : ancien conteneur sans volume → données dans sa couche, que
# docker rm détruirait). Idempotent : écrase la sauvegarde précédente.
nr_backup() {
  docker exec 9router tar -C /app/data -cf - . 2>/dev/null | { mkdir -p "$HOME/.9router-backup"; tar -C "$HOME/.9router-backup" -xf -; } \
    && ok "Backup 9router → ~/.9router-backup ($(du -sh "$HOME/.9router-backup" 2>/dev/null | cut -f1))" \
    || warn "Backup 9router KO (conteneur démarré ?)."
}

# Vrai si le volume 9router-data contient déjà des données (db sqlite présente).
nr_vol_vide() { [ -z "$(docker run --rm -v "$NR_VOL":/app/data --entrypoint ls decolua/9router:"$NR_TAG" -A /app/data/db 2>/dev/null)" ]; }

# ============================================================================
# 0. Docker Desktop
# ============================================================================
say "Étape 0/9 — Docker"
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker n'est pas disponible dans ce WSL."
  echo "  1. Télécharge Docker Desktop : https://docker.com/products/docker-desktop/"
  echo "  2. Installe-le sur Windows, active Settings → Resources → WSL Integration"
  echo "     → « Integrate with my default WSL distro »."
  echo "  3. Relance ce script."
  die "Docker requis."
fi
ok "Docker présent."

# ============================================================================
# 1. Sudo sans mot de passe (demandé une seule fois ici)
# ============================================================================
say "Étape 1/9 — Sudo sans mot de passe"
if sudo -n true 2>/dev/null; then
  ok "Sudo sans mot de passe déjà actif."
else
  echo "Entre ton mot de passe sudo (une seule fois — ensuite plus jamais,"
  echo "ni pour ce script, ni pour sofalost) :"
  sudo -v || die "sudo refusé."
  if [ -f "/etc/sudoers.d/$USER" ] && grep -qx "$USER ALL=(ALL) NOPASSWD:ALL" "/etc/sudoers.d/$USER" 2>/dev/null; then
    ok "Déjà enregistré."
  else
    echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/$USER" >/dev/null \
      && sudo chmod 440 "/etc/sudoers.d/$USER" \
      && ok "Sudo NOPASSWD enregistré pour $USER." \
      || warn "Écriture sudoers échouée — le mot de passe sera demandé."
  fi
fi
sudo -n true 2>/dev/null || warn "sudo -n KO — vérifie /etc/sudoers.d/$USER."

# ============================================================================
# 2. Dépendances système
# ============================================================================
say "Étape 2/9 — Dépendances système"
sudo apt-get update -y
# gh (CLI GitHub) — repo officiel car absent des dépôts Ubuntu 20.04
if ! command -v gh >/dev/null 2>&1; then
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -y >/dev/null 2>&1
fi
sudo apt-get install -y curl git rsync python3 python3-pip build-essential \
  ca-certificates gnupg unzip jq ripgrep gh
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
node --version || die "Node.js requis."
ok "Dépendances installées."

# ============================================================================
# 3. Les 6 applis
# ============================================================================
say "Étape 3/9 — Installation des 6 applis"

if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash || warn "Claude Code : install KO"
fi
command -v claude >/dev/null 2>&1 && ok "Claude Code" || warn "Claude Code absent."

if ! command -v openclaw >/dev/null 2>&1; then
  # --no-onboard : sans lui, l'installer lance openclaw onboard + le dashboard
  # en plein milieu du script ( comportement signalé par un pote).
  curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard --no-prompt \
    || npm install -g openclaw \
    || warn "OpenClaw : install KO"
fi
command -v openclaw >/dev/null 2>&1 && ok "OpenClaw" || warn "OpenClaw absent."

if ! command -v codex >/dev/null 2>&1; then
  npm install -g @openai/codex || warn "Codex : install KO"
fi
command -v codex >/dev/null 2>&1 && ok "Codex" || warn "Codex absent."

if ! command -v opencode >/dev/null 2>&1; then
  curl -fsSL https://opencode.ai/install | bash || npm install -g opencode-ai || warn "OpenCode : install KO"
fi
command -v opencode >/dev/null 2>&1 && ok "OpenCode" || warn "OpenCode absent."

if ! command -v hermes >/dev/null 2>&1; then
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash || warn "Hermes : install KO"
fi
command -v hermes >/dev/null 2>&1 && ok "Hermes Agent" || warn "Hermes absent."

if ! command -v dsh >/dev/null 2>&1; then
  npm install -g @deepseek-ai/dsh || warn "dsh : install KO"
fi
command -v dsh >/dev/null 2>&1 && ok "DeepSeek Harness (dsh)" || warn "dsh absent."

# --- Scrapling MCP (uv tool install) -----------------------------------------
if ! command -v scrapling-mcp >/dev/null 2>&1; then
  if ! command -v uv >/dev/null 2>&1; then
    curl -fsSL https://astral.sh/uv/install.sh | bash || warn "uv : install KO"
    export PATH="$HOME/.local/bin:$PATH"
  fi
  uv tool install "scrapling[ai]" || warn "Scrapling MCP : install KO"
fi
command -v scrapling-mcp >/dev/null 2>&1 \
  && ok "Scrapling MCP ($(command -v scrapling-mcp))" \
  || warn "scrapling-mcp absent (requis pour le MCP de scraping)."

# ============================================================================
# 4. Conteneur 9router
# ============================================================================
say "Étape 4/9 — Conteneur 9router"
for i in {1..30}; do docker info >/dev/null 2>&1 && break; sleep 1; done
docker info >/dev/null 2>&1 || die "Docker indisponible (Docker Desktop lancé ?)."

docker network create ai-network >/dev/null 2>&1

if docker ps -a --format '{{.Names}}' | grep -qx '9router'; then
  ok "Conteneur 9router déjà présent."
  nr_backup
  # Mise à jour de l'image même si le conteneur existe (données préservées :
  # elles vivent sur le volume 9router-data, pas dans le conteneur).
  say "Update image 9router..."
  img_avant=$(docker inspect 9router --format '{{.Image}}' 2>/dev/null)
  if docker pull decolua/9router:latest; then
    img_apres=$(docker image inspect decolua/9router:latest --format '{{.Id}}' 2>/dev/null)
    if [ "$img_avant" != "$img_apres" ]; then
      echo "⬆️ Nouvelle image — recréation du conteneur..."
      docker tag decolua/9router:latest decolua/9router:stack-rollback >/dev/null 2>&1
      docker stop 9router >/dev/null 2>&1
      docker rm 9router >/dev/null 2>&1
      docker run -d --name 9router "${NR_RUN_ARGS[@]}" decolua/9router:latest >/dev/null \
        && ok "9router recréé sur la nouvelle image (données préservées)." \
        || die "Recréation 9router échouée — rollback : docker run -d --name 9router ${NR_RUN_ARGS[*]} decolua/9router:stack-rollback"
    else
      ok "Image 9router déjà à jour."
    fi
  else
    warn "docker pull KO — conteneur existant conservé."
  fi
else
  docker volume create 9router-data >/dev/null 2>&1
  # Restauration : si le volume est vide mais qu'un backup existe (ancien
  # conteneur créé sans volume → données perdues par docker rm), on les remet.
  if nr_vol_vide && [ -f "$HOME/.9router-backup/db/data.sqlite" ]; then
    say "Volume vide + backup détecté → restauration des données..."
    docker run --rm -v "$NR_VOL":/app/data -v "$HOME/.9router-backup":/backup \
      --entrypoint sh decolua/9router:"$NR_TAG" \
      -c 'cp -a /backup/. /app/data/ && chown -R node:node /app/data' \
      && ok "Données restaurées dans le volume $NR_VOL." \
      || warn "Restauration KO — ancien conteneur perdu, nouveau départ."
  fi
  docker pull decolua/9router:"$NR_TAG" \
    && docker run -d --name 9router "${NR_RUN_ARGS[@]}" decolua/9router:"$NR_TAG" >/dev/null \
    && ok "Conteneur 9router créé (image $NR_TAG, données sur volume 9router-data)." \
    || die "Création conteneur 9router échouée."
fi

# ============================================================================
# 5. 9router opérationnel + navigateur
# ============================================================================
say "Étape 5/9 — Démarrage 9router"
docker start 9router >/dev/null 2>&1
up=0
for i in {1..30}; do
  curl -fsS --max-time 2 "$NR_URL/api/health" >/dev/null 2>&1 && { up=1; break; }
  sleep 1
done
[ "$up" = 1 ] && ok "9router répond sur $NR_URL" || die "9router ne répond pas (docker logs --tail 40 9router)."

# Combos pré-créés (noms seulement, modèles vides — le pote met les siens dans
# le dashboard). La base SQLite est créée paresseusement : un GET /api/auth/status
# suffit à la déclencher (sans tenter de login, donc sans risque de lockout).
say "Pré-création des 12 combos (9deepseek … 9sonnet) + scripts 9mode"
mkdir -p "$HOME/.9mode"
if [ -d "$NMODE_DIR" ] && [ -f "$NMODE_DIR/9auto.py" ]; then
  cp "$NMODE_DIR/9mode.py" "$NMODE_DIR/9auto.py" "$HOME/.9mode/" && ok "Scripts 9mode → ~/.9mode/"
else
  warn "9mode/ introuvable — skill 9mode-settings ne fonctionnera pas."
fi
curl -fsS --max-time 5 "$NR_URL/api/auth/status" >/dev/null 2>&1 || true
for i in {1..15}; do docker exec 9router sh -c '[ -f /app/data/db/data.sqlite ]' 2>/dev/null && break; sleep 1; done
SEED_JS="$(cat <<'EOSEED'
const db=require("node:sqlite");const d=new db.DatabaseSync("/app/data/db/data.sqlite");
const names=["9deepseek","9fable","9gemini","9glm","9gpt","9haiku","9kimi","9minimax","9opus","9oxalpha","9qwen","9sonnet"];
const now=new Date().toISOString();let n=0;
for(const name of names){const r=d.prepare("INSERT OR IGNORE INTO combos (id,name,kind,models,createdAt,updatedAt) VALUES (?,?,?,?,?,?)").run(crypto.randomUUID(),name,null,"[]",now,now);n+=r.changes}
console.log(n+" nouveaux, "+d.prepare("SELECT count(*) c FROM combos").get().c+" total");
EOSEED
)"
docker exec -u node 9router node -e "$SEED_JS" 2>/dev/null \
  && ok "Combos prêts (idempotent : les combos existants sont conservés)." \
  || warn "Seed combos KO — crée-les à la main dans le dashboard."

say "Ouverture du navigateur sur $NR_URL"
if command -v wslview >/dev/null 2>&1; then
  wslview "$NR_URL" >/dev/null 2>&1 || true
elif command -v explorer.exe >/dev/null 2>&1; then
  (cmd.exe /c start "$NR_URL" >/dev/null 2>&1) || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$NR_URL" >/dev/null 2>&1 || true
fi
echo
echo "→ Dans l'interface 9router ouverte dans ton navigateur :"
echo "     Dashboard → Keys → crée une clé API (sk-...) et garde-la sous la main."
echo "  Le script te la demandera à l'étape 8."

# ============================================================================
# 6. Skills
# ============================================================================
say "Étape 6/9 — Skills"
S9="https://raw.githubusercontent.com/decolua/9router/refs/heads/master/skills"
s9_ok=0
for skill in 9router 9router-chat 9router-image 9router-tts; do
  mkdir -p /tmp/9sk-$skill
  if curl -sL --max-time 10 "$S9/$skill/SKILL.md" -o /tmp/9sk-$skill/SKILL.md 2>/dev/null; then
    s9_ok=$((s9_ok+1))
  else
    warn "$skill : fetch KO"
  fi
done
ok "$s9_ok/4 skills 9router fetchés depuis GitHub."

SKILL_DESTS=(
  "$HOME/.claude/skills"
  "$HOME/.hermes/skills/claude-import"
  "$HOME/.config/opencode/skills"
  "$HOME/.codex/skills"
  "$HOME/.agents/skills"
)
for dest in "${SKILL_DESTS[@]}"; do
  mkdir -p "$dest"
  n=0
  for d in "$BUNDLE_DIR"/*/; do
    name="$(basename "$d")"
    # Skills extraits des plugins Claude Code : pas déployés dans ~/.claude/skills
    # (Claude Code les a déjà via ses plugins — doublon inutile).
    if [ "$dest" = "$HOME/.claude/skills" ]; then
      case "$name" in
        frontend-design|ui-ux-pro-max|defuddle|json-canvas|obsidian-bases|obsidian-cli|obsidian-markdown) continue ;;
      esac
    fi
    rsync -a --delete "$d" "$dest/$name" && n=$((n+1))
  done
  ok "$n skills → $dest"
  for skill in 9router 9router-chat 9router-image 9router-tts; do
    [ -f /tmp/9sk-$skill/SKILL.md ] && mkdir -p "$dest/$skill" && cp /tmp/9sk-$skill/SKILL.md "$dest/$skill/SKILL.md"
  done
done
rm -rf /tmp/9sk-*
ok "Skills déployés sur 5 dossiers ($(ls "$HOME/.claude/skills" | wc -l) dans ~/.claude/skills)."

if command -v openclaw >/dev/null 2>&1; then
  oc_ok=0; oc_fail=0
  for s in "$HOME"/.claude/skills/*/; do
    n=$(basename "$s")
    case "$n" in 9mode-settings) continue ;; esac
    if timeout 30 openclaw skills install --force "$s" >/dev/null 2>&1; then
      oc_ok=$((oc_ok+1))
    else
      oc_fail=$((oc_fail+1))
    fi
  done
  ok "OpenClaw : $oc_ok skills installés ($oc_fail échecs)."
fi

# ============================================================================
# 7. Config des 6 applis (placeholder clé, rempli à l'étape 8)
# ============================================================================
say "Étape 7/9 — Configuration des 6 applis → 9router"
NR_KEY_PLACEHOLDER="__9ROUTER_KEY__"


# --- util : écrit une valeur dans un JSON (chemin pointé) -------------------
json_set() {
  python3 - "$@" <<'EOJS'
import json, sys, os
path, dotpath, value = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path)) if (os.path.exists(path) and os.path.getsize(path) > 0) else {}
node = d
for k in dotpath.split('.')[:-1]:
    node = node.setdefault(k, {})
node[dotpath.split('.')[-1]] = value
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w') as f:
    f.write(json.dumps(d, indent=2) + "\n")
EOJS
}

# --- Claude Code -------------------------------------------------------------
mkdir -p "$HOME/.claude"
[ -f "$HOME/.claude/settings.json" ] && cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.bak-stack"
json_set "$HOME/.claude/settings.json" env.ANTHROPIC_BASE_URL "$NR_URL"
json_set "$HOME/.claude/settings.json" env.ANTHROPIC_AUTH_TOKEN "$NR_KEY_PLACEHOLDER"
json_set "$HOME/.claude/settings.json" env.ANTHROPIC_DEFAULT_OPUS_MODEL 9opus
json_set "$HOME/.claude/settings.json" env.ANTHROPIC_DEFAULT_SONNET_MODEL 9haiku
json_set "$HOME/.claude/settings.json" env.ANTHROPIC_DEFAULT_HAIKU_MODEL 9haiku
json_set "$HOME/.claude/settings.json" env.ANTHROPIC_SMALL_FAST_MODEL 9haiku
json_set "$HOME/.claude/settings.json" env.CLAUDE_CODE_MAX_CONTEXT_TOKENS 1000000
json_set "$HOME/.claude/settings.json" env.CLAUDE_CODE_MAX_OUTPUT_TOKENS 128000
json_set "$HOME/.claude/settings.json" model 9haiku
json_set "$HOME/.claude/settings.json" hasCompletedOnboarding true
# Autoupdate natif (le reste : ~/.claude.json, pas settings.json)
if [ -f "$HOME/.claude.json" ]; then
  cp "$HOME/.claude.json" "$HOME/.claude.json.bak-stack"
fi
json_set "$HOME/.claude.json" autoUpdates true

# --- claude-hud (plugin + statusLine) ----------------------------------------
say "claude-hud"
if command -v claude >/dev/null 2>&1; then
  claude plugin marketplace add jarrodwatts/claude-hud >/dev/null 2>&1 \
    || warn "marketplace claude-hud : add KO"
  claude plugin install claude-hud@claude-hud >/dev/null 2>&1 \
    || warn "plugin claude-hud : install KO"
  # statusLine : pointe sur la version la plus récente en cache
  json_set "$HOME/.claude/settings.json" statusLine.type command
  json_set "$HOME/.claude/settings.json" statusLine.padding 0
  HUD_JS='node "$(ls -d "$HOME"/.claude/plugins/cache/claude-hud/claude-hud/*/dist/index.js | sort -V | tail -1)"'
  json_set "$HOME/.claude/settings.json" statusLine.command "$HUD_JS"
  ok "claude-hud installé + statusLine configuré."
fi

# --- autres plugins Claude Code (même liste que sur ta machine) --------------
# frontend-design : PAS installé en plugin — son skill est dans le bundle
# (skills-bundle/frontend-design) et partagé avec les 5 autres agents.
say "plugins Claude Code (obsidian, ui-ux-pro-max, superpowers)"
if command -v claude >/dev/null 2>&1; then
  claude plugin marketplace add kepano/obsidian-skills >/dev/null 2>&1 \
    || warn "marketplace obsidian-skills : add KO"
  claude plugin install obsidian@obsidian-skills >/dev/null 2>&1 \
    || warn "plugin obsidian : install KO"

  claude plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill >/dev/null 2>&1 \
    || warn "marketplace ui-ux-pro-max-skill : add KO"
  claude plugin install ui-ux-pro-max@ui-ux-pro-max-skill >/dev/null 2>&1 \
    || warn "plugin ui-ux-pro-max : install KO"

  claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1 \
    || warn "marketplace claude-plugins-official : add KO"
  claude plugin install superpowers@claude-plugins-official >/dev/null 2>&1 \
    || warn "plugin superpowers : install KO"
  ok "plugins Claude Code installés (obsidian, ui-ux-pro-max, superpowers)."
fi

ok "Claude Code → 9router"

# --- OpenClaw ------------------------------------------------------------------
if command -v openclaw >/dev/null 2>&1; then
  mkdir -p "$HOME/.openclaw"
  [ -f "$HOME/.openclaw/openclaw.json" ] && cp "$HOME/.openclaw/openclaw.json" "$HOME/.openclaw/openclaw.json.bak-stack"
  python3 - "$NR_KEY_PLACEHOLDER" <<'EOOC'
import json, os, sys
key = sys.argv[1]
p = os.path.expanduser("~/.openclaw/openclaw.json")
d = json.load(open(p)) if os.path.exists(p) else {}
combos = ["9glm","9sonnet","9opus","9haiku","9deepseek","9fable",
          "9gemini","9gpt","9kimi","9minimax","9oxalpha","9qwen"]
d["models"] = d.get("models", {})
d["models"]["providers"] = d["models"].get("providers", {})
d["models"]["providers"]["9router"] = {
    "api": "openai-completions",
    "baseUrl": "http://127.0.0.1:20128/v1",
    "apiKey": key,
    "models": [{"id": c, "name": c} for c in combos],
}
d["agents"] = d.get("agents", {})
d["agents"]["defaults"] = d["agents"].get("defaults", {})
d["agents"]["defaults"]["model"] = {"primary": "9router/9haiku"}
d["agents"]["defaults"]["models"] = d["agents"]["defaults"].get("models") or {}
d["agents"]["defaults"]["models"]["9router/9haiku"] = {"contextWindow": 256000, "maxTokens": 128000}
d["mcp"] = d.get("mcp", {})
d["mcp"]["servers"] = d["mcp"].get("servers", {})
d["mcp"]["servers"]["ScraplingServer"] = {
    "command": os.path.expanduser("~/.local/bin/scrapling-mcp")
}
with open(p, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
print("OK")
EOOC
  ok "OpenClaw → 9router"
fi

# --- Codex --------------------------------------------------------------------
mkdir -p "$HOME/.codex"
[ -f "$HOME/.codex/config.toml" ] && cp "$HOME/.codex/config.toml" "$HOME/.codex/config.toml.bak-stack"
cat > "$HOME/.codex/config.toml" <<'EOCX'
# Codex CLI — 9router (généré par install-stack.sh)
model = "9haiku"
model_provider = "9router"
model_context_window = 256000
model_max_output_tokens = 128000

[model_providers.9router]
name = "9router"
base_url = "http://127.0.0.1:20128/v1"
env_key = "CODEROUTER_API_KEY"
wire_api = "responses"

# MCP Scrapling
[mcp_servers.ScraplingServer]
command = "~/.local/bin/scrapling-mcp"
EOCX
ok "Codex → 9router"

# --- OpenCode -----------------------------------------------------------------
mkdir -p "$HOME/.config/opencode"
[ -f "$HOME/.config/opencode/opencode.json" ] && cp "$HOME/.config/opencode/opencode.json" "$HOME/.config/opencode/opencode.json.bak-stack"
python3 - "$NR_KEY_PLACEHOLDER" <<'EOPO'
import json, os, sys
key = sys.argv[1]
p = os.path.expanduser("~/.config/opencode/opencode.json")
d = json.load(open(p)) if os.path.exists(p) else {}
models = {}
for c in ["9deepseek","9fable","9gemini","9gpt","9haiku","9kimi",
          "9minimax","9opus","9oxalpha","9qwen","9sonnet"]:
    models[c] = {"name": c}
models["9glm"] = {"name": "9glm", "limit": {"context": 256000, "output": 128000}}
models["9haiku"] = {"name": "9haiku", "limit": {"context": 256000, "output": 128000}}
d["provider"] = {"9router": {
    "npm": "@ai-sdk/openai-compatible",
    "name": "9router",
    "options": {"baseURL": "http://127.0.0.1:20128/v1", "apiKey": key},
    "models": models,
}}
d["model"] = "9router/9haiku"
d["autoupdate"] = True
d["mcp"] = {
    "ScraplingServer": {
        "type": "local",
        "command": [os.path.expanduser("~/.local/bin/scrapling-mcp")],
        "enabled": True,
    }
}
with open(p, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
print("OK")
EOPO
ok "OpenCode → 9router"

# --- Hermes -------------------------------------------------------------------
if command -v hermes >/dev/null 2>&1; then
  hermes config set model.provider custom >/dev/null 2>&1
  hermes config set model.base_url "$NR_URL/v1" >/dev/null 2>&1
  hermes config set model.default 9haiku >/dev/null 2>&1
  hermes config set model.api_key "$NR_KEY_PLACEHOLDER" >/dev/null 2>&1
  hermes config set model_overrides.custom.9haiku.context_window 256000 --force >/dev/null 2>&1
  hermes config set model_overrides.custom.9haiku.max_output_tokens 128000 --force >/dev/null 2>&1
  # MCP Scrapling (chemin absolu du binaire) — printf Y : hermes demande
  # confirmation interactive "Enable all tools?" qui bloquerait le script.
  printf 'Y\n' | hermes mcp add ScraplingServer --command "$HOME/.local/bin/scrapling-mcp" >/dev/null 2>&1 \
    || warn "hermes mcp add ScraplingServer KO"
  ok "Hermes → 9router"
fi

# --- dsh ----------------------------------------------------------------------
mkdir -p "$HOME/.dsh"
cat > "$HOME/.dsh/settings.yaml" <<'EODS'
# dsh — 9router (régénéré par sofalost)
agent-default-model:
  provider: 9router
  model: 9haiku
llm-pi-ai:
  providers:
    9router:
      displayName: 9router
      apiKeyEnv: CODEROUTER_API_KEY
      api: openai-completions
      baseURL: http://127.0.0.1:20128/v1
      compat:
        supportsDeveloperRole: false
        maxTokensField: max_tokens
      models:
        - id: 9haiku
          name: 9haiku (via 9router)
          contextWindow: 256000
          maxTokens: 128000
EODS
ok "dsh → 9router"

# Skills dans dsh : le profil web désactive le plugin skill-filesystem (celui
# qui lit ~/.agents/skills). Un cordis.patch.yml pré-créé survit au scaffold
# du profile et réactive le plugin → les 32 skills visibles aussi dans dsh web.
mkdir -p "$HOME/.dsh/profiles/web"
cat > "$HOME/.dsh/profiles/web/cordis.patch.yml" <<'EODP'
# Skills du filesystem (~/.agents/skills) réactivés dans le profil web.
- id: skill-filesystem
  disabled: false
EODP
ok "dsh web : skill-filesystem réactivé (skills ~/.agents/skills)."

# ============================================================================
# 8. Clé API
# ============================================================================
say "Étape 8/9 — Clé API 9router"

# Reprise après échec : si une clé valide est déjà en place (bashrc + 9router
# l'accepte), on saute la saisie — le script est relançable sans tout refaire.
EXISTING_KEY="$(grep -oP '^CODEROUTER_API_KEY="\K[^"]+' "$HOME/.bashrc" 2>/dev/null | head -1)"
if [ -n "$EXISTING_KEY" ] \
   && curl -fsS --max-time 5 -H "Authorization: Bearer $EXISTING_KEY" "$NR_URL/v1/models" >/dev/null 2>&1; then
  NR_KEY="$EXISTING_KEY"
  ok "Clé API déjà présente et valide — saisie sautée."
else
  echo
  echo "════════════════════════════════════════════════════════════════"
  echo "  Récupère ta clé API sur l'interface 9router (ouverte dans ton"
  echo "  navigateur à l'étape 5) : Dashboard → Keys → crée une clé sk-..."
  echo "════════════════════════════════════════════════════════════════"
  NR_KEY=""
  while [ -z "$NR_KEY" ]; do
    read -r -p "Colle ta clé API 9router (sk-...) : " NR_KEY
    if [ -z "$NR_KEY" ]; then
      warn "Clé vide — réessaie."
    elif ! printf '%s' "$NR_KEY" | grep -qE '^sk-[A-Za-z0-9_-]{8,}$'; then
      warn "Format inattendu (attendu : sk-... ) — réessaie."
      NR_KEY=""
    fi
  done

  if curl -fsS --max-time 5 -H "Authorization: Bearer $NR_KEY" "$NR_URL/v1/models" >/dev/null 2>&1; then
    ok "Clé validée contre 9router."
  else
    warn "Clé non validée par 9router — inscrite quand même (vérifie Dashboard → Keys)."
  fi
fi

sed -i "s|__9ROUTER_KEY__|$NR_KEY|g" \
  "$HOME/.claude/settings.json" \
  "$HOME/.openclaw/openclaw.json" \
  "$HOME/.config/opencode/opencode.json" 2>/dev/null
# Hermes : la clé via sa CLI (jamais d'édition manuelle de config.yaml)
command -v hermes >/dev/null 2>&1 && hermes config set model.api_key "$NR_KEY" >/dev/null 2>&1
ok "Clé écrite dans Claude Code, OpenClaw, OpenCode, Hermes."

BRC="$HOME/.bashrc"
touch "$BRC"
if ! grep -q 'CODEROUTER_API_KEY=' "$BRC"; then
  {
    echo ""
    echo "# Clé 9router pour Codex CLI + dsh (généré par install-stack.sh)"
    echo "CODEROUTER_API_KEY=\"$NR_KEY\""
    echo "export CODEROUTER_API_KEY"
  } >> "$BRC"
  ok "CODEROUTER_API_KEY ajouté à ~/.bashrc."
else
  sed -i "s|^CODEROUTER_API_KEY=.*|CODEROUTER_API_KEY=\"$NR_KEY\"|" "$BRC"
  ok "CODEROUTER_API_KEY mis à jour dans ~/.bashrc."
fi
export CODEROUTER_API_KEY="$NR_KEY"

# ============================================================================
# 9. Fonction sofalost
# ============================================================================
say "Étape 9/9 — Fonction sofalost"
MARK_START="# >>> sofalost (stack-hugo) >>>"
MARK_END="# <<< sofalost (stack-hugo) <<<"
if grep -qF "$MARK_START" "$BRC"; then
  say "sofalost déjà présente — remplacement."
  sed -i "/^# >>> sofalost (stack-hugo) >>>$/,/^# <<< sofalost (stack-hugo) <<<$/d" "$BRC"
fi
cat >> "$BRC" <<'EOSOF'
# >>> sofalost (stack-hugo) >>>
# Full update Ubuntu + 6 agents + skills + image Docker 9router (données
# préservées) + menu. sudo NOPASSWD : /etc/sudoers.d/$USER. Usage : sofalost.
_sofalost_mirror_skills() {
  local dest="$1"
  [ -d "$HOME/.claude/skills" ] || return 1
  command -v rsync >/dev/null 2>&1 || return 1
  mkdir -p "$dest"
  rsync -a --delete "$HOME/.claude/skills/" "$dest/"
}

_sofalost_wait_health() {
  local url="$1" tries="${2:-20}" i
  for ((i = 0; i < tries; i++)); do
    curl -fsS --max-time 2 "$url" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

sofalost() {
  # Refonte 2026-08-20, ajustée 2026-08-22/23 puis 2026-08-25, combos retirés
  # 2026-08-27 (sauf classifier) : sofalost n'est plus un gestionnaire de stack
  # (ollama abandonné ici). C'est un launcher multi-agents : full update Linux
  # + des agents (claude, hermes, openclaw, opencode, codex, dsh) + skills/plugins
  # + image Docker 9router (si ça ne menace pas les données) + classifier Claude
  # Code fixé sur 9haiku, puis menu de lancement. Le baseline 9router
  # (RTK/Caveman/Ponytail) et les autres combos ne sont plus touchés ici.
  if [ $# -gt 0 ]; then
    echo "sofalost ne prend plus d'option (plus de --fast) : usage \`sofalost\`."
    return 2
  fi

  local health_url="http://127.0.0.1:20128/api/health"

  # ─── Pré-check réseau (cf commentaire historique : deux pannes distinctes) ───
  echo "🌐 [1/8] Vérification réseau..."
  if [ -z "$(ip route show default 2>/dev/null)" ]; then
    echo "❌ Réseau WSL mort : aucune route par défaut (souvent networkingMode=mirrored décroché)."
    echo "   Fix (PowerShell) : wsl --shutdown, puis relance sofalost."
    return 1
  fi
  if ! getent hosts github.com >/dev/null 2>&1; then
    echo "⚠️ Routes OK mais résolution DNS KO — réparation de resolv.conf..."
    if ! sudo -n true 2>/dev/null; then
      echo "❌ sudo nécessite un mot de passe. Lance d'abord : sudo -v   puis relance sofalost."
      return 1
    fi
    printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' | sudo tee /etc/resolv.conf >/dev/null 2>&1
    sleep 1
    getent hosts github.com >/dev/null 2>&1 || { echo "❌ DNS toujours cassé. Essaie : wsl --shutdown."; return 1; }
  fi
  echo "✅ Réseau OK."

  echo
  echo "🔄 [2/8] Mise à jour Ubuntu (full-upgrade)..."
  if ! sudo apt update; then
    echo "❌ Échec de apt update."
    return 1
  fi
  local upgrade_log
  upgrade_log=$(mktemp)
  sudo apt full-upgrade -y | tee "$upgrade_log"
  local upgrade_rc=${PIPESTATUS[0]}
  if [ "$upgrade_rc" -ne 0 ]; then
    echo "❌ Échec de full-upgrade Ubuntu."
    rm -f "$upgrade_log"
    return 1
  fi
  # Le kernel WSL ne prend effet qu'après un redémarrage complet de la VM
  # (wsl --shutdown), pas juste ce shell — sinon la mise à jour reste inerte.
  if grep -qiE 'linux-image-[0-9]' "$upgrade_log"; then
    echo "⚠️ Kernel WSL mis à jour — redémarre la VM pour l'appliquer : wsl --shutdown (PowerShell), puis relance sofalost."
  fi
  rm -f "$upgrade_log"
  sudo apt autoremove -y

  echo
  echo "🤖 [3/8] Mise à jour Claude Code..."
  if ! command -v claude >/dev/null 2>&1; then
    echo "❌ Claude Code introuvable — installation attendue au préalable, sofalost ne l'installe plus."
    return 1
  fi
  claude update || echo "⚠️ Update Claude Code échouée, on continue."

  echo
  echo "🧩 [4/8] Mise à jour plugins + skills Claude Code..."
  if [ -x "$HOME/.claude/scripts/update-toolkit.sh" ]; then
    "$HOME/.claude/scripts/update-toolkit.sh" || echo "⚠️ Update toolkit (plugins/skills) échouée, on continue."
  else
    echo "⚠️ ~/.claude/scripts/update-toolkit.sh introuvable — étape sautée."
  fi

  echo
  echo "🧠 [5/8] Hermes Mise à jour via hermes update (CLI officielle) + skills..."
  if command -v hermes >/dev/null 2>&1; then
    # Retry 1x après 10 s : le git fetch d'update peut se faire couper par un
    # HTTP 429 GitHub (gros rattrapage de commits) — le 2e essai repart du
    # pack déjà partiellement téléchargé et passe généralement.
    hermes update --yes >/dev/null 2>&1 \
      || { sleep 10; hermes update --yes >/dev/null 2>&1; } \
      && echo "✅ Hermes à jour ($(hermes --version 2>/dev/null | head -1))." \
      || echo "⚠️ Update Hermes échouée, on continue."
    hermes skills update >/dev/null 2>&1 \
      && echo "✅ Skills Hermes (hub) à jour." \
      || echo "⚠️ Update skills Hermes échouée, on continue."
    # Miroir des skills Claude dans Hermes (claude-import = copie locale)
    _sofalost_mirror_skills "$HOME/.hermes/skills/claude-import" \
      && echo "✅ Skills Hermes (miroir Claude, $(ls "$HOME/.hermes/skills/claude-import" 2>/dev/null | wc -l) skills) à jour." \
      || echo "⚠️ Resync skills Hermes échouée, on continue."
    # ui-ux-pro-max vient d'un plugin (pas de ~/.claude/skills) : chemin absolu patché dans son SKILL.md
    if [ -d "$HOME/.hermes/skills/claude-import/ui-ux-pro-max" ]; then
      rsync -a "$HOME/.hermes/skills/claude-import/ui-ux-pro-max/" "$HOME/.config/opencode/skills/ui-ux-pro-max/" 2>/dev/null
    fi
  else
    echo "⚠️ hermes introuvable — étape sautée."
  fi

  echo
  echo "🦞 [openclaw] Mise à jour (sans lancer/restart) + skills..."
  if command -v openclaw >/dev/null 2>&1; then
    openclaw update --yes --no-restart >/dev/null 2>&1 \
      && echo "✅ openclaw à jour ($(openclaw --version 2>/dev/null))." \
      || echo "⚠️ Update openclaw échouée, on continue."
    # Skills openclaw = miroir des skills Claude (source de vérité)
    if [ -d "$HOME/.claude/skills" ]; then
      local oc_ok=0 oc_fail=0
      for s in "$HOME"/.claude/skills/*/; do
        if timeout 30 openclaw skills install --force "$s" >/dev/null 2>&1; then
          oc_ok=$((oc_ok+1))
        else
          oc_fail=$((oc_fail+1))
        fi
      done
      echo "✅ Skills openclaw resynchronisés ($oc_ok OK, $oc_fail échecs)."
    fi
  else
    echo "⚠️ openclaw introuvable — étape sautée."
  fi

  echo
  echo "📝 [opencode] Mise à jour + resync skills depuis Claude..."
  if command -v opencode >/dev/null 2>&1; then
    opencode upgrade >/dev/null 2>&1 \
      && echo "✅ opencode à jour ($(opencode --version 2>/dev/null | head -1))." \
      || echo "⚠️ Update opencode échouée, on continue."
    # Skills opencode = miroir des skills Claude (source de vérité)
    _sofalost_mirror_skills "$HOME/.config/opencode/skills" \
      && echo "✅ Skills opencode resynchronisés ($(ls "$HOME/.config/opencode/skills" 2>/dev/null | wc -l) skills)." \
      || echo "⚠️ Resync skills opencode échouée, on continue."
    # ui-ux-pro-max (issu d'un plugin, SKILL.md patché) — resync depuis la copie Hermes
    [ -d "$HOME/.hermes/skills/claude-import/ui-ux-pro-max" ] && \
      rsync -a "$HOME/.hermes/skills/claude-import/ui-ux-pro-max/" "$HOME/.config/opencode/skills/ui-ux-pro-max/"
  else
    echo "⚠️ opencode introuvable — étape sautée."
  fi

  echo
  echo "🤖 [codex] Mise à jour + skills..."
  if command -v codex >/dev/null 2>&1; then
    codex update >/dev/null 2>&1 \
      && echo "✅ codex à jour ($(codex --version 2>/dev/null | head -1))." \
      || echo "⚠️ Update codex échouée, on continue."
    # Skills codex = miroir des skills Claude (mêmes exclusions)
    _sofalost_mirror_skills "$HOME/.codex/skills" \
      && echo "✅ Skills codex resynchronisés ($(ls "$HOME/.codex/skills" 2>/dev/null | wc -l) skills)." \
      || echo "⚠️ Resync skills codex échouée, on continue."
    # ui-ux-pro-max : chemin absolu codex
    [ -d "$HOME/.hermes/skills/claude-import/ui-ux-pro-max" ] && \
      rsync -a "$HOME/.hermes/skills/claude-import/ui-ux-pro-max/" "$HOME/.codex/skills/ui-ux-pro-max/" && \
      sed -i "s|$HOME/.hermes/skills/claude-import/ui-ux-pro-max|$HOME/.codex/skills/ui-ux-pro-max|g" \
        "$HOME/.codex/skills/ui-ux-pro-max/SKILL.md"
  else
    echo "⚠️ codex introuvable — étape sautée."
  fi

  echo
  echo "🦀 [dsh] Mise à jour DeepSeek Harness + skills..."
  if command -v dsh >/dev/null 2>&1; then
    npm install -g @deepseek-ai/dsh >/dev/null 2>&1 \
      && echo "✅ dsh à jour ($(dsh --version 2>/dev/null))." \
      || echo "⚠️ Update dsh échouée, on continue."
    # Skills dsh = miroir des skills Claude (mêmes exclusions)
    _sofalost_mirror_skills "$HOME/.agents/skills" \
      && echo "✅ Skills dsh resynchronisés ($(ls "$HOME/.agents/skills" 2>/dev/null | wc -l) skills)." \
      || echo "⚠️ Resync skills dsh échouée, on continue."
  else
    echo "⚠️ dsh introuvable — étape sautée."
  fi

  echo
  echo "🔧 [6/8] Auto-update des 4 skills 9router sur les 6 CLI..."
  local s9="https://raw.githubusercontent.com/decolua/9router/refs/heads/master/skills"
  local s9_ok=0 s9_fail=0
  for skill in 9router 9router-chat 9router-image 9router-tts; do
    curl -sL --max-time 10 "$s9/$skill/SKILL.md" -o /tmp/9sk-$skill.md 2>/dev/null \
      && { mkdir -p /tmp/9sk-$skill && cp /tmp/9sk-$skill.md /tmp/9sk-$skill/SKILL.md; } \
      || { echo "⚠️ $skill : fetch KO, on garde la copie locale."; continue; }
    s9_ok=$((s9_ok+1))
  done
  [ "$s9_ok" -gt 0 ] && echo "✅ $s9_ok/4 skills 9router fetchés depuis upstream."

  for dest in ~/.hermes/skills/claude-import ~/.claude/skills ~/.config/opencode/skills ~/.codex/skills ~/.agents/skills; do
    mkdir -p "$dest"
    for skill in 9router 9router-chat 9router-image 9router-tts; do
      [ -f /tmp/9sk-$skill/SKILL.md ] && mkdir -p "$dest/$skill" && cp /tmp/9sk-$skill/SKILL.md "$dest/$skill/SKILL.md"
    done
  done

  if [ -f /tmp/9sk-9router/SKILL.md ] && command -v openclaw >/dev/null 2>&1; then
    for skill in 9router 9router-chat 9router-image 9router-tts; do
      [ -f /tmp/9sk-$skill/SKILL.md ] && \
        timeout 30 openclaw skills install --force /tmp/9sk-$skill >/dev/null 2>&1
    done
    echo "✅ Skills 9router openclaw resynchronisés."
  fi
  rm -rf /tmp/9sk-*

  echo
  echo "🐳 [7/8] Mise à jour de l'image Docker 9router..."
  if ! command -v docker >/dev/null 2>&1; then
    echo "⚠️ Docker introuvable — update 9router sautée."
  else
    for i in {1..30}; do
      docker info >/dev/null 2>&1 && break
      sleep 1
    done
    if ! docker info >/dev/null 2>&1; then
      echo "⚠️ Docker Desktop indisponible — update 9router sautée."
    elif docker ps -a --format '{{.Names}}' | grep -qx "9router"; then
      # Volume nommé 9router-data monté en dehors du conteneur : un pull+recreate
      # ne touche jamais les données, seul le code de l'image change. On ne
      # recrée que si le digest a vraiment changé, avec un tag de secours pour
      # pouvoir revenir en arrière si le nouveau conteneur ne répond pas.
      local img_avant img_apres
      img_avant=$(docker inspect 9router --format '{{.Image}}' 2>/dev/null)
      echo "   ⏳ docker pull decolua/9router:latest..."
      if docker pull decolua/9router:latest; then
        img_apres=$(docker image inspect decolua/9router:latest --format '{{.Id}}' 2>/dev/null)
        if [ "$img_avant" = "$img_apres" ]; then
          echo "✅ 9router déjà à la dernière image."
          docker start 9router >/dev/null 2>&1
        else
          echo "⬆️ Nouvelle image 9router — recréation (données sur volume 9router-data, préservées)..."
          docker tag decolua/9router:latest decolua/9router:sofalost-rollback >/dev/null 2>&1
          docker stop 9router >/dev/null 2>&1
          docker rm 9router >/dev/null 2>&1
          docker run -d --name 9router --restart always --network ai-network \
            -p 20128:20128 -v 9router-data:/app/data decolua/9router:latest >/dev/null 2>&1
          if _sofalost_wait_health "$health_url"; then
            echo "✅ 9router à jour et opérationnel."
          else
            echo "❌ 9router ne répond pas après recréation — rollback vers l'image précédente..."
            docker stop 9router >/dev/null 2>&1
            docker rm 9router >/dev/null 2>&1
            docker run -d --name 9router --restart always --network ai-network \
              -p 20128:20128 -v 9router-data:/app/data decolua/9router:sofalost-rollback >/dev/null 2>&1
            echo "   Rollback effectué. Diagnostic : docker logs --tail 40 9router"
          fi
        fi
      else
        echo "⚠️ docker pull 9router échoué (réseau ?) — conteneur existant laissé tel quel."
        docker start 9router >/dev/null 2>&1
      fi
    else
      echo "❌ Conteneur '9router' absent — recréation manuelle requise."
    fi

    # Filet de sécurité : claude cible ANTHROPIC_BASE_URL=127.0.0.1:20128, donc
    # un 9router down (même sans update, ex. crash silencieux) fait échouer le
    # lancement de claude en fin de fonction sans diagnostic clair.
    if ! curl -fsS --max-time 2 "$health_url" >/dev/null 2>&1; then
      echo "⚠️ 9router ne répond pas — restart avant lancement de claude..."
      docker restart 9router >/dev/null 2>&1
      if _sofalost_wait_health "$health_url"; then
        echo "✅ 9router récupéré après restart."
      else
        echo "❌ 9router toujours KO — claude va probablement échouer au lancement."
        echo "   Diagnostic : docker logs --tail 40 9router"
      fi
    fi
  fi

  echo
  echo "🎯 [8/8] Classifier Claude Code (ANTHROPIC_SMALL_FAST_MODEL → 9haiku)..."
  if command -v python3 >/dev/null 2>&1 && [ -f "$HOME/.claude/settings.json" ]; then
    python3 - <<'EOCF'
import json
from pathlib import Path
p = Path.home() / ".claude" / "settings.json"
d = json.loads(p.read_text())
d.setdefault("env", {})["ANTHROPIC_SMALL_FAST_MODEL"] = "9haiku"
p.write_text(json.dumps(d, indent=2) + "\n")
EOCF
    [ "$?" = 0 ] && echo "✅ Classifier Claude Code fixé sur 9haiku." || echo "⚠️ Fix classifier Claude Code échoué, on continue."
  else
    echo "⚠️ python3 ou ~/.claude/settings.json introuvable — étape sautée."
  fi

  echo
  echo "🚀 Quel agent veux-tu lancer ?"
  echo "   1) claude (Claude Code)"
  echo "   2) hermes (Hermes Agent)"
  echo "   3) openclaw (OpenClaw)"
  echo "   4) opencode (OpenCode)"
  echo "   5) codex (Codex CLI)"
  echo "   6) dsh (DeepSeek Harness)"
  local choix
  read -r -p "Choix [1-6] : " choix
  case "$choix" in
    1) echo "🚀 Lancement de Claude Code..."; claude ;;
    2) echo "🚀 Lancement de Hermes..."; hermes ;;
    3) echo "🚀 Lancement de OpenClaw..."; openclaw ;;
    4) echo "🚀 Lancement de OpenCode..."; opencode ;;
    5) echo "🚀 Lancement de Codex..."; codex ;;
    6) echo "🚀 Lancement de DeepSeek Harness..."; dsh web ;;
    *) echo "ℹ️ Aucun choix valide — rien n'est lancé."; return 0 ;;
  esac
}
# <<< sofalost (stack-hugo) <<<
EOSOF
ok "Fonction sofalost ajoutée à ~/.bashrc."

# ============================================================================
# Fin — résumé vérifiable
# ============================================================================
echo
echo "════════════════════ RÉSUMÉ DE L'INSTALLATION ════════════════════"
for app in claude openclaw codex opencode hermes dsh; do
  if command -v "$app" >/dev/null 2>&1; then
    printf '  ✅ %-10s installé\n' "$app"
  else
    printf '  ❌ %-10s ABSENT\n' "$app"
  fi
done
if curl -fsS --max-time 3 "$NR_URL/api/health" >/dev/null 2>&1; then
  printf '  ✅ %-10s répond sur %s\n' "9router" "$NR_URL"
else
  printf '  ❌ %-10s NE RÉPOND PAS\n' "9router"
fi
printf '  📦 Skills : %s dans ~/.claude/skills\n' "$(ls "$HOME/.claude/skills" 2>/dev/null | wc -l)"
echo "──────────────────────────────────────────────────────────────────"
if [ "$WARN_COUNT" -gt 0 ]; then
  warn "$WARN_COUNT avertissement(s) pendant l'install — voir le log : $LOG_FILE"
else
  ok "Aucun avertissement."
fi
echo "  Log complet : $LOG_FILE"
echo "══════════════════════════════════════════════════════════════════"
echo
ok "Installation terminée !"
echo
echo "  Prochaines étapes :"
echo "    1. Relance ton shell :  exec bash"
echo "    2. Lance             :  sofalost"
echo "    3. Choisis ton agent (1-6)."
echo
echo "  La clé API 9router est dans ~/.bashrc (CODEROUTER_API_KEY) et dans"
echo "  les configs des apps. Pour la changer : Dashboard → Keys puis"
echo "  remplace-la dans ~/.bashrc + les fichiers .bak-stack si besoin."
echo
