# Audit Notes — Skills vs backend_core (US-001)

> Read-only fact-checking phase. Each section lists the **exact current
> formulation** in a file and what should change in later stories.
> Format: `path:line` — current → expected.

Reference snapshots:

- `~/Work/friday_releases/cryptoprocessing/backend_core/CLAUDE.md`
- `~/Work/friday_releases/cryptoprocessing/backend_core/order_service/CLAUDE.md`
- `~/Work/friday_releases/cryptoprocessing/backend_core/auth_gateway/CLAUDE.md`
- `~/Work/friday_releases/cryptoprocessing/backend_core/order_service/internal/{app,domain,infrastructure}/`
- `~/Work/friday_releases/cryptoprocessing/backend_core/auth_gateway/internal/`

---

## src/skills/go-microservice/SKILL.md

| Line(s) | Current formulation | Required change | Story |
|---|---|---|---|
| 8–13 | "internal `git.itcrew.info/.../shared/*` packages and the in-repo `service/pkg/*` utilities" | Keep, but make explicit that this is **backend_core delta**, not just any corp Go project | US-003 |
| 27 | "Entities / DTO / Deps / Repository / Usecase / Delivery (HTTP, gRPC) / Workers" | Reorder: `Delivery (gRPC, Kafka, HTTP-only-in-gateway)`. gRPC is primary across 17 services, HTTP only in `auth_gateway`. | US-003 |
| 39–47 | Architecture block: shows `internal/domain/{name}/` + `internal/infrastructure/` | Add: `internal/entity/` is at **internal-level** (not inside domain — see order_service). Shown layout is order_service-shaped but mislabels entities. | US-003 |
| 41 | `internal/app/app.go               # CreateApp: composes corporate fx-modules` | OK | — |
| 42 | `domain/{name}/           # one module per domain (entities/dto/deps/...)` | Replace with: `domain/<aggregate>/{deps,delivery/{grpc,kafka},repository/{postgres,redis},usecase/...,outbox/...}`. Note **one** `domain/fx.go` (flat) for ALL aggregates inside a service. | US-003 |
| 87 | `pkg/httputil` shown as standard local utility | Mark as **gateway-only** (`auth_gateway/pkg/httputil`); remove from generic list. Most services have `pkg/errors` (gRPC-mapper) only. | US-003, US-010 |
| 92 | `pkg/timetools` shown as standard | Used in skill template; in real `order_service`/`asset_service` it's not always present — note as optional/legacy. | US-003 |
| 107–129 | "Corporate Error Mapping" block uses `MapErrorToHttp`, `httputil.WriteErrorResponse` | gRPC-first: show `mapError(err) → status.Error(codes.NotFound/InvalidArgument/AlreadyExists/PermissionDenied)`. HTTP variant moves to `api-gateway-pattern.md`. | US-003 |
| 137–164 | `CreateApp` example: shows `infrastructure.GRPCServerModule` AND `infrastructure.HTTPServerModule` side-by-side | Drop HTTP server. Real layouts: gRPC server + Kafka consumer + workers + outbox + healthcheck. HTTP-server lives only in auth_gateway. Add explicit ordering: observability → DB/Redis → external gRPC clients → domain → kafka consumer → workers → gRPC server → healthcheck. | US-003, US-005 |
| 168–187 | "Corporate Domain Checklist" — talks about HTTP handlers, fasthttp, httputil | Replace with gRPC handlers (delivery/grpc/handlers.go), `mapError`, gRPC server registration. Add outbox step. | US-003, US-007 |
| 188–199 | Reference list missing `grpc-delivery.md`, `outbox-pattern.md`, `api-gateway-pattern.md` | Add cross-references (allow dangling links until US-008/9/10). | US-003 |
| 168 (skill description) | "service_template" mention | OK (legacy alias). | — |
| Whole file | Mentions `domain.Module` as composition of `order.Module`, `user.Module`… (per-aggregate Modules) | Real `order_service/internal/domain/fx.go` is **a single flat `fx.Module("domain", ...)` with all `fx.Provide` for every use case + repos**. Side-modules are `outbox.Module` and `worker.Module`. Remove "one fx.go per aggregate" narrative. | US-003 |

---

## src/skills/go-microservice/references/template-structure.md

