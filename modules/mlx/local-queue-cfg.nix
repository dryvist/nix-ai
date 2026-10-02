# haproxy.cfg for the loopback queue front (./local-queue.nix), rendered from
# the role map. Pure: lib/checks/mlx-local-queue.nix renders it directly.
#
# One backend per model the host class keeps, its server `maxconn` = that
# model's role-map concurrency. Two frontends share those backends, so both
# count against the same slots:
#   wait   — FIFO queue per backend, `timeout queue` then HAProxy's own 503.
#   direct — never queues: 429 the moment the model's slots are taken.
# Every server carries an agent-check against the power agent; on battery it
# answers `maint`, the backend has no usable server, and both frontends
# answer 503 at once.
#
# Returns { ports; text; }. The wait/direct ports come from the endpoint URLs in
# vars/ai-stack.nix, so each number is written once.
{
  roleMap,
  hostClass,
  upstreamPort,
}:
let
  inherit (builtins)
    attrNames
    concatStringsSep
    filter
    head
    match
    ;

  inherit (import ../../vars/ai-stack.nix) endpoints;
  portOf = url: builtins.fromJSON (head (match "http://127.0.0.1:([0-9]+)/v1" url));
  ports = {
    wait = portOf endpoints.mlx_wait;
    direct = portOf endpoints.mlx_direct;
    metrics = 11431;
    powerAgent = 11430;
  };
  upstream = "127.0.0.1:${toString upstreamPort}";
  agent = "agent-check agent-addr 127.0.0.1 agent-port ${toString ports.powerAgent} agent-inter 30s";

  host = roleMap.hosts.${hostClass};
  roles = roleMap.roles // (host.roles or { });
  kept = host.resident ++ host.swap;
  concurrency = key: toString roleMap.models.${key}.concurrency;

  # Names a request may carry for a model: every role bound to it plus its id.
  names =
    key: filter (role: roles.${role}.model == key) (attrNames roles) ++ [ roleMap.models.${key}.id ];

  # Requests naming no kept model (unknown name, or a body past the buffer)
  # queue on the model the `default` role names, so nothing bypasses a queue.
  fallback = roles.default.model;
  defaultBackend = if builtins.elem fallback kept then fallback else head kept;

  lines = concatStringsSep "\n";
  modelAcls = lines (
    map (k: "  acl m_${k} req.body,json_query('$.model') -m str ${toString (names k)}") kept
  );
  routes = lines (map (k: "  use_backend ${k} if m_${k}") kept);
  full = k: "m_${k} { be_conn(${k}) ge ${concurrency k} } || m_${k} { queue(${k}) gt 0 }";
  backend = k: ''
    backend ${k}
      server ${k} ${upstream} maxconn ${concurrency k} ${agent}
  '';
in
{
  inherit ports;
  text = ''
    global
      # Bodies are buffered whole so the `model` field is seen wherever the
      # client serialised it; 2 MiB matches the loopback gate's body cap.
      tune.bufsize 2097152
      maxconn 64
      log stderr format raw local0 notice

    defaults
      mode http
      log global
      option http-buffer-request
      timeout http-request 30s
      timeout connect 5s
      timeout client 300s
      timeout server 300s
      timeout queue 90s

    frontend llm_wait
      bind 127.0.0.1:${toString ports.wait}
      maxconn 8
    ${modelAcls}
      acl infer method POST
    ${routes}
      use_backend passthrough if !infer
      default_backend ${defaultBackend}

    frontend llm_direct
      bind 127.0.0.1:${toString ports.direct}
    ${modelAcls}
      acl infer method POST
      http-request return status 429 content-type application/json string "{\"error\":\"model busy\"}" if ${concatStringsSep " || " (map full kept)}
    ${routes}
      use_backend passthrough if !infer
      default_backend ${defaultBackend}

    frontend metrics
      bind 127.0.0.1:${toString ports.metrics}
      http-request use-service prometheus-exporter if { path /metrics }

    ${lines (map backend kept)}
    backend passthrough
      server llama-swap ${upstream} ${agent}
  '';
}
