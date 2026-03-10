#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty')

MONOREPO_ROOT="${SERVICE_CONTEXT_MONOREPO_ROOT:-$HOME/Work/friday_releases}"
CONFIGS_DIR="$MONOREPO_ROOT/cryptoprocessing/configs/dev_do_configs"

if [[ -z "$cwd" || "$cwd" != "$MONOREPO_ROOT"* ]]; then
  echo '{}'
  exit 0
fi

find_go_mod() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/go.mod" ]] && { echo "$dir"; return 0; }
    dir=$(dirname "$dir")
  done
  return 1
}

service_root=$(find_go_mod "$cwd") || { echo '{}'; exit 0; }

if [[ "$service_root" == "$MONOREPO_ROOT" ]]; then
  echo '{}'
  exit 0
fi

relative_path="${service_root#"$MONOREPO_ROOT"/}"
case "$relative_path" in
  shared*|protos*|proto*|configs*) echo '{}'; exit 0 ;;
esac

service_dir_name=$(basename "$service_root")
config_name=$(echo "$service_dir_name" | tr '_' '-')
config_file="$CONFIGS_DIR/$config_name/env.dev.yaml"

parse_value() {
  sed -E 's/^[^:]+:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/'
}

# --- Build markdown context ---

ctx="# Service Context: $config_name

## Info
- Source: $relative_path/"

if [[ ! -f "$config_file" ]]; then
  ctx+="
- Config: not found (configs/dev_do_configs/$config_name/env.dev.yaml)"

else
  ctx+="
- Config: configs/dev_do_configs/$config_name/env.dev.yaml"

  # Database
  db=$(grep -E '^[[:space:]]*DB_DATABASE:' "$config_file" | head -1 | parse_value || true)
  [[ -n "$db" ]] && ctx+="
- Database: $db"

  # --- gRPC Dependencies ---
  grpc_deps=$(grep -E '^[[:space:]]*[A-Z_]+_DSN:' "$config_file" \
    | grep -v -E 'amqp://|redis|http|svc\.cluster' \
    | parse_value || true)

  if [[ -n "$grpc_deps" ]]; then
    ctx+="

## gRPC Dependencies"
    while IFS= read -r dep; do
      [[ -n "$dep" ]] && ctx+="
