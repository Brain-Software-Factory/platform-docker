#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# bootstrap-dev.sh — Prepara una VPS limpia para el deploy automático (dev)
#
# Corré esto UNA vez en la VPS, como root (o con sudo). Deja todo listo para
# que GitHub Actions se conecte por SSH y corra ./update.sh.
#
# Hace:
#   1. Instala Docker + compose v2 si faltan
#   2. Crea el usuario de deploy y lo suma al grupo docker
#   3. Autoriza la clave pública SSH de GitHub Actions
#   4. Clona platform-docker en el home del usuario de deploy (si REPO_URL es accesible)
#   5. Crea .env desde .env.example para que lo completes
#
# Uso:
#   sudo DEPLOY_USER=deploy \
#        DEPLOY_PUBKEY="ssh-ed25519 AAAA... github-actions-dev" \
#        REPO_URL=https://github.com/Brain-Software-Factory/platform-docker.git \
#        bash bootstrap-dev.sh
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
DEPLOY_PUBKEY="${DEPLOY_PUBKEY:-}"
REPO_URL="${REPO_URL:-https://github.com/Brain-Software-Factory/platform-docker.git}"

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_INFO=$'\033[36m'; C_RESET=$'\033[0m'
ok()   { echo "${C_OK}✓${C_RESET} $1"; }
warn() { echo "${C_WARN}!${C_RESET} $1"; }
err()  { echo "${C_ERR}✗${C_RESET} $1" >&2; }
info() { echo "${C_INFO}▸${C_RESET} $1"; }

if [[ "$(id -u)" -ne 0 ]]; then
  err "Corré como root o con sudo."
  exit 1
fi

# ─── 1. Docker + compose v2 ─────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  info "Instalando Docker…"
  curl -fsSL https://get.docker.com | sh
  ok "Docker instalado"
else
  ok "Docker ya presente: $(docker --version)"
fi

if ! docker compose version >/dev/null 2>&1; then
  err "docker compose v2 no disponible. Instalá docker-compose-plugin y reintentá."
  exit 1
fi
ok "docker compose v2 presente"

# ─── 2. Usuario de deploy ───────────────────────────────────────────────────
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  info "Creando usuario '$DEPLOY_USER'…"
  useradd -m -s /bin/bash "$DEPLOY_USER"
  ok "usuario '$DEPLOY_USER' creado"
else
  ok "usuario '$DEPLOY_USER' ya existe"
fi
usermod -aG docker "$DEPLOY_USER"
ok "'$DEPLOY_USER' está en el grupo docker"

DEPLOY_HOME="$(eval echo "~${DEPLOY_USER}")"

# ─── 3. Autorizar la clave pública de GitHub Actions ────────────────────────
if [[ -z "$DEPLOY_PUBKEY" ]]; then
  warn "No pasaste DEPLOY_PUBKEY — salteo la autorización SSH."
  warn "Generá el par con:  ssh-keygen -t ed25519 -C github-actions-dev -f gha_dev -N ''"
  warn "  → la PRIVADA (gha_dev) va al secret SSH_KEY del environment dev en GitHub"
  warn "  → la PÚBLICA (gha_dev.pub) la pasás acá como DEPLOY_PUBKEY"
else
  install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "${DEPLOY_HOME}/.ssh"
  AUTH="${DEPLOY_HOME}/.ssh/authorized_keys"
  touch "$AUTH"
  if ! grep -qF "$DEPLOY_PUBKEY" "$AUTH" 2>/dev/null; then
    printf '%s\n' "$DEPLOY_PUBKEY" >> "$AUTH"
    ok "clave pública autorizada"
  else
    ok "la clave pública ya estaba autorizada"
  fi
  chown "$DEPLOY_USER:$DEPLOY_USER" "$AUTH"
  chmod 600 "$AUTH"
fi

# ─── 4. Clonar platform-docker ──────────────────────────────────────────────
TARGET="${DEPLOY_HOME}/platform-docker"
if [[ -d "$TARGET/.git" ]]; then
  ok "platform-docker ya clonado en $TARGET"
else
  info "Clonando platform-docker en $TARGET…"
  if sudo -u "$DEPLOY_USER" git clone "$REPO_URL" "$TARGET" 2>/dev/null; then
    ok "repo clonado"
  else
    warn "No se pudo clonar (repo privado sin credenciales en la VPS)."
    warn "Cloná manualmente o copiá la carpeta platform-docker a: $TARGET"
  fi
fi

# ─── 5. .env listo para completar ───────────────────────────────────────────
if [[ -d "$TARGET" ]]; then
  if [[ ! -f "$TARGET/.env" && -f "$TARGET/.env.example" ]]; then
    sudo -u "$DEPLOY_USER" cp "$TARGET/.env.example" "$TARGET/.env"
    ok ".env creado desde .env.example"
  fi
fi

# ─── Resumen ────────────────────────────────────────────────────────────────
echo
echo "${C_OK}═══ Bootstrap done ═══${C_RESET}"
echo "Falta:"
echo "  1. Completar  ${TARGET}/.env  con valores de dev:"
echo "       DATABASE_URL=postgresql://user:pass@HOST:5432/platform_dev"
echo "       JWT_SECRET, SEED_ADMIN_EMAIL, SEED_ADMIN_PASSWORD"
echo "       IMAGE_BACKEND_TAG / IMAGE_FRONTEND_TAG  (los setea el deploy automático)"
echo "       RUN_DB_PUSH=true  ← SOLO el primer arranque sobre la DB vacía, después false"
echo "  2. Cargar en GitHub el environment 'dev' (SSH_HOST=esta IP, SSH_USER=${DEPLOY_USER}, SSH_KEY, DEPLOY_PATH=${TARGET}, DEPLOY_MODE=compose)"
echo "  3. Push a develop → el deploy corre solo."
