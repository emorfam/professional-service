#!/usr/bin/env bash
# Copyright 2026 Schwarz Digits Cloud GmbH & Co. KG
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Lists the resources of a STACKIT project and shows which of them reference
# each other. Optionally deletes selected objects, ordered by the references it
# found.
#
# Edges are not derived from hard-wired field names. The script first collects
# all IDs, then searches every object for strings that equal a foreign ID and
# records the JSON path of the hit. Renamed fields therefore do not break it,
# but the quality of the edges depends on whether the APIs expose relations as
# IDs inside the object at all.
#
# Status is displayed, not filtered: which field means "active" differs per
# service.
#
# Requirements: stackit CLI (checked with 0.72.0), jq. python3 is optional: with
# it the script reads its own identity from the access token on every run;
# without it the self-check before deleting a service account falls back to the
# key file's issuer (with --key) or refuses.

set -euo pipefail

# --- Options ------------------------------------------------------------------
KEY_DIR="${STACKIT_KEY_DIR:-$HOME/.stackit/keys}"
PROFILE_NAME="${STACKIT_RESOURCE_GRAPH_PROFILE:-resource-graph}"
KEY_SELECTOR=""
PROJECTS=()          # --project-id, else --all-projects or DEFAULT_PROJECT
ALL_PROJECTS=0
REGION=""            # --region, else the region from the CLI configuration
SERVICES=""
FORMAT="text"
DUMP_DIR=""
LIST_SERVICES=0
DELETES=()

# --- Runtime state ------------------------------------------------------------
CLI_PROFILE=""        # profile holding the activated key; empty for the logged-in session
SELF_EMAIL=""         # identity the script runs as, used to refuse deleting itself
DEFAULT_PROJECT=""    # project from the CLI configuration
WORK=""               # scratch directory with one subdirectory per project
KEY_PATHS=()          # service account keys found in KEY_DIR
KEY_EMAILS=()         # their issuer emails, empty when the key has none
SELECTED_KEY_INDEX=-1
DELETE_EXIT_CODE=0    # 1 when a delete step failed or was blocked

readonly RULE='-------------------------------------------------------------------'
readonly UNKNOWN_EMAIL='unknown'

# --- Service catalog ----------------------------------------------------------
# kind|CLI list command. A kind is the resource type as written in KIND/NAME
# selectors; the CLI command group that lists it is the service. Everything here
# is project-scoped; network-area belongs to the organization and is left out on
# purpose.
SERVICE_TABLE='
server|server list
volume|volume list
network|network list
nic|network-interface list
public-ip|public-ip list
security-group|security-group list
load-balancer|load-balancer list
image|image list
key-pair|key-pair list
affinity-group|affinity-group list
ske|ske cluster list
postgresflex|postgresflex instance list
mongodbflex|mongodbflex instance list
mariadb|mariadb instance list
redis|redis instance list
opensearch|opensearch instance list
rabbitmq|rabbitmq instance list
logme|logme instance list
object-storage|object-storage bucket list
dns-zone|dns zone list
kms-keyring|kms keyring list
secrets-manager|secrets-manager instance list
observability|observability instance list
git|git instance list
service-account|service-account list
'

# Catalog kinds: their list is the system catalog, not the project's own
# inventory (images alone quickly reach three digits). They are still queried so
# that a server can point at its image; only referenced entries are displayed.
CATALOG_KINDS="image"

# The delete command is the list command with "delete" instead of "list":
# "ske cluster list" -> "ske cluster delete". This holds for every service in the
# table (CLI 0.72.0, taken from --help). The argument is the ID, except here:
DELETE_BY_NAME=' load-balancer key-pair ske object-storage '
DELETE_BY_EMAIL=' service-account '
# Kinds this script never deletes. image is the system catalog. A keyring can
# only be deleted once it is empty, and a deleted key only leaves it after its
# grace period; the destructive step there is "kms key delete --keyring-id",
# which is not in this table.
DELETE_BLOCKED=' image kms-keyring '

# --- Helpers ------------------------------------------------------------------
usage() {
  cat <<'USAGE'
project-resource-graph.sh [options]

Lists the resources of a project and their references to each other.

Options:
      --key NAME|PATH|EMAIL  Service account key from $STACKIT_KEY_DIR; "?"
                             opens a menu (needs a terminal). Without --key
                             everything runs with the logged-in session.
      --profile NAME         CLI profile for the key. Default:
                             $STACKIT_RESOURCE_GRAPH_PROFILE or resource-graph.
      --project-id ID        Project, may be repeated. Without it the project
                             from the CLI configuration.
      --all-projects         All projects the identity is a member of.
      --region R             Default: region from the CLI configuration.
      --services a,b,c       Query only these services.
      --list-services        Show queryable services and exit.
      --delete KIND/NAME     Delete an object, may be repeated. KIND/ID works
                             too. Needs exactly one project and a terminal.
                             The plan is shown and must be confirmed.
      --format text|mermaid|json   Default: text.
      --dump-dir PATH        Write the raw response of every service there.
  -h, --help                 This help.

Examples:
  ./project-resource-graph.sh
  ./project-resource-graph.sh --key tftest-key --region eu01
  ./project-resource-graph.sh --services server,nic,network --format mermaid
  ./project-resource-graph.sh --dump-dir ./evidence/inventory
  ./project-resource-graph.sh --delete server/web-1 --delete volume/web-1-data
USAGE
}

