# PRD: Синхронизация skills `go-microservice` и `coding-rules` с реальной архитектурой `backend_core`

## 1. Introduction/Overview

Skills `go-microservice` и `coding-rules` сейчас расходятся с де-факто архитектурой монорепо `backend_core` (`~/Work/friday_releases/cryptoprocessing/backend_core/`), подтверждённой 7-ю сервисами (`order_service`, `exchange_service`, `auth_gateway`, `mailer_service`, `report_service`, `commission_service`, `accounting_service`, `ledger_service`, `liquidity-service`). В частности skill ведёт по HTTP-first паттерну вместо gRPC, использует ошибочные пути (`buissines`, `deps/dep.go`), описывает устаревший паттерн per-aggregate `fx.go` и не охватывает ключевые корпоративные паттерны (outbox CDC, API gateway, gRPC inter-service clients).

Цель — привести `go-microservice` (обёртку) в правильное отношение к `coding-rules` (базе): убрать дублирование generic-материала, добавить ссылки на базу, оставить только corporate delta. `coding-rules` правится только в generic-плоскости — никакой корпоративной специфики (`shared/*`, `pgconnector`, `kafkaconnector`, `squirrel`, `shopspring/decimal` и т.д.) в нём быть не должно.

## 2. Goals

- Установить чёткое разделение «база (`coding-rules`) → обёртка (`go-microservice`)» во всех reference-файлах.
- Сделать gRPC основным транспортом в `go-microservice`, HTTP — изолировать в gateway-pattern reference.
- Зафиксировать каноничный паттерн `internal/domain/fx.go`: единая плоская точка сборки use case'ов + опциональные side-модули (audit/email/outbox/worker).
- Исправить опечатки (`buissines` → `business`) и неверные пути (`deps/dep.go` → `deps/deps.go`, `entities` → `internal/entity/`).
- Добавить недостающие паттерны: outbox CDC, API gateway (auth_gateway), gRPC delivery layer, gRPC inter-service clients.
- Структуру шаблона (template-structure, layer-patterns) привести 1-в-1 к `order_service` (canonical reference).
- Удалить из `coding-rules` любую корпоративную специфику; перенести её в `go-microservice` как «corporate delta».

## 3. User Stories

### US-001: Прочитать существующие reference-файлы skills и сверить с реальностью
**Description:** Как разработчик skills, я должен изучить текущее состояние всех файлов skills и каноничных сервисов backend_core, чтобы точно знать где какие правки нужны.

**Acceptance Criteria:**
- [ ] Прочитаны все файлы `src/skills/go-microservice/SKILL.md` и `src/skills/go-microservice/references/*.md`
- [ ] Прочитаны все файлы `src/skills/coding-rules/golang/*.md`
- [ ] Прочитаны `~/Work/friday_releases/cryptoprocessing/backend_core/CLAUDE.md`, `order_service/CLAUDE.md`, `auth_gateway/CLAUDE.md`
- [ ] Зафиксирован список конкретных формулировок, которые меняются в каждом файле

### US-002: Переписать `SKILL.md` под gRPC-first нарратив
**Description:** Как пользователь skill, я хочу видеть gRPC как основной транспорт и HTTP только в контексте API gateway, чтобы не получать неверные рекомендации при создании нового сервиса.

**Acceptance Criteria:**
- [ ] В `src/skills/go-microservice/SKILL.md` заменён HTTP-first нарратив на gRPC-first
- [ ] Удалены упоминания «один агрегат = один fx.go»
- [ ] Зафиксирован канонический паттерн `domain/fx.go` (плоская сборка + side-модули)
- [ ] Добавлены ссылки на новые reference-файлы (`api-gateway-pattern.md`, `outbox-pattern.md`, `grpc-delivery.md`)
- [ ] Markdown проходит без сломанных relative-ссылок

### US-003: Переписать `template-structure.md` под реальную раскладку backend_core
**Description:** Как разработчик, создающий новый сервис, я хочу видеть в template-structure точную раскладку папок, совпадающую с `order_service`, чтобы при следовании skill получать структуру 1-в-1 с монорепо.

