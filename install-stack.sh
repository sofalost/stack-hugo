#!/usr/bin/env bash
# ============================================================================
# Stack IA de Hugo — installateur pour potes (WSL2 Ubuntu)
# Usage : bash <(curl -fsSL https://raw.githubusercontent.com/sofalost/stack-hugo/master/install-stack.sh)
# (le script se suffit à lui-même : il clone le repo public sofalost/stack-hugo
# pour récupérer les 33 skills si besoin)
# Ce que fait le script : 1) sudo NOPASSWD 2) installe les 6 applis
# 3) skills (+ skills 9router si tu as déjà un conteneur) 4) plugins Claude
# Code (les mêmes que sur ta machine, Claude Code uniquement — pas mirroré
# vers les 5 autres CLI) 5) ajoute la fonction `sofalost` dans ~/.bashrc
# 6) exec bash.
# La création/config du conteneur 9router n'est plus ici : c'est `sofalost`
# qui s'en charge (update d'image si un conteneur 9router existe déjà).
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
    && ok "Repo cloné (33 skills)." \
    || die "Clonage sofalost/stack-hugo échoué (réseau ?)."
fi
[ -d "$BUNDLE_DIR" ] || die "Skills introuvables (bundle ou repo)."

# ============================================================================
# 0. Conteneur 9router déjà là ?
# ============================================================================
say "Étape 0/6 — Conteneur 9router"
HAS_9ROUTER=false
read -r -p "As-tu déjà un conteneur Docker nommé « 9router » (o/N) ? " _reply
case "$_reply" in
  o|O|oui|Oui|OUI|y|Y|yes|Yes) HAS_9ROUTER=true ;;
esac
if $HAS_9ROUTER; then
  ok "9router détecté : skills 9router seront installés."
else
  warn "Pas de 9router : skills 9router ignorés (sofalost s'en chargera plus tard)."
fi

# ============================================================================
# 1. Sudo sans mot de passe (demandé une seule fois ici)
# ============================================================================
say "Étape 1/6 — Sudo sans mot de passe"
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
say "Étape 2/6 — Dépendances système"
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
say "Étape 3/6 — Installation des 6 applis"

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
# 4. Skills
# ============================================================================
say "Étape 4/6 — Skills"
if $HAS_9ROUTER; then
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
fi

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
  if $HAS_9ROUTER; then
    for skill in 9router 9router-chat 9router-image 9router-tts; do
      [ -f /tmp/9sk-$skill/SKILL.md ] && mkdir -p "$dest/$skill" && cp /tmp/9sk-$skill/SKILL.md "$dest/$skill/SKILL.md"
    done
  fi
done
rm -rf /tmp/9sk-*
ok "Skills déployés sur 5 dossiers ($(ls "$HOME/.claude/skills" | wc -l) dans ~/.claude/skills)."

if command -v openclaw >/dev/null 2>&1; then
  oc_ok=0; oc_fail=0
  for s in "$HOME"/.claude/skills/*/; do
    n=$(basename "$s")
    if timeout 30 openclaw skills install --force "$s" >/dev/null 2>&1; then
      oc_ok=$((oc_ok+1))
    else
      oc_fail=$((oc_fail+1))
    fi
  done
  ok "OpenClaw : $oc_ok skills installés ($oc_fail échecs)."
fi

# ============================================================================
# 5. Plugins Claude Code (installés là où tu les as, toi)
# ============================================================================
# Claude Code uniquement — aucun mirroring vers les 5 autres CLI (ce sont des
# plugins Claude Code, pas des skills du bundle).
say "Étape 5/6 — Plugins Claude Code"
if command -v claude >/dev/null 2>&1; then
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
  install_plugin() {
    local marketplace="$1" plugin_id="$2"
    claude plugin marketplace add "$marketplace" >/dev/null 2>&1 \
      || warn "marketplace $marketplace : add KO"
    claude plugin install "$plugin_id" >/dev/null 2>&1 \
      || warn "plugin $plugin_id : install KO"
  }
  install_plugin anthropics/claude-code                       frontend-design@claude-code-plugins
  install_plugin kepano/obsidian-skills                        obsidian@obsidian-skills
  install_plugin nextlevelbuilder/ui-ux-pro-max-skill           ui-ux-pro-max@ui-ux-pro-max-skill
  install_plugin anthropics/claude-plugins-official             superpowers@claude-plugins-official
  install_plugin bitwize-music-studio/claude-ai-music-skills     bitwize-music@bitwize-music
  install_plugin https://github.com/fadelabs/phantom.git         phantom@phantom

  install_plugin jarrodwatts/claude-hud                          claude-hud@claude-hud
  # statusLine : pointe sur la version la plus récente en cache
  json_set "$HOME/.claude/settings.json" statusLine.type command
  json_set "$HOME/.claude/settings.json" statusLine.padding 0
  HUD_JS='node "$(ls -d "$HOME"/.claude/plugins/cache/claude-hud/claude-hud/*/dist/index.js | sort -V | tail -1)"'
  json_set "$HOME/.claude/settings.json" statusLine.command "$HUD_JS"

  ok "Plugins Claude Code installés (frontend-design, obsidian, ui-ux-pro-max, superpowers, bitwize-music, phantom, claude-hud + statusLine)."
else
  warn "claude introuvable — plugins Claude Code sautés."
fi

# ============================================================================
# 6. Fonction sofalost
# ============================================================================
say "Étape 6/6 — Fonction sofalost"
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
if $HAS_9ROUTER; then
  printf '  ✅ 9router     détecté — skills 9router installés, image à jour via sofalost\n'
else
  printf '  ℹ️  9router     absent — skills 9router ignorés, à relancer si tu en installes un\n'
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
echo "  Ensuite : lance sofalost, puis choisis ton agent (1-6)."
echo
exec bash
