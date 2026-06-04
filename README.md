# platform-docker

Stack de despliegue de **Brain Platform** para correr en el VPS del cliente.

Este repo NO tiene código fuente — sólo `docker-compose.yml` / `stack.yml` que **pullean** las imágenes ya buildeadas y subidas a Docker Hub por el equipo de desarrollo.

> Repo hermano con el código: **`platform/`**.

---

## Qué incluye

| Archivo | Para qué |
|---|---|
| `docker-compose.yml` | Stack single-host (uso típico — un VPS solo) |
| `stack.yml` | Stack Swarm + Traefik (cliente con cluster propio) |
| `.env.example` | Plantilla de variables — copiala a `.env` y editá |
| `install.sh` | Primera instalación (chequea pre-requisitos, levanta el stack) |
| `update.sh` | Actualizar versión (pull + recreate) |

---

## Pre-requisitos en el VPS

- Docker Engine 24+
- docker compose v2 (`docker compose version`)
- Para `stack.yml`: swarm inicializado (`docker swarm init`) y Traefik corriendo en una red overlay
- Postgres **externo** ya corriendo y accesible — el template **no** crea su DB
- (Opcional) Chatwoot, Metabase, NocoDB, n8n ya desplegados si vas a embeberlos

---

## Primera instalación

```bash
# 1. clonar el repo en el VPS
git clone <repo-platform-docker> platform-docker
cd platform-docker

# 2. crear el .env (lo arma desde el .example)
./install.sh
# → te dice que edites el .env y vuelvas a correr

# 3. editá los valores reales del cliente
nano .env
#   IMAGE_BACKEND_TAG, IMAGE_FRONTEND_TAG
#   DATABASE_URL (apunta al postgres del cliente)
#   JWT_SECRET (openssl rand -hex 32)
#   PUBLIC_HOST, CORS_ORIGIN
#   SEED_ADMIN_EMAIL, SEED_ADMIN_PASSWORD
#   integraciones que use el cliente (chatwoot/metabase/nocodb/n8n)

# 4. levantar
./install.sh                # docker compose single-host
# o
./install.sh --stack        # Swarm + Traefik (usa stack.yml)
```

**Login inicial**: `SEED_ADMIN_EMAIL` / `SEED_ADMIN_PASSWORD` del `.env`.

### Primer arranque sobre DB vacía

En `.env` poné `RUN_DB_PUSH=true` SÓLO para el primer arranque para que Prisma cree las tablas. Después volvelo a `false` (en DB compartida con el CRM del cliente, `db push --accept-data-loss` puede dropear tablas que no estén en el schema).

---

## Actualizar versión

Workflow típico cuando el equipo de desarrollo publica una versión nueva en Docker Hub:

```bash
# 1. editá .env y cambiá las tags
nano .env
# IMAGE_BACKEND_TAG=javierrodriguez4/platform-backend:0.4.0
# IMAGE_FRONTEND_TAG=javierrodriguez4/platform-frontend:0.7.0

# 2. aplicá
./update.sh                 # docker compose
# o
./update.sh --stack         # swarm
```

`update.sh` hace `docker pull` de las imágenes nuevas, recrea los containers y limpia imágenes dangling.

### Rollback

Volvé a tags anteriores en el `.env` y corré `./update.sh` otra vez. Las imágenes viejas siguen en Docker Hub.

---

## Comandos útiles

| Para qué | Compose | Swarm |
|---|---|---|
| Ver estado | `docker compose ps` | `docker stack services platform` |
| Logs backend | `docker compose logs -f backend` | `docker service logs -f platform_backend` |
| Logs frontend | `docker compose logs -f frontend` | `docker service logs -f platform_frontend` |
| Reiniciar backend | `docker compose restart backend` | `docker service update --force platform_backend` |
| Apagar todo | `docker compose down` | `docker stack rm platform` |

### Health checks

```bash
curl http://localhost:8080/api/health     # liveness — { ok: true, version }
curl http://localhost:8080/api/ready      # readiness — DB + integraciones
```

(Si el cliente tiene Traefik, usá el `PUBLIC_HOST` en vez de `localhost:8080`.)

---

## Variables principales del `.env`