| Line(s) | Current formulation | Required change | Story |
|---|---|---|---|
| 1–9 | Header says baseline lives in coding-rules | OK, keep "Generic basis → Corporate delta" structure | US-004, US-011 |
| 14–35 | `cmd/app/main.go` skeleton | OK; matches reality. | — |
| 47–98 | `Config` example with `containers.AppConfig`, `HttpServerConfig`, etc. | Real services use `KafkaConsumerConfig`, `KafkaProducerConfig`, `OutboxConfig`, `NetPublisherConfig`, `BusinessConfig`, plus per-client gRPC configs. Replace HTTP-centric example with order_service-style env prefix table. Mention `.local.env` + k8s values. | US-004 |
| 109–117 | "Common environment variables" block — only HTTP/Redis/DB/Logger | Add: `KAFKA_*`, `PRODUCER_OUTBOX_*`, `NET_PUBLISHER_*`, `BUSINESS_*`, `<UPSTREAM_SERVICE>_GRPC_ADDR`, `HEALTHCHECK_*`. | US-004 |
| 128–151 | `CreateApp` example — registers `infrastructure.Module` (composite) | Replace with explicit ordering matching reality (observability → infra → domain → kafka consumer → workers → gRPC server → health). | US-004, US-005 |
| 169–204 | `internal/domain/{name}/` listing: `entities/entities.go`, `usecase/buissines/uc.go`, `repository/http_clients/`, `workers/`, separate `delivery/http,grpc,kafka,rabbit` | **Multiple errors**: (a) entities are at `internal/entity/` not `domain/{name}/entities/`; (b) `buissines` typo — real is `usecase/business/` for one service + flat per-feature folders (`usecase/order/`, `usecase/payout/`, …); (c) `http_clients/` does not exist — real is `internal/infrastructure/<external_service>/{client.go,fx.go}` (gRPC); (d) `workers/` is `worker/` (no `s`); (e) HTTP delivery is gateway-only; (f) RabbitMQ delivery — only some services. | US-004, US-007 |
| 215–234 | Domain `fx.Module` skeleton with `fx.Provide(postgres.NewRepository, buissines.NewUseCase, http.NewHandlers, http.NewRouter)` | Replace: gRPC handlers (`grpc.NewHandler`), `fx.Annotate(impl, fx.As(new(deps.X)))` pattern, single flat `domain/fx.go`. | US-004 |
| 240–303 | `infrastructure.Module` with `httpserver.Module + grpcserver.Module`; large fasthttp Server example | Replace with grpc server bootstrap + `infrastructure/{kafka,worker,grpc/{server,clients/<svc>}}/fx.go` patterns. fasthttp example moves to `api-gateway-pattern.md`. | US-004, US-010 |
| 311–330 | "Infrastructure Constants" block — uses `IpAddressContextKey`, `FingerprintContextKey`, `AccessTokenCookieName`, etc. | These are **auth_gateway-specific**. Move to `api-gateway-pattern.md`. Most services don't define cookie names. | US-004, US-010 |
| 336–408 | `pkg/errors`, `pkg/httputil`, `pkg/ctxutil`, `pkg/timetools` block — `MapErrorToHttp`, `WriteResponse` | Real `pkg/errors` in services is gRPC-mapper-first. Show `mapError(err) → grpc/status` example from order_service `delivery/grpc/handlers.go`. HTTP utilities move to gateway. | US-004 |
| Module name & Go version | Not stated in file | Add: `module <service-name>` (kebab-case), Go 1.25+ (per backend_core CLAUDE.md). | US-004 |
| Pattern diversity | Not described | Add a "Pattern X across Y services" table with side-vs-core split (e.g., outbox: 4 services; rabbit: 1; kafka-consumer: most; redis cache: ~6). | US-004 |
| Side-modules section | Missing | Add: `outbox/`, `worker/`, audit, email — each as a separate fx-module under `domain/fx.go` or `infrastructure/fx.go`. | US-004 |
| Migrations/configs/deploy artifacts | Missing | Mention `db/` and `migrations/`, optional `Dockerfile`, `Makefile`, `README.md`, `docker-compose.yml`, `docs/swagger.*`. | US-004 |

---

## src/skills/go-microservice/references/layer-patterns.md

