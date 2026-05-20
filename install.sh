#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# install.sh — Primera instalación en el VPS del cliente
#
# Hace:
#   1. Chequea que docker + docker compose estén instalados
#   2. Crea .env desde .env.example si no existe (y para que lo edites)
#   3. Pull de las imágenes definidas en .env
#   4. Levanta el stack con docker compose
#
# Uso:
#   ./install.sh                    → modo docker compose (single-host)
#   ./install.sh --stack            → modo swarm (usa stack.yml + Traefik)
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
cd "$(dirname "$0")"

# Colores
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_OK=$'\033[32m'
C_WARN=$'\033[33m'
C_ERR=$'\033[31m'
C_INFO=$'\033[36m'

print_header() { echo; echo "${C_BOLD}═══ $1 ═══${C_RESET}"; }
print_ok()     { echo "${C_OK}✓${C_RESET} $1"; }
print_warn()   { echo "${C_WARN}!${C_RESET} $1"; }
print_err()    { echo "${C_ERR}✗${C_RESET} $1" >&2; }
print_info()   { echo "${C_INFO}▸${C_RESET} $1"; }

MODE="compose"
if [[ "${1:-}" == "--stack" || "${1:-}" == "swarm" ]]; then
  MODE="swarm"
fi

print_header "Platform — Install (${MODE})"

# ─── Pre-flight: docker disponible ──────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  print_err "docker no está instalado. Instalalo primero: https://docs.docker.com/engine/install/"
  exit 1
fi
print_ok "docker presente: $(docker --version)"

if ! docker compose version >/dev/null 2>&1; then
  print_err "docker compose v2 no está disponible. Instalá Docker Engine moderno o docker-compose-plugin."
  exit 1
fi
print_ok "docker compose v2 presente"

if [[ "$MODE" == "swarm" ]]; then
  if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    print_err "Swarm no está inicializado. Corré: docker swarm init"
    exit 1
  fi
  print_ok "swarm activo"
fi

# ─── Crear .env si no existe ────────────────────────────────────────────────
if [[ ! -f .env ]]; then
  cp .env.example .env
  print_warn ".env creado desde .env.example"
  print_warn "EDITALO con los valores reales del cliente antes de seguir:"
  echo "    DATABASE_URL, JWT_SECRET, PUBLIC_HOST, SEED_ADMIN_*, IMAGE_*_TAG"
  echo
  print_info "Cuando termines, volvé a correr: ./install.sh"
  exit 0
fi
print_ok ".env existe"

# ─── Cargar .env y validar mínimos ──────────────────────────────────────────
set -a
# shellcheck disable=SC1091
source .env
set +a

required=(IMAGE_BACKEND_TAG IMAGE_FRONTEND_TAG DATABASE_URL JWT_SECRET SEED_ADMIN_EMAIL SEED_ADMIN_PASSWORD)
missing=()
for var in "${required[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done
if (( ${#missing[@]} > 0 )); then
  print_err "Faltan variables obligatorias en .env: ${missing[*]}"
  exit 1
fi
print_ok "variables obligatorias presentes"

# ─── Pull imágenes ──────────────────────────────────────────────────────────
print_header "Pull imágenes"
docker pull "${IMAGE_BACKEND_TAG}"
docker pull "${IMAGE_FRONTEND_TAG}"
print_ok "imágenes en cache local"

# ─── Levantar stack ─────────────────────────────────────────────────────────
if [[ "$MODE" == "swarm" ]]; then
  print_header "Deploy stack (swarm)"
  docker stack deploy -c stack.yml platform
  print_ok "stack desplegado"
  echo
  echo "Verificá con:  docker stack services platform"
  echo "Logs:           docker service logs -f platform_backend"
else
  print_header "Up docker compose"
  docker compose up -d
  print_ok "containers arriba"
  echo
  echo "Verificá con:  docker compose ps"
  echo "Logs:           docker compose logs -f backend"
fi

print_header "Done"
echo
echo "Login inicial: ${SEED_ADMIN_EMAIL} / (la SEED_ADMIN_PASSWORD del .env)"
echo