| Variable | Para qué |
|---|---|
| `IMAGE_BACKEND_TAG` / `IMAGE_FRONTEND_TAG` | Las imágenes a correr — acá cambiás versión |
| `DATABASE_URL` | Postgres externo del cliente |
| `JWT_SECRET` | Secret para firmar JWTs (`openssl rand -hex 32`) |
| `RUN_DB_PUSH` | `true` SOLO la primera vez sobre DB vacía |
| `PUBLIC_HOST` | Dominio público (Traefik) |
| `CORS_ORIGIN` | Igual al PUBLIC_HOST con `https://` |
| `FRONTEND_PORT` | Puerto local (sólo single-host) |
| `EXTERNAL_NETWORK` | Red overlay del cliente (Swarm) |
| `SEED_ADMIN_*` | Usuario admin inicial (idempotente) |
| `AUTH_LOCAL_ENABLED` | `false` para forzar solo OIDC/Keycloak |
| `OIDC_ENABLED` + `OIDC_*` | SSO con Keycloak — `false` por defecto |
| `KEYCLOAK_ADMIN_CLIENT_ID/SECRET` | ABM de usuarios Keycloak desde Platform |
| `METABASE_*` | Embedded analytics — vacío = desactivado |
| `CHATWOOT_*` | SSO + agentes Chatwoot — vacío = desactivado |
| `EVOLUTION_*` | Gateway WhatsApp — vacío = desactivado |
| `N8N_*` | Automatizaciones n8n — vacío = desactivado |
| `NOCODB_PUBLIC_URL` | Shared views NocoDB — vacío = desactivado |
| `BOT_SERVICE_KEY` | Clave para el endpoint `/api/bot` — vacío = 503 |

Ver `.env.example` para el archivo completo con comentarios y valores de ejemplo.

---

## Conectar al postgres del cliente

Tres escenarios típicos:

**1. Postgres en otro container Docker (misma máquina, otra red):**
```env
DATABASE_URL=postgresql://user:pass@nombre_container:5432/platform?schema=public
EXTERNAL_NETWORK=ClienteNet     # red overlay donde vive postgres
```
Y descomentá `external_net` en `docker-compose.yml`.

**2. Postgres en host machine:**
```env
DATABASE_URL=postgresql://user:pass@host.docker.internal:5432/platform?schema=public
```

**3. Postgres managed (RDS, Supabase, Neon, etc.):**
```env
DATABASE_URL=postgresql://user:pass@xxx.amazonaws.com:5432/platform?schema=public
```

La DB **debe existir antes**. El backend NO la crea — sólo aplica el schema (Prisma `db push` cuando `RUN_DB_PUSH=true`).

---

## Conectar a Chatwoot existente

Si Chatwoot del cliente vive en otra red docker (típico), descomentá `external_net` en `docker-compose.yml` y en `.env`:

```env
EXTERNAL_NETWORK=BrainNet                              # red de Chatwoot
CHATWOOT_INTERNAL_URL=http://chatwoot_chatwoot_app:3000
CHATWOOT_PUBLIC_URL=https://chat.cliente.com
CHATWOOT_PLATFORM_TOKEN=...                            # de Chatwoot admin → Platform Apps
```

---

## Troubleshooting

| Síntoma | Posible causa |
|---|---|
| `docker compose up` falla con `image not found` | Las tags del `.env` no existen en Docker Hub. Verificá con `docker pull <tag>` |
| Backend reinicia en loop | Mirá `docker compose logs backend` — usualmente `DATABASE_URL` mal o postgres no accesible |
| 502 desde Traefik | Backend down, o el frontend nginx no llega al container backend (chequear `CORS_ORIGIN` y red) |
| Login falla con 401 | `JWT_SECRET` cambió entre instalaciones — re-loguear |
| Iframes de Chatwoot/n8n no cargan | El servicio externo está bloqueando frame-ancestors. Setear `N8N_SECURITY_HEADERS_FRAME_ANCESTORS=https://${PUBLIC_HOST}` en n8n |

---

## Flujo end-to-end (recordatorio)

```
[DEV en su máquina]
  cd platform/
  edita código
  git push                                      ← repo platform/
  ./scripts/build-and-push.sh 0.4.0 0.7.0       ← publica a Docker Hub

[OPERADOR en VPS del cliente]
  cd platform-docker/
  edita .env  →  IMAGE_BACKEND_TAG=...:0.4.0
                 IMAGE_FRONTEND_TAG=...:0.7.0
  ./update.sh                                   ← pull + restart
```