**Acceptance Criteria:**
- [ ] `internal/entity/` зафиксирован на уровне `internal/`, не внутри домена
- [ ] `internal/infrastructure/` переписан: `grpc/{server,clients/{...}}/`, `kafka/{consumer,producer}/`, `worker/`, `outbox/`, опциональный `http/server/` для gateway, опциональный `postgres/` для multi-DB
- [ ] Зафиксирован `module <service-name>` (kebab-case) и Go 1.25+
- [ ] Описана таблица «Pattern X в Y сервисах» (примеры из 7 сервисов: side-vs-core разделение)
- [ ] Раздел про `domain/fx.go` показывает плоский `fx.Provide` для всех use case'ов основного домена
- [ ] Раздел про side-модули (audit/email/outbox/worker) с примерами из реальных сервисов
- [ ] Раздел Migrations описывает оба варианта (`db/` и `migrations/`)
- [ ] Раздел Configs указывает `.local.env` + values из k8s
- [ ] `Dockerfile`, `Makefile`, `README.md`, `docker-compose.yml`, `docs/swagger.*` помечены как опциональные
- [ ] Используется delta-структура: «Generic basis» (ссылка на coding-rules) → «Corporate delta»

### US-004: Переписать `layer-patterns.md` под gRPC-first и реальные паттерны
**Description:** Как разработчик, я хочу видеть в layer-patterns раздел Delivery с gRPC-первым описанием, секции Repository/UseCase/Errors с корпоративной спецификой, и явный service start/stop sequence.

**Acceptance Criteria:**
- [ ] Раздел Delivery: gRPC primary + Kafka + HTTP (только в gateway-разделе)
- [ ] Раздел Repository: `pgconnector.IDB.Do(ctx)` + `db.WithTx` + squirrel/goqu builders
- [ ] Раздел UseCase: `logger.ILogger.InfowCtx`, `shopspring/decimal` для денег
- [ ] Раздел Errors: основной — gRPC mapping (`MapError → status.Error(codes.*)`), HTTP вынесен в gateway
- [ ] Раздел Workers: claim pattern (`ClaimPendingReports` стиль) + multi-instance (`ResumeWithdrawOrderWorker × 3`)
- [ ] Отдельная секция «Service start/stop sequence»: `observability → DB/Redis → external gRPC clients → domain → kafka consumer → workers → gRPC/HTTP servers → healthcheck`
- [ ] DTO секция: `Validate()` без мутации, `ApplyDefaults()` отдельно
- [ ] Каждый раздел начинается со ссылки на соответствующий файл `coding-rules/golang/*.md`

### US-005: Обновить `internal-packages.md` под реальные shared-зависимости
**Description:** Как разработчик, я хочу видеть точный список shared-пакетов из backend_core с их назначением и корректные пути инфраструктурных клиентов (gRPC, не HTTP).

**Acceptance Criteria:**
- [ ] Удалены упоминания `repository/http_clients/`
- [ ] Добавлен `infrastructure/grpc/clients/{service}/` паттерн с per-client `fx.go` и `fx.Annotate(NewClient, fx.As(new(deps.XClient)))`
- [ ] Сверена таблица shared-пакетов с реальными импортами go.mod из 5 сервисов
- [ ] Раздел Redis: `shared/redisconnector` (single source), `redsync` упомянут только в gateway-pattern
- [ ] Раздел Kafka: `shared/kafkaconnector`, `AddSimpleJSONHandler`, late handler registration
- [ ] Раздел Observability: `loggerfx.LoggerFx`, `tracerfx.TracerFx`, `meterfx.MeterFx` + OTel конвенции
- [ ] Раздел External integrations: `go.uber.org/ratelimit`, `go-resty/resty/v2` для exchange-сервисов

### US-006: Обновить `new-domain-checklist.md` под реальные пути и gRPC
**Description:** Как разработчик, добавляющий новый домен, я хочу видеть чеклист, ведущий в правильное место — без опечаток, с gRPC handlers, с правилом про единый `domain/fx.go`.

**Acceptance Criteria:**
- [ ] `usecase/buissines/` исправлено на `usecase/business/` (+ описан плоский `usecase/` для простых доменов)
- [ ] Entities перенесены на уровень `internal/entity/`
- [ ] HTTP-handlers checklist заменён на gRPC-handlers checklist
- [ ] Явно прописано правило: новый use case в основном домене → `fx.Provide` дописывается в существующий `internal/domain/fx.go`, новый файл НЕ создаётся
- [ ] Перечислены индикаторы side-модуля (когда нужен отдельный `{X}/fx.go`)
- [ ] Добавлен опциональный шаг про outbox для domains с внешними событиями
- [ ] Канонический пример воркера: `worker/` (без `s`)

