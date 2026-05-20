#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# update.sh — Actualizar versión de la plataforma en el VPS del cliente
#
# Flujo típico:
#   1. Editás .env y cambiás IMAGE_BACKEND_TAG / IMAGE_FRONTEND_TAG
#      con las nuevas versiones publicadas en Docker Hub.
#   2. Corrés:
#        ./update.sh                  → docker compose (single-host)
#        ./update.sh --stack          → swarm (stack.yml)
#
# Lo que hace:
#   - pull de las nuevas imágenes
#   - reemplaza los containers en caliente (no apaga el host)
#   - muestra estado final
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail
cd "$(dirname "$0")"

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

if [[ ! -f .env ]]; then
  print_err ".env no existe. Corré ./install.sh primero."
  exit 1
fi

# ─── Leer versiones nuevas del .env ────────────────────────────────────────
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${IMAGE_BACKEND_TAG:?IMAGE_BACKEND_TAG no está definido en .env}"
: "${IMAGE_FRONTEND_TAG:?IMAGE_FRONTEND_TAG no está definido en .env}"

print_header "Platform — Update (${MODE})"
print_info "Backend  → ${IMAGE_BACKEND_TAG}"
print_info "Frontend → ${IMAGE_FRONTEND_TAG}"
echo

read -r -p "¿Confirmás el update? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
  echo "Cancelado."
  exit 0
fi

# ─── Pull ───────────────────────────────────────────────────────────────────
print_header "Pull"
docker pull "${IMAGE_BACKEND_TAG}"
docker pull "${IMAGE_FRONTEND_TAG}"
print_ok "imágenes nuevas en cache"

# ─── Aplicar ────────────────────────────────────────────────────────────────
if [[ "$MODE" == "swarm" ]]; then
  print_header "Update stack (swarm)"
  docker stack deploy -c stack.yml platform
  print_ok "stack actualizado"
  echo
  echo "Estado: docker stack services platform"
else
  print_header "Recreate containers"
  # --pull always por si tag mutó (ej. :latest) — barato si no cambió.
  docker compose up -d --pull always
  print_ok "containers actualizados"

  print_header "Limpieza"
  # Limpia imágenes viejas sin tag para no acumular GB en el VPS.
  docker image prune -f >/dev/null && print_ok "imágenes dangling limpiadas"

  echo
  echo "Estado: docker compose ps"
  echo "Logs:   docker compose logs -f backend"
fi

print_header "Done"
