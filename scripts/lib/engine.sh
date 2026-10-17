# Operational helpers share the launchers' CLI > environment > auto policy.
engine() { "$ENGINE_COMMAND" "$@"; }

engine_status() {
  local name="$1" version remote
  ENGINE_CLIENT=missing ENGINE_SERVER=unavailable ENGINE_READY=false
  command -v "$name" >/dev/null 2>&1 || return 0
  ENGINE_CLIENT="$("$name" --version 2>/dev/null || true)"
  [[ -n "$ENGINE_CLIENT" ]] || ENGINE_CLIENT=unavailable
  if [[ "$name" == podman ]]; then
    remote="$("$name" info --format '{{.Host.ServiceIsRemote}}' 2>/dev/null)" || return 0
    [[ "$remote" == true || "$remote" == false ]] || return 0
    version="$("$name" version --format '{{.Client.Version}}' 2>/dev/null)" || return 0
    [[ -n "$version" ]] || return 0
    ENGINE_CLIENT="$version"
    if [[ "$remote" == false ]]; then
      ENGINE_SERVER="not applicable (local Podman engine $version)"
      ENGINE_READY=true
      return 0
    fi
  fi
  if version="$("$name" version --format '{{.Server.Version}}' 2>/dev/null)" && [[ -n "$version" ]]; then
    ENGINE_SERVER="$version"
    ENGINE_READY=true
    version="$("$name" version --format '{{.Client.Version}}' 2>/dev/null || true)"
    [[ -z "$version" ]] || ENGINE_CLIENT="$version"
  fi
}

resolve_engine() {
  local requested="$1" candidate
  case "$requested" in
    auto|docker|podman) ;;
    *) echo "Invalid engine '$requested'. Expected auto, docker, or podman." >&2; return 1 ;;
  esac
  for candidate in docker podman; do
    [[ "$requested" == auto || "$requested" == "$candidate" ]] || continue
    engine_status "$candidate"
    if [[ "$ENGINE_READY" == true ]]; then printf '%s\n' "$candidate"; return 0; fi
  done
  if [[ "$requested" == auto ]]; then
    echo 'No healthy container engine is available. Start Docker or repair Podman.' >&2
  else
    engine_status "$requested"
    if [[ "$ENGINE_CLIENT" == missing ]]; then
      echo "Selected engine '$requested' client is missing." >&2
    else
      echo "Selected engine '$requested' server is unreachable or unhealthy." >&2
    fi
  fi
  if [[ "$requested" != docker ]]; then
    echo "Inspect Podman with 'podman machine list' and 'podman system connection list'; start the intended stopped machine with 'podman machine start <name>'." >&2
  fi
  return 1
}

parse_engine_options() {
  REQUESTED_ENGINE="${AI_SANDBOX_ENGINE:-auto}"
  NO_CACHE=false SKIP_BUILD=false
  while (($#)); do
    case "$1" in
      --engine) [[ $# -ge 2 ]] || { echo 'Missing engine for --engine.' >&2; return 1; }; REQUESTED_ENGINE="$2"; shift 2 ;;
      --no-cache) NO_CACHE=true; shift ;;
      --skip-build) SKIP_BUILD=true; shift ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done
}