### US-007: Создать `references/grpc-delivery.md`
**Description:** Как разработчик gRPC-сервиса, я хочу детальный reference про gRPC delivery layer с реальными корпоративными паттернами.

**Acceptance Criteria:**
- [ ] Создан файл `src/skills/go-microservice/references/grpc-delivery.md`
- [ ] Секция «Generic basis» со ссылкой на `coding-rules/golang/grpc.md`
- [ ] Секция «Corporate delta»: `access_level_guard`, dual external/internal services, корпоративный `mapError → codes.*`
- [ ] Описан server lifecycle через `fx.Invoke` и `fx.Hook{OnStart,OnStop}`
- [ ] Структура `delivery/grpc/handlers.go` с примером handler'а
- [ ] Server registration patterns
- [ ] Markdown без сломанных ссылок

### US-008: Создать `references/outbox-pattern.md`
**Description:** Как разработчик сервиса с внешними событиями (`order_service`, `exchange_service`, `auth_gateway`), я хочу понимать структуру и интеграцию outbox CDC паттерна с `shared/outbox`.

**Acceptance Criteria:**
- [ ] Создан файл `src/skills/go-microservice/references/outbox-pattern.md`
- [ ] Описана структура `internal/domain/{...}/outbox/{notify,netpublisher}/`
- [ ] Интеграция в repository: запись в outbox-таблицу внутри `db.WithTx`
- [ ] Описан outbox worker (читает таблицу, публикует в Kafka)
- [ ] Перечислены конфиг-параметры `PRODUCER_OUTBOX_*`
- [ ] Указано, что находится в `internal/infrastructure/outbox/` vs в `internal/domain/.../outbox/`
- [ ] Cross-link на пример из `order_service`

### US-009: Создать `references/api-gateway-pattern.md`
**Description:** Как разработчик, я хочу понимать особенности API gateway (`auth_gateway`) — отдельного архитектурного класса, отличного от gRPC-микросервисов.

**Acceptance Criteria:**
- [ ] Создан файл `src/skills/go-microservice/references/api-gateway-pattern.md`
- [ ] Описан `internal/infrastructure/grpc/proxy/` (HTTP-to-gRPC reverse proxy к 11 backend-сервисам)
- [ ] Описан стек: fasthttp + `fasthttp/router` + 3 middleware-группы
- [ ] Ссылки на `pkg/jwtutil`, `pkg/secure`
- [ ] Описаны библиотеки gateway-only: `fernet/fernet-go`, `golang-jwt/jwt/v5`, `pquerna/otp`, `go-redsync/redsync/v4`
- [ ] Описан swagger-pipeline (`swaggo/swag`, `swag init`)
- [ ] Указано, что HTTP utils (`pkg/httputil.WriteResponse`) живут только здесь
- [ ] Cross-link на пример из `auth_gateway`

### US-010: Очистить `coding-rules` от корпоративной специфики
**Description:** Как пользователь skills opensource-проектов, я хочу, чтобы `coding-rules` оставался generic базой без упоминаний корпоративных библиотек и shared-пакетов.

**Acceptance Criteria:**
- [ ] Прочитаны все `src/skills/coding-rules/golang/*.md`
- [ ] Найденные упоминания `shared/*`, `pgconnector`, `kafkaconnector`, `squirrel`, `shopspring/decimal`, `redsync`, `access_level_guard`, `fasthttp`, `timetools.FrontendTime`, `outbox` — удалены или перенесены в `go-microservice`
- [ ] Generic-материал, случайно живущий в `go-microservice` (общая clean architecture, общий DDD, naming без привязки к библиотекам), перенесён в `coding-rules` или удалён как дубль
- [ ] Допустимые generic-добавления: «деньги через библиотеку произвольной точности, не float» (без упоминания shopspring/decimal), «typed errors предпочтительнее sentinel-only»
- [ ] Структура `coding-rules/SKILL.md` не меняется

### US-011: Применить delta-структуру ко всем reference-файлам go-microservice
**Description:** Как читатель skill, я хочу в каждом reference-файле видеть унифицированную структуру «Generic basis → Corporate delta», чтобы понимать, что универсально, а что специфично для backend_core.