| Line(s) | Current formulation | Required change | Story |
|---|---|---|---|
| 1–9 | "deltas that come from corporate packages" — OK | Keep "Generic basis → Corporate delta" intent in every section. | US-005, US-011 |
| 11–43 | Entities use `timetools.FrontendTime` | Real: many services use plain `time.Time` + `null.Time` (`guregu/null/v6`). `FrontendTime` is opt-in for legacy frontend API. Soften wording: "if the service exposes `frontend-format` timestamps to merchant API". | US-005 |
| 47–84 | DTO `Validate()` purity — OK; cross-link to `coding-rules → golang/validation.md` | Keep, ensure link still resolves (`coding-rules/references/golang/validation.md`). | US-005 |
| 88–90 | "Deps Layer" — empty | Note: corporate-specific delta = none, but add cross-link to `clean-architecture.md`. | US-005, US-011 |
| 99–195 | Repository — `pgconnector.IDB`, `db.Do(ctx)`, `db.WithTx`, raw SQL strings | Add: query builders — `Masterminds/squirrel` (auth_gateway), `doug-martin/goqu/v9` (order_service), `huandu/go-sqlbuilder` (some). Mention which to use when. | US-005 |
| 199–234 | Usecase — corporate delta is `logger.ILogger.InfowCtx` and `timetools.FrontendTime(time.Now())` | Replace `time.Now()` example with `time.Now()` (`time.Time`) — `FrontendTime` only when serving legacy API. Add `shopspring/decimal` for money. | US-005 |
| 238–308 | "Delivery HTTP — fasthttp + pkg/httputil + pkgerrors.Mapper" — full block presented as primary | **Demote to gateway-only subsection**. Section heading reorder: Delivery gRPC primary, Kafka next, HTTP only inside `api-gateway-pattern.md` link. | US-005, US-010 |
| 313–337 | Delivery gRPC: just lists corporate deltas (mapError, access_level_guard) | Promote to primary section. Add: gRPC server lifecycle via `fx.Invoke(fx.Lifecycle.Append(fx.Hook{OnStart, OnStop}))`, dual external/internal services, `delivery/grpc/handlers.go` shape with `convertX()` for proto↔entity, `validate-go` ValidateAll() interceptor. | US-005, US-008 |
| 340–381 | Workers — covers constructor hygiene & raw-id logging | Add: claim-pattern (e.g., `ClaimPendingReports` style — atomic `UPDATE ... RETURNING` to lease rows), multi-instance workers (`ResumeWithdrawOrderWorker × WORKER_COUNT=3`). Real workers live in `internal/infrastructure/worker/` and/or `internal/domain/<svc>/worker/`. | US-005 |
| 386–408 | "Service Reuse Before New Client" — shared/clients/ paths | Real: per-client lives in `internal/infrastructure/<external_service>/{client.go,fx.go}`. There is no `shared/clients/`. | US-005, US-006 |
| 412–451 | "Cross-Service Boundaries" — keep; valuable conceptually | Mark "Generic basis: see coding-rules/golang/grpc.md → Public IDs". | US-005, US-011 |
| 455–471 | Domain Errors — pkgerrors constructors. OK. | Add note: pkg/errors is **per-service**, not shared package. Keep cross-link to clean-architecture. | US-005 |
| 475–522 | "Lifecycle Shutdown Order in CreateApp" — has start/stop ordering | Promote into a separate "Service start/stop sequence" section (acceptance criterion US-005). | US-005 |
| 526–567 | Generic pagination — `shared/pagination` | Real services use a mix: pgx + manual filter, `shared/pagination`, or service-local. Keep, but link "Generic basis: coding-rules → patterns.md / validation.md". | US-005, US-011 |

---

## src/skills/go-microservice/references/internal-packages.md

