#!/usr/bin/env bash
# ============================================================================
# Stack IA de Hugo — installateur pour potes (WSL2 Ubuntu)
# Usage : ./install-stack.sh
# Ce que fait le script : 1) installe tout (6 applis, skills, conteneur 9router)
# 2) configure les 6 applis sur 9router 3) à la fin, demande la clé API et
# termine la config 4) ajoute la fonction `sofalost` dans ~/.bashrc.
# Prérequis : Windows + Docker Desktop avec intégration WSL activée.
# ============================================================================
set -uo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skills-bundle"
NR_URL="http://127.0.0.1:20128"

say()  { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✅ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m⚠️ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m❌ %s\033[0m\n' "$*" >&2; exit 1; }

[ -d "$BUNDLE_DIR" ] || die "Dossier skills-bundle/ introuvable à côté du script."

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
sudo apt-get install -y curl git rsync python3 python3-pip build-essential \
  ca-certificates gnupg unzip jq ripgrep
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
  curl -fsSL https://openclaw.ai/install.sh | bash || npm install -g openclaw || warn "OpenClaw : install KO"
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
else
  docker volume create 9router-data >/dev/null 2>&1
  docker pull decolua/9router:latest \
    && docker run -d --name 9router --restart always --network ai-network \
         -p 20128:20128 -v 9router-data:/app/data decolua/9router:latest >/dev/null \
    && ok "Conteneur 9router créé (données sur volume 9router-data)." \
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
  rsync -a "$BUNDLE_DIR/" "$dest/" || warn "rsync bundle → $dest KO"
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
json_set "$HOME/.claude/settings.json" env.ANTHROPIC_DEFAULT_SONNET_MODEL 9sonnet
json_set "$HOME/.claude/settings.json" env.ANTHROPIC_DEFAULT_HAIKU_MODEL 9haiku
json_set "$HOME/.claude/settings.json" env.ANTHROPIC_SMALL_FAST_MODEL 9classifier
json_set "$HOME/.claude/settings.json" env.CLAUDE_CODE_MAX_CONTEXT_TOKENS 1000000
json_set "$HOME/.claude/settings.json" env.CLAUDE_CODE_MAX_OUTPUT_TOKENS 128000
json_set "$HOME/.claude/settings.json" model 9sonnet
json_set "$HOME/.claude/settings.json" hasCompletedOnboarding true

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
combos = ["9glm","9sonnet","9opus","9haiku","9classifier","9deepseek","9fable",
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
d["agents"]["defaults"]["model"] = {"primary": "9router/9glm"}
d["agents"]["defaults"]["models"] = d["agents"]["defaults"].get("models") or {}
d["agents"]["defaults"]["models"]["9router/9glm"] = {}
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
model = "9kimi"
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
for c in ["9classifier","9deepseek","9fable","9gemini","9gpt","9haiku","9kimi",
          "9minimax","9opus","9oxalpha","9qwen","9sonnet"]:
    models[c] = {"name": c}
models["9glm"] = {"name": "9glm", "limit": {"context": 256000, "output": 128000}}
d["provider"] = {"9router": {
    "npm": "@ai-sdk/openai-compatible",
    "name": "9router",
    "options": {"baseURL": "http://127.0.0.1:20128/v1", "apiKey": key},
    "models": models,
}}
d["model"] = "9router/9glm"
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
  hermes config set model.default 9glm >/dev/null 2>&1
  hermes config set model.api_key "$NR_KEY_PLACEHOLDER" >/dev/null 2>&1
  hermes config set model_overrides.custom.9glm.context_window 256000 --force >/dev/null 2>&1
  hermes config set model_overrides.custom.9glm.max_output_tokens 128000 --force >/dev/null 2>&1
  # MCP Scrapling (chemin absolu du binaire)
  hermes mcp add ScraplingServer --command "$HOME/.local/bin/scrapling-mcp" >/dev/null 2>&1 \
    || warn "hermes mcp add ScraplingServer KO"
  ok "Hermes → 9router"
fi

# --- dsh ----------------------------------------------------------------------
mkdir -p "$HOME/.dsh"
cat > "$HOME/.dsh/settings.yaml" <<'EODS'
# dsh — 9router (régénéré par sofalost)
agent-default-model:
  provider: 9router
  model: 9glm
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
        - id: 9glm
          name: 9glm (GLM via 9router)
          contextWindow: 256000
          maxTokens: 128000
EODS
ok "dsh → 9router"

# ============================================================================
# 8. Clé API
# ============================================================================
say "Étape 8/9 — Clé API 9router"
echo
echo "════════════════════════════════════════════════════════════════"
echo "  Récupère ta clé API sur l'interface 9router (ouverte dans ton"
echo "  navigateur à l'étape 5) : Dashboard → Keys → crée une clé sk-..."
echo "════════════════════════════════════════════════════════════════"
NR_KEY=""
while [ -z "$NR_KEY" ]; do
  read -r -p "Colle ta clé API 9router (sk-...) : " NR_KEY
  [ -z "$NR_KEY" ] && warn "Clé vide — réessaie."
done

if curl -fsS --max-time 5 -H "Authorization: Bearer $NR_KEY" "$NR_URL/v1/models" >/dev/null 2>&1; then
  ok "Clé validée contre 9router."
else
  warn "Clé non validée par 9router — inscrite quand même (vérifie Dashboard → Keys)."
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
sofalost() {
  if [ $# -gt 0 ]; then
    echo "Usage : sofalost (sans option)."
    return 2
  fi
  local health_url="http://127.0.0.1:20128/api/health"

  # ─── [1/6] Pré-check réseau ───
  echo "🌐 [1/6] Vérification réseau..."
  if [ -z "$(ip route show default 2>/dev/null)" ]; then
    echo "❌ Réseau WSL mort — fix (PowerShell) : wsl --shutdown puis relance sofalost."
    return 1
  fi
  if ! getent hosts github.com >/dev/null 2>&1; then
    echo "⚠️ DNS KO — réparation resolv.conf..."
    printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' | sudo tee /etc/resolv.conf >/dev/null 2>&1
    sleep 1
    getent hosts github.com >/dev/null 2>&1 || { echo "❌ DNS toujours cassé : wsl --shutdown."; return 1; }
  fi
  echo "✅ Réseau OK."

  # ─── [2/6] Ubuntu full update (sudo sans mot de passe) ───
  echo
  echo "🔄 [2/6] Mise à jour Ubuntu..."
  sudo apt update || { echo "❌ apt update KO."; return 1; }
  local upgrade_log
  upgrade_log=$(mktemp)
  sudo apt full-upgrade -y | tee "$upgrade_log" >/dev/null
  local rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then echo "❌ full-upgrade KO."; rm -f "$upgrade_log"; return 1; fi
  grep -qiE 'linux-image-[0-9]' "$upgrade_log" && echo "⚠️ Kernel WSL mis à jour — wsl --shutdown pour l'appliquer."
  rm -f "$upgrade_log"
  sudo apt autoremove -y
  echo "✅ Ubuntu à jour."

  # ─── [3/6] Updates des 6 agents ───
  echo
  echo "🤖 [3/6] Updates des agents..."
  command -v claude >/dev/null 2>&1 && { claude update || echo "⚠️ claude update KO, on continue."; }
  command -v openclaw >/dev/null 2>&1 && { openclaw update --yes --no-restart || echo "⚠️ openclaw update KO, on continue."; }
  command -v codex >/dev/null 2>&1 && { codex update || echo "⚠️ codex update KO, on continue."; }
  command -v opencode >/dev/null 2>&1 && { opencode upgrade || echo "⚠️ opencode upgrade KO, on continue."; }
  command -v hermes >/dev/null 2>&1 \
    && { hermes update --yes || { sleep 10; hermes update --yes; } || echo "⚠️ hermes update KO, on continue."; }
  command -v dsh >/dev/null 2>&1 && { npm install -g @deepseek-ai/dsh >/dev/null 2>&1 || echo "⚠️ dsh update KO, on continue."; }
  echo "✅ Agents à jour."

  # ─── [4/6] Skills ───
  echo
  echo "🧩 [4/6] Skills..."
  local s9="https://raw.githubusercontent.com/decolua/9router/refs/heads/master/skills"
  local s9_ok=0
  for skill in 9router 9router-chat 9router-image 9router-tts; do
    curl -sL --max-time 10 "$s9/$skill/SKILL.md" -o /tmp/9sk-$skill.md 2>/dev/null \
      && s9_ok=$((s9_ok+1)) \
      || echo "⚠️ $skill : fetch KO, copie locale conservée."
  done
  echo "✅ $s9_ok/4 skills 9router fetchés."
  local dest
  for dest in ~/.claude/skills ~/.hermes/skills/claude-import ~/.config/opencode/skills ~/.codex/skills ~/.agents/skills; do
    mkdir -p "$dest"
    for skill in 9router 9router-chat 9router-image 9router-tts; do
      [ -f /tmp/9sk-$skill.md ] && mkdir -p "$dest/$skill" && cp /tmp/9sk-$skill.md "$dest/$skill/SKILL.md"
    done
  done
  rm -f /tmp/9sk-9router*.md
  if command -v openclaw >/dev/null 2>&1 && [ -d "$HOME/.claude/skills" ]; then
    local oc_ok=0 oc_fail=0
    for s in "$HOME"/.claude/skills/*/; do
      n=$(basename "$s")
      case "$n" in 9mode-settings) continue ;; esac
      if timeout 30 openclaw skills install --force "$s" >/dev/null 2>&1; then
        oc_ok=$((oc_ok+1))
      else
        oc_fail=$((oc_fail+1))
      fi
    done
    echo "✅ OpenClaw skills : $oc_ok OK, $oc_fail échecs."
  fi
  echo "✅ Skills à jour."

  # ─── [5/6] Docker 9router (données préservées) ───
  echo
  echo "🐳 [5/6] 9router (Docker)..."
  if ! command -v docker >/dev/null 2>&1; then
    echo "⚠️ Docker introuvable — étape sautée."
  else
    for i in {1..30}; do docker info >/dev/null 2>&1 && break; sleep 1; done
    if ! docker info >/dev/null 2>&1; then
      echo "⚠️ Docker Desktop indisponible — étape sautée."
    elif docker ps -a --format '{{.Names}}' | grep -qx "9router"; then
      local img_avant img_apres
      img_avant=$(docker inspect 9router --format '{{.Image}}' 2>/dev/null)
      echo "   ⏳ docker pull decolua/9router:latest..."
      if docker pull decolua/9router:latest; then
        img_apres=$(docker image inspect decolua/9router:latest --format '{{.Id}}' 2>/dev/null)
        if [ "$img_avant" = "$img_apres" ]; then
          echo "✅ 9router déjà à la dernière image."
          docker start 9router >/dev/null 2>&1
        else
          echo "⬆️ Nouvelle image — recréation (données sur volume 9router-data, préservées)..."
          docker tag decolua/9router:latest decolua/9router:sofalost-rollback >/dev/null 2>&1
          docker stop 9router >/dev/null 2>&1
          docker rm 9router >/dev/null 2>&1
          docker run -d --name 9router --restart always --network ai-network \
            -p 20128:20128 -v 9router-data:/app/data decolua/9router:latest >/dev/null 2>&1
          local ok=0
          for i in {1..20}; do
            curl -fsS --max-time 2 "$health_url" >/dev/null 2>&1 && { ok=1; break; }
            sleep 1
          done
          if [ "$ok" = 1 ]; then
            echo "✅ 9router à jour et opérationnel."
          else
            echo "❌ 9router KO après recréation — rollback vers l'image précédente..."
            docker stop 9router >/dev/null 2>&1
            docker rm 9router >/dev/null 2>&1
            docker run -d --name 9router --restart always --network ai-network \
              -p 20128:20128 -v 9router-data:/app/data decolua/9router:sofalost-rollback >/dev/null 2>&1
            echo "   Rollback effectué. Diagnostic : docker logs --tail 40 9router"
          fi
        fi
      else
        echo "⚠️ docker pull KO — conteneur existant laissé tel quel."
        docker start 9router >/dev/null 2>&1
      fi
    else
      echo "❌ Conteneur '9router' absent — relance install-stack.sh."
    fi
    if ! curl -fsS --max-time 2 "$health_url" >/dev/null 2>&1; then
      echo "⚠️ 9router ne répond pas — restart..."
      docker restart 9router >/dev/null 2>&1
      local ok3=0
      for i in {1..20}; do
        curl -fsS --max-time 2 "$health_url" >/dev/null 2>&1 && { ok3=1; break; }
        sleep 1
      done
      [ "$ok3" = 1 ] && echo "✅ 9router récupéré." || echo "❌ 9router toujours KO — docker logs --tail 40 9router"
    fi
  fi

  # ─── [6/6] Menu ───
  echo
  echo "🚀 Quel agent veux-tu lancer ?"
  echo "   1) claude   (Claude Code, 9sonnet)"
  echo "   2) hermes   (Hermes Agent, 9glm 256K)"
  echo "   3) opencode (OpenCode, 9glm 256K)"
  echo "   4) dsh      (DeepSeek Harness, 9glm 256K)"
  echo "   5) codex    (Codex CLI, 9kimi)"
  echo "   6) openclaw (OpenClaw, 9glm 256K)"
  local choix
  read -r -p "Choix [1-6] : " choix
  case "$choix" in
    1) echo "🚀 Lancement de Claude Code..."; claude ;;
    2) echo "🚀 Lancement de Hermes..."; hermes ;;
    3) echo "🚀 Lancement de OpenCode..."; opencode ;;
    4) echo "🚀 Lancement de DeepSeek Harness..."; dsh web ;;
    5) echo "🚀 Lancement de Codex..."; codex ;;
    6) echo "🚀 Lancement de OpenClaw..."; openclaw ;;
    *) echo "ℹ️ Aucun choix valide — rien n'est lancé."; return 0 ;;
  esac
}
# <<< sofalost (stack-hugo) <<<
EOSOF
ok "Fonction sofalost ajoutée à ~/.bashrc."

# ============================================================================
# Fin
# ============================================================================
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