**Acceptance Criteria:**
- [ ] В `layer-patterns.md`, `internal-packages.md`, `template-structure.md`, `new-domain-checklist.md`, `grpc-delivery.md`, `outbox-pattern.md`, `api-gateway-pattern.md` каждая основная секция начинается с «Generic basis: см. `coding-rules/golang/{X}.md`»
- [ ] Секция «Corporate delta» содержит только то, что отличается от generic
- [ ] Удалены любые повторы generic-материала из `coding-rules`
- [ ] Mapping (таблица из плана) применён ко всем парам файлов

### US-012: Кросс-проверка: новый домен по обновлённому checklist'у
**Description:** Как QA процесса skill, я хочу мысленно пройти по обновлённому `new-domain-checklist.md`, чтобы убедиться, что чеклист ведёт в правильное место.

**Acceptance Criteria:**
- [ ] Mental dry-run: «создать новый домен в `order_service`» по новому чеклисту
- [ ] Каждый шаг чеклиста сверен с реальной структурой `order_service/internal/domain/{order,masspay,...}/`
- [ ] Расхождения зафиксированы и устранены

### US-013: Cross-check на втором и третьем сервисе
**Description:** Как QA процесса skill, я хочу проверить, что обновлённые `template-structure.md` и `layer-patterns.md` совпадают не только с `order_service`, но и с простым (`mailer_service`) и gateway-сервисом (`auth_gateway`).

**Acceptance Criteria:**
- [ ] Структура из `template-structure.md` сверена с `mailer_service/` (простой Kafka-consumer)
- [ ] Gateway-pattern из `api-gateway-pattern.md` сверен с `auth_gateway/`
- [ ] Расхождения зафиксированы и устранены

### US-014: Linter-нейтральность markdown
**Description:** Как пользователь, я хочу, чтобы все markdown-файлы skills проходили без сломанных relative-ссылок.

**Acceptance Criteria:**
- [ ] Проверены все relative-ссылки между reference-файлами `go-microservice`
- [ ] Проверены ссылки `go-microservice` → `coding-rules`
- [ ] Битые ссылки исправлены

### US-015: Обновить `MEMORY.md` (если содержит затронутые утверждения)
**Description:** Как процесс skill, я хочу убрать устаревшие memory-записи, противоречащие новому пониманию архитектуры backend_core.

**Acceptance Criteria:**
- [ ] Прочитан `MEMORY.md` (если существует)
- [ ] Найденные утверждения про per-aggregate `fx.go`, HTTP-first и т.д. — обновлены или удалены
- [ ] Новые memory-записи (если нужны) добавлены через Write

### US-016: Финальный git diff review
**Description:** Как разработчик skills, перед коммитом я хочу убедиться глазами, что не удалил полезных generic-объяснений, а только специализировал под backend_core.

**Acceptance Criteria:**
- [ ] `git diff src/skills/` пройден глазами
- [ ] Не удалено ни одного полезного generic-объяснения
- [ ] Все правки только специализируют, а не выкидывают
- [ ] Коммит создан через skill `commit`

## 4. Functional Requirements

- FR-1: Все reference-файлы `go-microservice` должны начинаться с явной ссылки на соответствующий generic-документ `coding-rules` (паттерн «Generic basis: …»).
- FR-2: В `go-microservice` остаётся только corporate delta — материал, который **отличается** от generic.
- FR-3: gRPC должен быть основным транспортом во всех reference-файлах `go-microservice`. HTTP-материал живёт исключительно в `api-gateway-pattern.md`.
- FR-4: Структура шаблона должна совпадать 1-в-1 с `order_service` (canonical reference).
- FR-5: Каноничный паттерн `internal/domain/fx.go` — единая плоская точка сборки use case'ов основного домена + опциональные `{side}/fx.go` для side-concerns (audit/email/outbox/worker).
- FR-6: Все опечатки и неверные пути исправлены: `buissines` → `business`, `deps/dep.go` → `deps/deps.go`, entities на уровне `internal/entity/`, workers — `worker/` (без `s`).
- FR-7: External clients описываются как `infrastructure/grpc/clients/{service}/` с per-client `fx.go`. Паттерн `repository/http_clients/` удалён.
- FR-8: Создан reference `grpc-delivery.md` с детальным описанием gRPC delivery layer (`access_level_guard`, dual services, `mapError`, lifecycle).
- FR-9: Создан reference `outbox-pattern.md` с описанием outbox CDC через `shared/outbox`.
- FR-10: Создан reference `api-gateway-pattern.md` с описанием стиля `auth_gateway` (fasthttp + middleware-groups + gRPC reverse proxy + JWT/2FA + swagger).
- FR-11: `coding-rules` не должен содержать упоминаний `shared/*`, `pgconnector`, `kafkaconnector`, `squirrel`, `shopspring/decimal`, `redsync`, `access_level_guard`, `fasthttp`, `timetools.FrontendTime`, `outbox`.
- FR-12: Generic-материал из `go-microservice` (общая clean architecture, общий DDD, generic naming) перенесён в `coding-rules` или удалён как дубль.
- FR-13: `module <service-name>` (kebab-case) и Go 1.25+ зафиксированы в `template-structure.md`.
- FR-14: Service start/stop sequence (`observability → DB/Redis → external gRPC clients → domain → kafka consumer → workers → gRPC/HTTP servers → healthcheck`) задокументирован в `layer-patterns.md`.
- FR-15: Все relative-ссылки между markdown-файлами skills работают (нет битых линков).