| Line(s) | Current formulation | Required change | Story |
|---|---|---|---|
| 199 | `internal/domain/{name}/repository/http_clients/` (in template-structure cross-reference & narrative) | **Wrong**. Real services keep external service clients in `internal/infrastructure/<service>/` and they are gRPC, not HTTP. Remove `repository/http_clients/`, add `infrastructure/grpc/clients/<service>/` pattern. | US-006 |
| 419 | `git.bwg-io.site/processing/new-cryptoprocessing/pkg/logger` | Real path: `git.itcrew.info/Fri_releases/cryptoprocessing/shared/logger`. Old path is leftover. | US-006 |
| 585 | `gl.dteam.site/cryptoprocessing/pkg/healthcheck` | Real: `git.itcrew.info/Fri_releases/cryptoprocessing/shared/healthcheck`. | US-006 |
| 639 | `git.bwg-io.site/processing/new-cryptoprocessing/pkg/events/v2` | Real: `git.itcrew.info/Fri_releases/cryptoprocessing/shared/events/v2`. | US-006 |
| 752 | `git.bwg-io.site/processing/new-cryptoprocessing/pkg/pagination` | Real: `git.itcrew.info/Fri_releases/cryptoprocessing/shared/pagination`. | US-006 |
| 9–73 | pgconnector | OK; verify against go.mod of 5 services. | US-006 |
| 76–127 | redisconnector | OK; add note: redsync used **only in auth_gateway**, not in service-level redis cache (move redsync subsection to api-gateway-pattern.md). | US-006, US-010 |
| 131–199 | kafkaconnector | Add: late handler registration via `fx.Invoke` (handlers must be registered before `Consume()` starts). | US-006 |
| 203–246 | rabbitconnector | Used in only 1–2 services; mark as "rare; only when service consumes from RabbitMQ". | US-006 |
| 661–710 | outbox | Move detailed example to new `outbox-pattern.md`; keep brief table entry only. | US-006, US-009 |
| 770–801 | access_level_guard | OK; keep. | US-006 |
| 894–912 | Quick Reference Table | Add: ratelimit (`go.uber.org/ratelimit`), resty (`github.com/go-resty/resty/v2`) for exchange-services. Add: `shared/outbox`, `shared/access-level-guard` paths. | US-006 |
| Whole file | Missing observability OTel section | Add: loggerfx.LoggerFx, tracerfx.TracerFx, meterfx.MeterFx + OTel attribute conventions. | US-006 |

---

## src/skills/go-microservice/references/new-domain-checklist.md

**File does not exist** — verified by `ls src/skills/go-microservice/references/`.

US-007 needs to **create** this file (or move existing checklist from `examples/` if it lives there). Search:

- `src/skills/go-microservice/SKILL.md` line 199: `examples/new-domain-checklist.md` referenced. The `examples/` directory is also missing.
- Acceptance criterion: file path is `src/skills/go-microservice/references/new-domain-checklist.md` (referenced by `references/` per US-007 acceptance text).

Required content per US-007:
1. `usecase/business/` (correct spelling) **+** flat `usecase/{feature}/` allowed.
2. Entities at `internal/entity/` (not `domain/<svc>/entities/`).
3. gRPC handlers checklist (replace HTTP).
4. Rule: **new use case → fx.Provide added to existing flat `internal/domain/fx.go`, no new fx.go file**.
5. Side-module indicators: when to create separate `{outbox,notify,worker}/fx.go`.
6. Optional outbox step (services with external events).
7. Worker example: `worker/` (no `s`).

---

## src/skills/coding-rules/SKILL.md and references/golang/*.md (US-002 — corporate scrub)

`grep -rE 'shared/|pgconnector|kafkaconnector|squirrel|shopspring/decimal|redsync|access_level_guard|fasthttp|timetools.FrontendTime|outbox' src/skills/coding-rules/` matches:

| File:line | Match | Verdict |
|---|---|---|
| `SKILL.md:54` | `go-redis/redis`, `go-redsync/redsync` | **Remove** redsync from generic table — corporate-only. Keep `go-redis/redis`. |
| `SKILL.md:55` | `chi`, `echo`, `gin`, `fiber`, `fasthttp` | OK as **opensource library list** (fasthttp is generic). Keep. |
| `SKILL.md:89` | "Consumer idempotency, **outbox**, DLQ" | OK — outbox is generic concept (transactional outbox). Keep. |
| `SKILL.md:90` | "**redsync** distributed locks" | **Remove** — generic alternative is `Redlock` algorithm; specific lib is corporate choice. Re-word to "distributed locks (Redlock)". |
| `clean-architecture.md:31, 121` | `github.com/shopspring/decimal` | Replace with comment "// money via arbitrary-precision decimal library (e.g. shopspring/decimal)". |
| `common.md:500` | `// Go: github.com/shopspring/decimal` | Same — generalise to "arbitrary-precision decimal lib (Go: shopspring/decimal)". Allowed. |
| `redis.md:319, 334–355, 374` | extensive `redsync` examples | **Move** entire "Use go-redsync Instead of Hand-rolled Locks" section to `go-microservice/references/api-gateway-pattern.md` (redsync is used only in auth_gateway). Replace with generic Redlock guidance. |
| `kafka.md:313, 654, 660+` | outbox table integration | **Generic concept** — keep. The implementation example is library-agnostic. Verify no `git.itcrew.info/...shared/outbox` import. |
| `grpc.md:786` | "outbox-подобный механизм" | Generic, keep. |
| `http.md:21–27` | fasthttp/fiber as options | Generic library comparison — keep. |
| `patterns.md:9` | "outbox pattern" | Generic, keep. |