die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*" >&2; }
require_value() { [[ -n "$2" ]] || die "$1 needs a value"; }

# Runs the CLI in the profile that holds the activated key, if any.
stackit_cli() {
  if [[ -n "$CLI_PROFILE" ]]; then
    STACKIT_CLI_PROFILE="$CLI_PROFILE" stackit "$@"
  else
    stackit "$@"
  fi
}

# True when <kind> is queried: no --services filter, or the kind is listed there.
service_selected() { # <kind>
  [[ -z "$SERVICES" ]] && return 0
  case ",$SERVICES," in (*",$1,"*) return 0 ;; esac
  return 1
}

# Prints the delete command for <kind>, fails for unknown kinds.
delete_command() { # <kind>
  local list_command
  list_command="$(printf '%s\n' "$SERVICE_TABLE" | awk -F'|' -v kind="$1" '$1 == kind { print $2 }')"
  [[ -n "$list_command" ]] || return 1
  printf '%s delete' "${list_command% list}"
}

# Prints which node field the delete command of <kind> takes: id, name or email.
delete_argument_field() { # <kind>
  case "$DELETE_BY_NAME"  in (*" $1 "*) printf 'name';  return 0 ;; esac
  case "$DELETE_BY_EMAIL" in (*" $1 "*) printf 'email'; return 0 ;; esac
  printf 'id'
}

# Prints the exit code recorded for <kind> in <dir>, 1 when nothing was recorded.
service_exit_code() { # <dir> <kind>
  cat "$1/$2.rc" 2>/dev/null || echo 1
}

# Prints the first <bytes> of <file> on one line. LC_ALL=C keeps tr from failing
# when the cut splits a multibyte character.
error_excerpt() { # <file> <bytes>
  head -c "$2" "$1" 2>/dev/null | LC_ALL=C tr '\n' ' '
}

# --- Options ------------------------------------------------------------------
parse_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      # Accept --option=value as well as --option value.
      --*=*)           set -- "${1%%=*}" "${1#*=}" "${@:2}"; continue ;;
      --key)           require_value "$1" "${2:-}"; KEY_SELECTOR="$2"; shift 2 ;;
      --profile)       require_value "$1" "${2:-}"; PROFILE_NAME="$2"; shift 2 ;;
      --project-id)    require_value "$1" "${2:-}"; PROJECTS+=("$2"); shift 2 ;;
      --all-projects)  ALL_PROJECTS=1; shift ;;
      --region)        require_value "$1" "${2:-}"; REGION="$2"; shift 2 ;;
      --services)      require_value "$1" "${2:-}"; SERVICES="$2"; shift 2 ;;
      --list-services) LIST_SERVICES=1; shift ;;
      --delete)        require_value "$1" "${2:-}"; DELETES+=("$2"); shift 2 ;;
      --format)        require_value "$1" "${2:-}"; FORMAT="$2"; shift 2 ;;
      --dump-dir)      require_value "$1" "${2:-}"; DUMP_DIR="$2"; shift 2 ;;
      -h|--help)       usage; exit 0 ;;
      *)               die "unknown option: $1" ;;
    esac
  done
}

validate_options() {
  case "$FORMAT" in
    text|mermaid|json) ;;
    *) die "--format accepts only text, mermaid or json" ;;
  esac
}

list_services() {
  local kind cli_command
  printf 'Queryable services:\n'
  while IFS='|' read -r kind cli_command; do
    [[ -n "$kind" ]] || continue
    printf '  %-18s stackit %s\n' "$kind" "$cli_command"
  done <<< "$SERVICE_TABLE"
}

require_tools() {
  command -v stackit >/dev/null || die "stackit CLI not found"
  command -v jq >/dev/null      || die "jq not found"
}

# The region must be read from the active profile before switching to another
# profile; a profile created with --empty has none. Both values are optional: a
# failure here must not end the script as long as --region and --project-id are set.
load_cli_defaults() {
  local cli_config
  cli_config="$(stackit config list -o json 2>/dev/null || true)"
  if [[ -z "$REGION" ]]; then
    REGION="$(printf '%s' "$cli_config" | jq -r '.region // empty' 2>/dev/null || true)"
  fi
  DEFAULT_PROJECT="$(printf '%s' "$cli_config" | jq -r '.project_id // empty' 2>/dev/null || true)"
}

create_workspace() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/project-resource-graph.XXXXXX")"
  trap 'rm -rf "$WORK"' EXIT
}