## 5. Non-Goals (Out of Scope)

- Не правим реальные сервисы в `~/Work/friday_releases/cryptoprocessing/backend_core/`.
- Не меняем CI, hooks (`format-and-lint.sh`, `lint-project.sh`, `service-context.sh`), `settings.json`, plugins.
- Не трогаем `src/skills/coding-rules/SKILL.md` базовую структуру — только specific reference-файлы внутри.
- Не создаём «универсальный» шаблон-сервис в repo — каноничным считается реальный `order_service`.
- Не трогаем `CLAUDE.md` корня config-репо (он про symlink-стратегию).
- Не правим другие skills (`commit`, `verify`, `check-di`, `code-review` и др.) кроме `go-microservice` и `coding-rules`.

## 6. Design Considerations

- Документация только в markdown, никаких диаграмм или внешних артефактов.
- Cross-references должны быть relative (`../coding-rules/golang/grpc.md`), а не абсолютные пути.
- Каждый reference-файл должен быть самодостаточным для одной темы; не разваливать тему на несколько файлов.
- Примеры кода — короткие, иллюстрирующие именно corporate delta, не пересказывающие generic.
- Использовать таблицы для сопоставлений (skills vs реальность) — формат уже принят в плане.

## 7. Technical Considerations

- Источник истины — реальный код в `~/Work/friday_releases/cryptoprocessing/backend_core/`. При расхождениях с планом приоритет у кода.
- Каноничные сервисы для проверки:
  - `order_service/` — сложный gRPC-сервис (4 домена, 4 worker'а, outbox)
  - `mailer_service/` — простой Kafka-consumer
  - `auth_gateway/` — API gateway (fasthttp + gRPC proxy)
  - `report_service/` — async report-генератор (claim pattern)
  - `exchange_service/` — external API integrations
- При написании markdown — соблюдать stylistic conventions уже использованные в существующих reference-файлах skills.
- Изменения вносятся в `src/skills/`, симлинки `~/.claude/skills/` подтянутся автоматически.

## 8. Success Metrics

- Структура из `template-structure.md` совпадает 1-в-1 с `order_service/` при визуальной сверке.
- Mental dry-run «создать новый домен» по новому `new-domain-checklist.md` приводит к раскладке, идентичной существующим доменам в `order_service`.
- В `coding-rules/golang/*.md` нет ни одного упоминания corporate-библиотек/shared-пакетов (grep == 0).
- В `go-microservice/references/*.md` каждая основная секция начинается с ссылки на `coding-rules` (manual review).
- Все relative-ссылки между markdown-файлами skills резолвятся (нет 404).
- Расхождения, перечисленные в §1.1–§1.13 плана, закрыты.

## 9. Open Questions

- В `coding-rules` ли уже есть файлы `validation.md`, `migrations.md`, `errors.md` — или их нужно создавать? Если нет, оставляем материал в `go-microservice` с пометкой «TODO: generic часть выделить в coding-rules».
- Считать ли `Test__*` naming convention generic (тогда в `coding-rules`) или corporate (тогда в `go-microservice`)?
- Нужна ли отдельная reference для multi-DB паттерна (`infrastructure/postgres/` как в `report_service`) или это уместно вшить в основной `template-structure.md`?
- Нужно ли явно описывать `docker-compose.yml` стиля `order_service` отдельным reference, или достаточно упоминания в `template-structure.md`?