Acceptance criterion (US-002): the same grep should return **0 matches** for `pgconnector`, `kafkaconnector`, `squirrel`, `redsync`, `access_level_guard`, `timetools.FrontendTime`, `shared/`. `shopspring/decimal` and `outbox` and `fasthttp` may stay if generalised.

Allowed additions:
- `coding-rules` may say "money via arbitrary-precision library, not float" without mentioning `shopspring/decimal`.
- "typed errors preferred over sentinel-only" general rule.

---

## MEMORY.md (US-015)

**File does not exist** at `~/.claude/memory/MEMORY.md` (the standard location). Per US-015 acceptance: "If MEMORY.md does not exist or has no relevant entries, story passes with a note explaining no changes needed."

Will verify in US-015.

---

## Cross-cutting findings (apply to multiple files)

1. **gRPC-first across all services** — confirmed by backend_core/CLAUDE.md§"Inter-Service Communication" and per-service CLAUDE.md files. HTTP only in `auth_gateway`.
2. **Single flat `internal/domain/fx.go`** per service — confirmed by reading `order_service/internal/domain/fx.go` (one `fx.Module("domain", …)` with all `fx.Provide` calls flat). The skill's "one Module per aggregate" pattern is **wrong**.
3. **Side-modules**: `outbox.Module`, `worker.Module`, `email.Module`, `audit.Module` — these are separate `fx.Module` siblings of the domain module, not nested.
4. **Entities live at `internal/entity/`** — confirmed in `order_service/internal/entity/`, `auth_gateway/internal/entity/`. Skill's `domain/<svc>/entities/` is wrong.
5. **External service clients are gRPC** — `internal/infrastructure/<service>/{client.go,fx.go}` with `fx.Annotate(NewClient, fx.As(new(deps.<Service>Client)))`. Skill's `repository/http_clients/` is wrong.
6. **Worker dir is singular `worker/`** — confirmed in `order_service/internal/domain/service/worker/` and `internal/infrastructure/worker/`. Skill's `workers/` (plural) is wrong.
7. **Module name** is kebab-case service name (e.g. `order-service`, `auth-gateway`) — confirmed in `auth_gateway/CLAUDE.md` ("Module name: auth-gateway") and `order_service/internal/domain/fx.go` (`order-service/internal/...`).
8. **Configs include `.local.env`** + k8s values — confirmed in `order_service/CLAUDE.md` ("Copy `.local.env` as a starting point").
9. **Common kafka/outbox env prefixes** in services with events: `KAFKA_CONSUMER_`, `KAFKA_PRODUCER_`, `PRODUCER_OUTBOX_`, `NET_PUBLISHER_`, `NOTIFY_`.
10. **Auth-gateway-specific stack**: fasthttp + fasthttp/router + 3 middleware groups (userGroup, userSessionGroup, userSessionOtpGroup) + grpc-gateway proxy to 11 services + redsync + JWT (`golang-jwt/jwt/v5`) + TOTP (`pquerna/otp`) + fernet (`fernet/fernet-go`) + swagger (`swaggo/swag`).

---

## Story → file impact summary

| Story | Files to edit | Files to create |
|---|---|---|
| US-002 | `coding-rules/SKILL.md`, `coding-rules/references/golang/redis.md` (move redsync) | — |
| US-003 | `go-microservice/SKILL.md` | — |
| US-004 | `go-microservice/references/template-structure.md` | — |
| US-005 | `go-microservice/references/layer-patterns.md` | — |
| US-006 | `go-microservice/references/internal-packages.md` | — |
| US-007 | `go-microservice/SKILL.md` (link), maybe layer-patterns | `go-microservice/references/new-domain-checklist.md` |
| US-008 | — | `go-microservice/references/grpc-delivery.md` |
| US-009 | — | `go-microservice/references/outbox-pattern.md` |
| US-010 | — | `go-microservice/references/api-gateway-pattern.md` |
| US-011 | All ref files | — |
| US-012 | `new-domain-checklist.md` (fixes if dry-run finds issues) | — |
| US-013 | `template-structure.md`, `api-gateway-pattern.md` (fixes) | — |
| US-014 | Any with broken links | — |
| US-015 | `MEMORY.md` (if exists) | — |
| US-016 | — | — |