- $dep"
    done <<< "$grpc_deps"
  fi

  # --- RabbitMQ: Consumers ---
  consumer_lines=$(grep -E '^[[:space:]]*[A-Z_]*CONSUMER[A-Z_]*EXCHANGE_NAME:' "$config_file" 2>/dev/null || true)
  consumer_rk_lines=$(grep -E '^[[:space:]]*[A-Z_]*CONSUMER[A-Z_]*ROUTING_KEY:' "$config_file" 2>/dev/null || true)
  consumer_type_lines=$(grep -E '^[[:space:]]*[A-Z_]*CONSUMER[A-Z_]*EXCHANGE_TYPE:' "$config_file" 2>/dev/null || true)

  consumer_section=""
  if [[ -n "$consumer_lines" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      ex=$(echo "$line" | parse_value)
      key=$(echo "$line" | sed -E 's/^[[:space:]]*([A-Z_]+):.*/\1/')
      prefix=$(echo "$key" | sed -E 's/CONSUMER.*EXCHANGE_NAME//')

      rk=$(echo "$consumer_rk_lines" | grep -E "^[[:space:]]*${prefix}CONSUMER" | sed -E 's/^[^:]+:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/' | paste -sd ',' - | sed 's/,/, /g' 2>/dev/null || true)
      etype=$(echo "$consumer_type_lines" | grep -E "^[[:space:]]*${prefix}CONSUMER" | head -1 | parse_value 2>/dev/null || true)

      entry="- Exchange \`$ex\`"
      [[ -n "$etype" ]] && entry+=" ($etype)"
      [[ -n "$rk" ]] && entry+=", routing key: $rk"
      consumer_section+="
$entry"
    done <<< "$consumer_lines"
  fi

  # --- RabbitMQ: Producers (grouped by exchange) ---
  producer_section=$(awk '
    /^[[:space:]]*[A-Z_]+_PRODUCERS?_[A-Z_]*EXCHANGE_NAME:/ {
      key = $0; sub(/[[:space:]]*:.*/, "", key); gsub(/^[[:space:]]+/, "", key)
      val = $0; sub(/^[^:]+:[[:space:]]*"?/, "", val); sub(/"?[[:space:]]*$/, "", val)
      prefix = key; sub(/_EXCHANGE_NAME$/, "", prefix)
      exchanges[prefix] = val
      if (!seen_prefix[prefix]++) prefix_order[++pn] = prefix
    }
    /^[[:space:]]*[A-Z_]+_PRODUCERS?_[A-Z_]*ROUTING_KEY:/ {
      key = $0; sub(/[[:space:]]*:.*/, "", key); gsub(/^[[:space:]]+/, "", key)
      val = $0; sub(/^[^:]+:[[:space:]]*"?/, "", val); sub(/"?[[:space:]]*$/, "", val)
      prefix = key
      if (match(prefix, /_EVENT/)) sub(/_EVENT.*/, "", prefix)
      else sub(/_ROUTING_KEY$/, "", prefix)
      if (routings[prefix] != "") routings[prefix] = routings[prefix] ", " val
      else routings[prefix] = val
    }
    END {
      for (i = 1; i <= pn; i++) {
        p = prefix_order[i]
        ex = exchanges[p]
        rk = routings[p]
        if (rk != "") {
          if (ex_rk[ex] != "") ex_rk[ex] = ex_rk[ex] ", " rk
          else ex_rk[ex] = rk
        }
        if (!seen_ex[ex]++) ex_order[++en] = ex
      }
      for (i = 1; i <= en; i++) {
        ex = ex_order[i]
        if (ex_rk[ex] != "") printf "- Exchange `%s`: %s\n", ex, ex_rk[ex]
        else printf "- Exchange `%s`\n", ex
      }
    }
  ' "$config_file" 2>/dev/null || true)

  if [[ -n "$consumer_section" || -n "$producer_section" ]]; then
    ctx+="

## RabbitMQ"
    [[ -n "$consumer_section" ]] && ctx+="
### Consumes$consumer_section"
    if [[ -n "$producer_section" ]]; then
      ctx+="
### Produces
$producer_section"
    fi
  fi

  # --- Kafka ---
  kafka_topic=$(grep -E '^[[:space:]]*PRODUCER_TOPIC:' "$config_file" | head -1 | parse_value || true)
  kafka_group=$(grep -E '^[[:space:]]*GROUP_ID:' "$config_file" | head -1 | parse_value || true)

  if [[ -n "$kafka_topic" || -n "$kafka_group" ]]; then
    ctx+="

## Kafka"
    [[ -n "$kafka_topic" ]] && ctx+="
- Producer topic: \`$kafka_topic\`"
    [[ -n "$kafka_group" ]] && ctx+="
- Consumer group: \`$kafka_group\`"
  fi

  # --- TLS Clients ---
  tls_section=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key=$(echo "$line" | sed -E 's/^[[:space:]]*([A-Z_]+):.*/\1/')
    prefix=$(echo "$key" | sed -E 's/_TYPE$//')
    svc=$(grep -E "^[[:space:]]*${prefix}_SERVICE_NAME:" "$config_file" | head -1 | parse_value || true)
    [[ -n "$svc" ]] && tls_section+="
- $svc"
  done < <(grep -E '^[[:space:]]*TLS_[A-Z_]+_TYPE:[[:space:]]*"?client' "$config_file" 2>/dev/null || true)

  [[ -n "$tls_section" ]] && ctx+="

## TLS Clients$tls_section"

  # --- Exchange Neighbors ---
  all_exchanges=""
  if [[ -n "$consumer_lines" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      all_exchanges+="$(echo "$line" | parse_value)"$'\n'
    done <<< "$consumer_lines"
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    all_exchanges+="$(echo "$line" | parse_value)"$'\n'
  done < <(grep -E '^[[:space:]]*[A-Z_]+_PRODUCERS?_[A-Z_]*EXCHANGE_NAME:' "$config_file" 2>/dev/null || true)

  unique_exchanges=$(printf '%s' "$all_exchanges" | sort -u | sed '/^$/d' || true)

  if [[ -n "$unique_exchanges" ]]; then
    ctx+="

## Exchange Neighbors"
    while IFS= read -r exchange; do
      [[ -z "$exchange" ]] && continue
      ctx+="
### $exchange"

      producers=""
      consumers=""

      while IFS= read -r match_file; do
        [[ -z "$match_file" ]] && continue
        neighbor=$(basename "$(dirname "$match_file")")

        if grep -qE "_PRODUCERS?_.*EXCHANGE_NAME.*\"${exchange}\"" "$match_file" 2>/dev/null; then
          [[ -n "$producers" ]] && producers+=", "
          producers+="$neighbor"
        fi
        if grep -q "CONSUMER.*EXCHANGE_NAME.*\"${exchange}\"" "$match_file" 2>/dev/null; then
          [[ -n "$consumers" ]] && consumers+=", "
          consumers+="$neighbor"
        fi
      done < <(grep -rl "EXCHANGE_NAME.*\"${exchange}\"" "$CONFIGS_DIR"/*/env.dev.yaml 2>/dev/null || true)

      [[ -n "$producers" ]] && ctx+="
- Producers: $producers"
      [[ -n "$consumers" ]] && ctx+="
- Consumers: $consumers"
    done <<< "$unique_exchanges"
  fi
fi

# --- Migrations ---
migration_section=""

check_migration_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  local count
  count=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  [[ "$count" -eq 0 ]] && return 0
  local rel="${dir#"$MONOREPO_ROOT"/}"
  migration_section+="
- $rel/ ($count files)"
}

check_migration_dir "$service_root/migration"
check_migration_dir "$service_root/migrations"

for base in "$MONOREPO_ROOT/cryptoprocessing/backend_cp/migrations" \
            "$MONOREPO_ROOT/cryptoprocessing/cryptoprocessing/migrations"; do
  check_migration_dir "$base/${config_name}_migration/db/migrations"
  [[ "$config_name" != "$service_dir_name" ]] && \
    check_migration_dir "$base/${service_dir_name}_migration/db/migrations"
done

[[ -n "$migration_section" ]] && ctx+="

## Migrations$migration_section"

# --- Output ---
jq -n --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