# --- Identity -----------------------------------------------------------------
# Prints one line per service account key in KEY_DIR: "<path>\x1f<email>".
# .credentials.kid excludes credentials.json, which only maps environment
# variables to paths and is not a key. The email is empty for keys without
# .credentials.iss.
list_service_account_keys() {
  local file
  for file in "$KEY_DIR"/*.json; do
    [[ -f "$file" ]] || continue
    jq -e '.credentials.kid' "$file" >/dev/null 2>&1 || continue
    jq -r --arg file "$file" '[ $file, (.credentials.iss // "") ] | join("\u001f")' "$file"
  done
}

load_service_account_keys() {
  local path email
  while IFS=$'\037' read -r path email; do
    [[ -n "${path:-}" ]] || continue
    KEY_PATHS+=("$path")
    KEY_EMAILS+=("${email:-}")
  done < <(list_service_account_keys)
  [[ ${#KEY_PATHS[@]} -gt 0 ]] || die "no keys in $KEY_DIR"
}

print_key_menu() {
  local i
  for ((i = 0; i < ${#KEY_PATHS[@]}; i++)); do
    printf '  %d) %-24s %s\n' "$((i + 1))" "$(basename "${KEY_PATHS[$i]}" .json)" "${KEY_EMAILS[$i]:-$UNKNOWN_EMAIL}"
  done
}

# Sets SELECTED_KEY_INDEX from a menu on the terminal.
choose_key_from_menu() {
  local answer
  [[ -t 0 ]] || die "no terminal for the selection:
$(print_key_menu)"
  printf 'Service account keys in %s:\n' "$KEY_DIR" >&2
  print_key_menu >&2
  read -r -p "Choice [1-${#KEY_PATHS[@]}]: " answer || die "no input, no key selected"
  [[ "$answer" =~ ^[0-9]+$ ]] || die "'$answer' is not a number"
  (( 10#$answer >= 1 && 10#$answer <= ${#KEY_PATHS[@]} )) || die "choice outside 1-${#KEY_PATHS[@]}"
  SELECTED_KEY_INDEX=$((10#$answer - 1))
}

# Sets SELECTED_KEY_INDEX to the single key matching <selector> by path, file
# name or email.
find_key() { # <selector>
  local selector="$1" i
  SELECTED_KEY_INDEX=-1
  for ((i = 0; i < ${#KEY_PATHS[@]}; i++)); do
    if [[ "$selector" == "${KEY_PATHS[$i]}" \
       || "$selector" == "$(basename "${KEY_PATHS[$i]}" .json)" \
       || "$selector" == "${KEY_EMAILS[$i]}" ]]; then
      [[ $SELECTED_KEY_INDEX -lt 0 ]] || die "--key '$selector' is ambiguous:
$(print_key_menu)"
      SELECTED_KEY_INDEX="$i"
    fi
  done
  [[ $SELECTED_KEY_INDEX -ge 0 ]] || die "--key '$selector' matches no key:
$(print_key_menu)"
}

# Activates the key in its own CLI profile so the logged-in session in the
# default profile stays untouched.
activate_service_account_key() { # <key-path>
  stackit config profile create "$PROFILE_NAME" --empty --no-set --ignore-existing >/dev/null 2>&1 \
    || die "profile $PROFILE_NAME could not be created"
  STACKIT_CLI_PROFILE="$PROFILE_NAME" stackit auth activate-service-account \
    --service-account-key-path "$1" >/dev/null 2>&1 \
    || die "key $1 could not be activated"
  CLI_PROFILE="$PROFILE_NAME"
}

email_from_access_token() {
  command -v python3 >/dev/null || return 1
  stackit_cli auth get-access-token 2>/dev/null | cut -d. -f2 \
    | python3 -c 'import sys,base64,json;p=sys.stdin.read().strip();print(json.loads(base64.urlsafe_b64decode(p+"="*(-len(p)%4))).get("email") or "")' 2>/dev/null
}

resolve_identity() {
  local token_email
  if [[ -n "$KEY_SELECTOR" ]]; then
    load_service_account_keys
    if [[ "$KEY_SELECTOR" == "?" ]]; then
      choose_key_from_menu
    else
      find_key "$KEY_SELECTOR"
    fi
    activate_service_account_key "${KEY_PATHS[$SELECTED_KEY_INDEX]}"
    SELF_EMAIL="${KEY_EMAILS[$SELECTED_KEY_INDEX]}"
    info "Identity: ${SELF_EMAIL:-$UNKNOWN_EMAIL} (profile $PROFILE_NAME)"
  else
    info "Identity: logged-in session in the active profile"
  fi
  stackit_cli auth get-access-token >/dev/null 2>&1 \
    || die "not authenticated. Run 'stackit auth login' or set --key."
  # The effective identity is in the access token, not in the profile file, and
  # only it is good enough for the self-check before deleting. If reading it
  # fails, SELF_EMAIL keeps the key's email; when that is empty too, the delete
  # path refuses service-account.
  token_email="$(email_from_access_token || true)"
  if [[ -n "$token_email" ]]; then
    SELF_EMAIL="$token_email"
  fi
}

# --- Projects -----------------------------------------------------------------
resolve_projects() {
  local id name
  : > "$WORK/project-names"
  if [[ $ALL_PROJECTS -eq 1 ]]; then
    while IFS=$'\037' read -r id name; do
      [[ -n "${id:-}" ]] || continue
      PROJECTS+=("$id")
      printf '%s\037%s\n' "$id" "$name" >> "$WORK/project-names"
    done < <(stackit_cli project list -o json 2>/dev/null \
               | jq -r '(if type=="array" then . else (.items // []) end)[]
                        | [(.projectId // ""), (.name // "")] | join("\u001f")')
    [[ ${#PROJECTS[@]} -gt 0 ]] || die "no readable projects"
  elif [[ ${#PROJECTS[@]} -eq 0 ]]; then
    [[ -n "$DEFAULT_PROJECT" ]] \
      || die "no project. Set --project-id, use --all-projects or run 'stackit config set project-id ...'."
    PROJECTS+=("$DEFAULT_PROJECT")
  fi
}

# A selector like server/web-1 can match different objects in several projects,
# so deletion is limited to exactly one project.
require_single_project_for_deletion() {
  [[ ${#DELETES[@]} -eq 0 || ${#PROJECTS[@]} -eq 1 ]] \
    || die "--delete needs exactly one project, ${#PROJECTS[@]} are selected"
}

# Prints the project name, or nothing when it is not readable.
project_name() { # <project-id>
  local name
  name="$(awk -F $'\037' -v id="$1" '$1 == id { print $2; exit }' "$WORK/project-names")"
  if [[ -n "$name" ]]; then
    printf '%s' "$name"
    return 0
  fi
  # A subject without read permission on the project gets an error here. The
  # name is decoration, so the function silently falls back to empty.
  stackit_cli project describe "$1" -o json 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true
}

# --- Collection ---------------------------------------------------------------
# Writes the CLI response for one service to <prefix>.json, its stderr to
# <prefix>.err and its exit code to <prefix>.rc. Always succeeds: a service that
# is not enabled in the project responds with an error and must not abort the
# other queries.
fetch_service() { # <project> <prefix> <cli words...>
  local project="$1" prefix="$2"
  shift 2
  local payload rc=0
  payload="$(stackit_cli "$@" -p "$project" --region "$REGION" -o json 2>"$prefix.err")" || rc=$?
  printf '%s' "$rc" > "$prefix.rc"
  if [[ $rc -eq 0 ]]; then
    printf '%s' "$payload" > "$prefix.json"
  fi
  return 0
}

# Queries all selected services of <project> in parallel and records the kinds
# queried in $WORK/<project>/kinds.
collect_project() { # <project>
  local project="$1" dir="$WORK/$1" kind cli_command
  local kinds=()
  mkdir -p "$dir"
  while IFS='|' read -r kind cli_command; do
    [[ -n "$kind" ]] || continue
    service_selected "$kind" || continue
    kinds+=("$kind")
    # </dev/null: a background job must not read the here-string that feeds this loop.
    # shellcheck disable=SC2086  # the command is a word list on purpose
    fetch_service "$project" "$dir/$kind" $cli_command </dev/null &
  done <<< "$SERVICE_TABLE"
  wait
  [[ ${#kinds[@]} -gt 0 ]] || die "--services matches no service: $SERVICES"
  printf '%s\n' "${kinds[@]}" > "$dir/kinds"
}

collect_all_projects() {
  local project
  for project in "${PROJECTS[@]}"; do
    collect_project "$project"
  done
}

dump_raw_responses() {
  local project
  [[ -n "$DUMP_DIR" ]] || return 0
  mkdir -p -- "$DUMP_DIR"
  for project in "${PROJECTS[@]}"; do
    mkdir -p -- "$DUMP_DIR/$project"
    cp "$WORK/$project"/*.json "$WORK/$project"/*.err "$WORK/$project"/*.rc "$DUMP_DIR/$project/" 2>/dev/null || true
  done
  info "Raw responses written to $DUMP_DIR"
}

# --- Nodes and edges ----------------------------------------------------------
# items: the responses are either a list or an object with a list field.
# container_ids: fields that name the surrounding container, never a resource.
# idof: .id, else the first string field ending in Id that is not a container
#   ID, else .name.
# node_key: the kind/id pair that identifies a node everywhere.
# caption: how a node is shown in the text output.
# shellcheck disable=SC2016  # jq code, the $ variables belong to jq
JQ_NODE_LIB='
def items:
  if type == "array" then .
  elif type == "object" then ([.[] | select(type == "array")] | first // [])
  else [] end;
def container_ids: ["projectId","organizationId","folderId","containerId"];
def idof:
  (.id? // (
     [ to_entries[]
       | select(.key | test("Id$"))
       | select(.key as $k | (container_ids | index($k)) == null)
       | select(.value | type == "string")
       | .value ] | first
   ) // .name? // null);
def node_key: .kind + "/" + .id;
def caption: "\(.kind)/\(.name)" + (if .status == "" then "" else " [\(.status)]" end);
'

# Writes one node per line to <dir>/nodes.jsonl. A service whose response cannot
# be parsed is marked with <kind>.jqfail and its error kept in <kind>.jqerr.
build_nodes() { # <dir>
  local dir="$1" kind
  : > "$dir/nodes.jsonl"
  while read -r kind; do
    [[ -n "$kind" ]] || continue
    [[ -f "$dir/$kind.json" ]] || continue
    jq -c --arg kind "$kind" "$JQ_NODE_LIB"'
      items[]
      | . as $it
      | (idof) as $id
      | select($id != null and ($id | tostring) != "")
      | { kind: $kind,
          id: ($id | tostring),
          name: (($it.name? // $it.displayName? // $it.instanceName? // $it.clusterName? // $id) | tostring),
          status: (($it.status? // $it.state? // $it.lifecycleState? // "") | tostring),
          raw: $it }
    ' "$dir/$kind.json" >> "$dir/nodes.jsonl" 2>"$dir/$kind.jqerr" || printf '1' > "$dir/$kind.jqfail"
  done < "$dir/kinds"
}

# Catalog entries without an incoming reference are dropped. The total is kept
# in <kind>.total so the table can say how much was hidden.
hide_unreferenced_catalog_entries() { # <dir>
  local dir="$1" kind
  for kind in $CATALOG_KINDS; do
    grep -c "\"kind\":\"$kind\"" "$dir/nodes.jsonl" > "$dir/$kind.total" 2>/dev/null || printf '0' > "$dir/$kind.total"
  done
  if jq -s -c --arg catalog "$CATALOG_KINDS" '
    ($catalog | split(" ")) as $catalog
    | ( [ .[] | select((.kind | IN($catalog[])) | not) | .raw | .. | strings ] | unique ) as $refs
    | .[]
    | select( ((.kind | IN($catalog[])) | not) or (.id as $i | ($refs | index($i)) != null) )
  ' "$dir/nodes.jsonl" > "$dir/nodes.filtered" 2>/dev/null; then
    mv "$dir/nodes.filtered" "$dir/nodes.jsonl"
  else
    rm -f "$dir/nodes.filtered"
  fi
}

# Writes one edge per line to <dir>/edges.jsonl: every string in a node that
# equals the ID of another node, except container IDs, name and displayName.
build_edges() { # <dir>
  local dir="$1"
  # shellcheck disable=SC2016  # jq code, the $ variables belong to jq
  jq -s -c "$JQ_NODE_LIB"'
    (map({key: .id, value: node_key}) | from_entries) as $ids
    | .[]
    | . as $n
    | ($n | node_key) as $self
    | [ ($n.raw | paths(scalars)) as $p
        | ($n.raw | getpath($p)) as $v
        | select(($v | type) == "string")
        | select($ids[$v] != null)
        | select($ids[$v] != $self)
        | select( ([$p[] | select(type == "string")] | last // "") as $k
                  | ((container_ids + ["name","displayName"]) | index($k)) == null )
        | { from: $self, fromKind: $n.kind, to: $ids[$v], path: ($p | map(tostring) | join(".")) } ]
    | unique_by(.to)[]
  ' "$dir/nodes.jsonl" > "$dir/edges.jsonl" 2>/dev/null || : > "$dir/edges.jsonl"
}

build_graphs() {
  local project dir
  for project in "${PROJECTS[@]}"; do
    dir="$WORK/$project"
    build_nodes "$dir"
    hide_unreferenced_catalog_entries "$dir"
    build_edges "$dir"
  done
}

# --- Deletion -----------------------------------------------------------------
# Order: whoever points at another object goes first. The edges from above
# provide that, limited to the selection. If nothing is free, there is a cycle;
# then one object is picked and the rest is sorted further.
# shellcheck disable=SC2016  # jq code, the $ variables belong to jq
JQ_DELETE_ORDER='
def ready($rest; $E):
  [ $rest[] as $k | select([ $E[] | select(.[1] == $k) ] | length == 0) | $k ];
def order($rest; $E):
  if ($rest | length) == 0 then []
  else (ready($rest; $E)) as $r
    | (if ($r | length) == 0 then $rest[0:1] else $r end) as $n
    | $n + order(($rest - $n); [ $E[] | select((.[0] | IN($n[])) | not) ])
  end;
. as $plan
| map(.key) as $keys
| [ $edges[0][] | select((.from | IN($keys[])) and (.to | IN($keys[]))) | [.from, .to] ] as $E
| order($keys; $E) as $o
| { cycle: [ $E[] as $k | select(($o | index($k[0])) > ($o | index($k[1])))
             | $k[0] + " -> " + $k[1] ],
    plan: [ $o[] as $k | ($plan[] | select(.key == $k)) ] }
'

# What deleting does to objects this script does not list at all. Not verified
# against the API, hence "unclear" where it is.
deletion_note() { # <kind>
  case "$1" in
    dns-zone)        printf "the zone's records go with it" ;;
    secrets-manager) printf "the instance's secrets go with it" ;;
    object-storage)  printf 'unclear whether a bucket with content gets deleted' ;;
    public-ip)       printf 'the address is gone, along with everything pointing at it from outside' ;;
    service-account) printf 'affects all projects; roles and server attachments are not visible here' ;;
    postgresflex|mongodbflex|mariadb|redis|opensearch|rabbitmq|logme)
                     printf 'unclear whether backups survive the instance' ;;
    *) return 1 ;;
  esac
}

# A non-zero exit code has several meanings. The mapping relies on strings in
# the API message and is not verified against the real API.
classify_delete_error() { # <message>
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *"not found"*|*"does not exist"*|*404*) printf 'gone' ;;
    *"in use"*|*"must be empty"*|*conflict*|*409*) printf 'blocked' ;;
    *) printf 'error' ;;
  esac
}

# idof falls back to .name, so two kinds can share the same id. The ID table
# used for the edges then keeps only the last entry.
warn_about_duplicate_ids() { # <dir>
  local duplicates
  duplicates="$(jq -r '.id' "$1/nodes.jsonl" 2>/dev/null | LC_ALL=C sort | uniq -d)"
  if [[ -n "$duplicates" ]]; then
    printf 'Note: these IDs occur more than once, their edges are unreliable:\n' >&2
    printf '%s\n' "$duplicates" | sed 's/^/  /' >&2
  fi
}

refuse_blocked_kind() { # <kind>
  case "$DELETE_BLOCKED" in
    (*" $1 "*)
      if [[ "$1" == "kms-keyring" ]]; then
        die "this script does not delete kms-keyring. A keyring can only be deleted
once it is empty; the destructive step is 'stackit kms key delete <key> --keyring-id <ring>'."
      fi
      die "this script does not delete $1: that is the system catalog, not the project's own inventory." ;;
  esac
}

# Resolves one --delete selector to exactly one node and appends it as a plan
# step to <dir>/delete.raw.
resolve_delete_selector() { # <dir> <project> <selector>
  local dir="$1" project="$2" selector="$3"
  local kind="${selector%%/*}" ref="${selector#*/}" cli_command field hits hit_count
  [[ "$selector" == */* && -n "$kind" && -n "$ref" ]] \
    || die "--delete expects KIND/NAME or KIND/ID, not '$selector'"
  refuse_blocked_kind "$kind"
  cli_command="$(delete_command "$kind")" || die "unknown kind $kind. --list-services shows the kinds."
  field="$(delete_argument_field "$kind")"
  service_selected "$kind" || die "$kind is excluded by --services"
  [[ "$(service_exit_code "$dir" "$kind")" == "0" ]] \
    || die "$kind is not readable in $project: $(error_excerpt "$dir/$kind.err" 120)"
  [[ ! -f "$dir/$kind.jqfail" ]] \
    || die "$kind could not be parsed: $(error_excerpt "$dir/$kind.jqerr" 120)"
  # "network-interface delete" additionally requires --network-id (taken from --help).
  # shellcheck disable=SC2016  # jq code, the $ variables belong to jq
  hits="$(jq -c --arg kind "$kind" --arg ref "$ref" --arg field "$field" --arg command "$cli_command" "$JQ_NODE_LIB"'
    select(.kind == $kind and (.id == $ref or .name == $ref))
    | { key: node_key, kind: .kind, id: .id, name: .name, cmd: $command,
        arg: (if $field == "id" then .id
              elif $field == "name" then .name
              else (.raw.email // .name) end),
        extra: (if $kind == "nic" then ("--network-id " + (.raw.networkId // "")) else "" end) }
  ' "$dir/nodes.jsonl")"
  hit_count="$(printf '%s' "$hits" | grep -c . || true)"
  [[ "$hit_count" -gt 0 ]] || die "--delete $selector matches no object in $project"
  [[ "$hit_count" -eq 1 ]] || die "--delete $selector is ambiguous, use the ID:
$(printf '%s\n' "$hits" | jq -r '"  " + .kind + "/" + .id')"
  printf '%s\n' "$hits" >> "$dir/delete.raw"
}

# Rejects plan steps whose argument the CLI would misread or that must not be
# deleted. Runs after the selectors are resolved so that an empty argument is
# still counted as a hit by the ambiguity check above.
validate_delete_plan() { # <dir>
  local kind arg extra
  while IFS=$'\037' read -r kind arg extra; do
    # An object named "-y" would otherwise be read as a CLI option.
    case "$arg" in
      -*|*" "*|"") die "unusable delete argument '$arg'. Delete the object manually." ;;
    esac
    [[ "$kind" != "nic" || "$extra" != "--network-id " ]] \
      || die "nic/$arg carries no networkId, and the CLI refuses to delete without it."
    if [[ "$kind" == "service-account" ]]; then
      [[ -n "$SELF_EMAIL" ]] \
        || die "the script cannot determine its own identity, so no service-account
is deleted. Install python3 (identity from the access token) or pass --key with a key that carries an issuer email."
      [[ "$arg" != "$SELF_EMAIL" ]] \
        || die "$arg is the identity this script runs as. Refusing to delete itself."
    fi
  done < <(jq -r '[.kind, .arg, .extra] | join("\u001f")' "$1/delete.plan")
}

sort_delete_plan() { # <dir>
  jq -s -c --slurpfile edges <(jq -s . "$1/edges.jsonl") "$JQ_DELETE_ORDER" \
    "$1/delete.plan" > "$1/delete.sorted"
  jq -r '.plan[] | [.kind, .id, .name, .arg, .cmd, .extra] | join("\u001f")' \
    "$1/delete.sorted" > "$1/delete.lines"
}

print_delete_plan() { # <dir> <project>
  local dir="$1" project="$2" display_name step=0 kind id name arg cli_command extra note
  display_name="$(project_name "$project")"
  printf '\nDeletion in project %s (%s), region %s\n' "${display_name:-?}" "$project" "$REGION" >&2
  printf '%s\n' "$RULE" >&2
  while IFS=$'\037' read -r kind id name arg cli_command extra; do
    step=$((step + 1))
    printf '  %2d. %-30s stackit %s %s %s\n' "$step" "$kind/$name" "$cli_command" "$arg" "$extra" >&2
    if note="$(deletion_note "$kind")"; then
      printf '      %s\n' "$note" >&2
    fi
  done < "$dir/delete.lines"

  # References from outside do not block: the edges are guessed from IDs and the
  # API decides. They are listed because they are the most common reason for a
  # rejection.
  # shellcheck disable=SC2016  # jq code, the $ variables belong to jq
  jq -r --slurpfile plan <(jq -s . "$dir/delete.plan") '
    [$plan[0][].key] as $selected
    | select((.to | IN($selected[])) and ((.from | IN($selected[])) | not))
    | "  Note: " + .to + " is referenced by " + .from + ", which stays"
  ' "$dir/edges.jsonl" | LC_ALL=C sort -u >&2
  jq -r '.cycle[] | "  Note: " + . + " points back, the order there is a guess"' \
    "$dir/delete.sorted" >&2

  printf '\n  The order and the notes above come from edges guessed from IDs.\n' >&2
  printf '  A missing edge means a missing note: no message is not proof\n' >&2
  printf '  that nothing points at an object.\n' >&2
  if [[ -n "$SERVICES" ]]; then
    printf '  Only these services were queried: %s. References from other services are invisible.\n' "$SERVICES" >&2
  fi
  printf '  The script cannot tell whether Terraform or OpenTofu manages an object.\n' >&2
  printf '  For such objects "tofu destroy" is the way.\n' >&2
}

confirm_deletion() { # <project>
  local answer
  [[ -t 0 ]] || die "deletion needs a terminal for the confirmation"
  printf '\nDeletion cannot be undone.\n' >&2
  read -r -p "Type the project ID to confirm ($1, region $REGION): " answer \
    || die "no input, nothing deleted"
  [[ "$answer" == "$1" ]] || die "aborted, nothing deleted"
}

# Runs the plan steps in order and appends one result line per step to the
# evidence file. Sets DELETE_EXIT_CODE to 1 when a step failed or was blocked; a
# step whose object is already gone counts as done.
execute_deletion() { # <dir> <project> <evidence-file>
  local dir="$1" project="$2" evidence="$3"
  local kind id name arg cli_command extra message result
  # -y suppresses the CLI's own prompt, confirmation happened above.
  # </dev/null keeps the CLI away from the plan list on stdin.
  while IFS=$'\037' read -r kind id name arg cli_command extra; do
    # shellcheck disable=SC2086  # command and extra are word lists on purpose
    if stackit_cli $cli_command "$arg" $extra -p "$project" --region "$REGION" -y </dev/null \
         >/dev/null 2>"$dir/delete.err"; then
      printf '  request accepted    %-26s %s\n' "$kind/$name" "$id"
      jq -nc --arg step "$kind/$id" '{step: $step, result: "accepted"}' >> "$evidence"
    else
      message="$(error_excerpt "$dir/delete.err" 200)"
      result="$(classify_delete_error "$message")"
      # The result comes from a string match on the API message and is not
      # verified against the real API, so the message is always printed next to
      # it, even when the result says "gone".
      case "$result" in
        gone)    printf '  rejected, message suggests it no longer exists: %s\n' "$message" ;;
        blocked) printf '  rejected, message suggests it is blocked: %s\n' "$message"; DELETE_EXIT_CODE=1 ;;
        *)       printf '  failed: %s\n' "$message"; DELETE_EXIT_CODE=1 ;;
      esac
      printf '    %s\n' "$kind/$name ($id)"
      jq -nc --arg step "$kind/$id" --arg result "$result" --arg message "$message" \
        '{step: $step, result: $result, message: $message}' >> "$evidence"
    fi
  done < "$dir/delete.lines"
}

run_deletion() { # <project>
  local project="$1" dir="$WORK/$1" selector evidence
  warn_about_duplicate_ids "$dir"
  : > "$dir/delete.raw"
  for selector in "${DELETES[@]}"; do
    resolve_delete_selector "$dir" "$project" "$selector"
  done
  # The same node may have been named by name and by ID.
  awk '!seen[$0]++' "$dir/delete.raw" > "$dir/delete.plan"
  validate_delete_plan "$dir"
  sort_delete_plan "$dir"
  print_delete_plan "$dir" "$project"
  confirm_deletion "$project"

  # Written only now, so that an abort leaves no evidence that looks like an
  # execution. Timestamp in the name so nothing gets overwritten. Without .raw,
  # because credentials may be in there.
  evidence="./stackit-delete-${project}-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
  ( umask 077; jq -c '.plan[]' "$dir/delete.sorted" > "$evidence" )
  execute_deletion "$dir" "$project" "$evidence"

  # On stdout, because the result lines above go there too: a redirect of
  # stdout must not cut off this caveat.
  printf '\nAccepted does not mean deleted. Several services process the request\n'
  printf 'asynchronously. Run the script again to see the inventory afterwards.\n'
  printf 'Evidence: %s\n' "$evidence"
}

# --- Output -------------------------------------------------------------------
service_row() { # <service> <objects> <out> <in> <note>
  printf '  %-18s %8s %7s %7s  %s\n' "$@"
}

render_service_row() { # <dir> <kind>
  local dir="$1" kind="$2" rc objects outgoing incoming note
  rc="$(service_exit_code "$dir" "$kind")"
  if [[ "$rc" != "0" ]]; then
    note="$(error_excerpt "$dir/$kind.err" 90)"
    service_row "$kind" "-" "-" "-" "unavailable: ${note:-error $rc}"
    return 0
  fi
  if [[ -f "$dir/$kind.jqfail" ]]; then
    note="$(error_excerpt "$dir/$kind.jqerr" 90)"
    service_row "$kind" "?" "?" "?" "parsing failed: $note"
    return 0
  fi
  objects="$(jq -r --arg k "$kind" 'select(.kind == $k) | .id' "$dir/nodes.jsonl" 2>/dev/null | wc -l | tr -d ' ')"
  outgoing="$(jq -r --arg k "$kind" 'select(.fromKind == $k) | .to' "$dir/edges.jsonl" 2>/dev/null | wc -l | tr -d ' ')"
  incoming="$(jq -r --arg k "$kind" 'select((.to | split("/")[0]) == $k) | .from' "$dir/edges.jsonl" 2>/dev/null | wc -l | tr -d ' ')"
  note=""
  if [[ -f "$dir/$kind.total" ]]; then
    note="of $(cat "$dir/$kind.total") in the catalog, only the referenced ones"
  elif [[ "$objects" != "0" && "$outgoing" == "0" && "$incoming" == "0" ]]; then
    note="no references found"
  fi
  service_row "$kind" "$objects" "$outgoing" "$incoming" "$note"
}

node_label() { # <dir> <key>
  jq -r --arg key "$2" "$JQ_NODE_LIB"'select(node_key == $key) | caption' "$1/nodes.jsonl" | head -1
}

render_edges_from() { # <dir> <key>
  jq -r --arg from "$2" --slurpfile nodes <(jq -s . "$1/nodes.jsonl") "$JQ_NODE_LIB"'
    def pad($n): . as $s | ($n - ($s | length)) as $d
                 | $s + (if $d > 0 then (" " * $d) else "" end);
    select(.from == $from)
    | . as $e
    | ($nodes[0] | map(select(node_key == $e.to)) | first) as $t
    | (($e.to | split("/")[0]) + "/" + ($t.name // "?")) as $lbl
    | "      -> " + ($lbl | pad(44)) + "  " + $e.path
  ' "$1/edges.jsonl" 2>/dev/null
}

render_references() { # <dir>
  local dir="$1" key any=0
  printf '\n  References\n'
  while read -r key; do
    [[ -n "$key" ]] || continue
    any=1
    printf '    %s\n' "$(node_label "$dir" "$key")"
    render_edges_from "$dir" "$key"
  done < <(jq -r '.from' "$dir/edges.jsonl" 2>/dev/null | LC_ALL=C sort -u)
  [[ $any -eq 1 ]] || printf '    none\n'
}

render_unreferenced() { # <dir>
  local lonely
  printf '\n  Without references\n'
  lonely="$(jq -r --slurpfile edges <(jq -s . "$1/edges.jsonl") "$JQ_NODE_LIB"'
    . as $n | node_key as $key
    | select(([$edges[0][] | select(.from == $key or .to == $key)] | length) == 0)
    | "    " + caption
  ' "$1/nodes.jsonl" 2>/dev/null)"
  printf '%s\n' "${lonely:-    none}"
}

render_text() { # <project> <dir>
  local project="$1" dir="$2" display_name kind
  display_name="$(project_name "$project")"
  printf '\n%s\n' "Project ${display_name:-?} ($project), region $REGION"
  printf '%s\n' "$RULE"
  service_row "Service" "Objects" "out" "in" "Note"
  while read -r kind; do
    [[ -n "$kind" ]] || continue
    render_service_row "$dir" "$kind"
  done < "$dir/kinds"
  render_references "$dir"
  render_unreferenced "$dir"
}

render_mermaid() { # <project> <dir>
  local project="$1" dir="$2" display_name
  display_name="$(project_name "$project")"
  printf 'graph LR\n'
  printf '  subgraph "%s"\n' "${display_name:-$project}"
  jq -r '
    "    " + (((.kind + "_" + .id) | gsub("[^A-Za-z0-9_]"; "_"))
              + "[\"" + .kind + "<br/>" + (.name | gsub("\""; "&quot;")) + "\"]")
  ' "$dir/nodes.jsonl" 2>/dev/null
  printf '  end\n'
  jq -r '
    "  " + ((.from | gsub("/"; "_") | gsub("[^A-Za-z0-9_]"; "_"))
            + " --> " + (.to | gsub("/"; "_") | gsub("[^A-Za-z0-9_]"; "_")))
  ' "$dir/edges.jsonl" 2>/dev/null | LC_ALL=C sort -u
}

render_json() { # <project> <dir>
  jq -n --arg project "$1" --arg region "$REGION" \
    --slurpfile nodes <(jq -s . "$2/nodes.jsonl") \
    --slurpfile edges <(jq -s . "$2/edges.jsonl") \
    '{project: $project, region: $region,
      nodes: ($nodes[0] | map(del(.raw))), edges: $edges[0]}'
}

render_all_projects() {
  local project
  for project in "${PROJECTS[@]}"; do
    case "$FORMAT" in
      text)    render_text    "$project" "$WORK/$project" ;;
      mermaid) render_mermaid "$project" "$WORK/$project" ;;
      json)    render_json    "$project" "$WORK/$project" ;;
    esac
  done
  if [[ "$FORMAT" == "text" ]]; then
    printf '\nStatus is shown, not filtered. Edges come from IDs of other objects found\n'
    printf 'inside an object, not from a topology API.\n'
  fi
}

# --- Main ---------------------------------------------------------------------
main() {
  parse_options "$@"
  validate_options
  if [[ $LIST_SERVICES -eq 1 ]]; then
    list_services
    exit 0
  fi
  require_tools
  load_cli_defaults
  [[ -n "$REGION" ]] || die "no region. Set --region or run 'stackit config set region ...'."
  resolve_identity
  create_workspace
  resolve_projects
  require_single_project_for_deletion
  collect_all_projects
  dump_raw_responses
  build_graphs
  if [[ ${#DELETES[@]} -gt 0 ]]; then
    run_deletion "${PROJECTS[0]}"
    exit "$DELETE_EXIT_CODE"
  fi
  render_all_projects
}

main "$@"
