import Config

# ========================================
# CONFIGURACIÓN DE ESCALADO AUTOMÁTICO
# ========================================

# === SCRIPTS DE ESCALADO ===
config :elixir_fast_charge,
  # Scripts custom para escalado
  scale_up_script: System.get_env("SCALE_UP_SCRIPT") || "/opt/scripts/scale_up.sh",
  scale_down_script: System.get_env("SCALE_DOWN_SCRIPT") || "/opt/scripts/scale_down.sh",

  # === ALERTAS Y NOTIFICACIONES ===
  # Slack webhook para alertas
  slack_webhook: System.get_env("SLACK_WEBHOOK_URL"),

  # Email para alertas críticas
  alert_email: System.get_env("ALERT_EMAIL") || "ops@elixirfastcharge.com",

  # === THRESHOLDS DE ESCALADO ===
  scaling_thresholds: %{
    # CPU y memoria
    cpu_scale_up: String.to_float(System.get_env("CPU_SCALE_UP_THRESHOLD") || "80.0"),
    cpu_scale_down: String.to_float(System.get_env("CPU_SCALE_DOWN_THRESHOLD") || "20.0"),
    memory_scale_up: String.to_float(System.get_env("MEMORY_SCALE_UP_THRESHOLD") || "85.0"),
    memory_scale_down: String.to_float(System.get_env("MEMORY_SCALE_DOWN_THRESHOLD") || "40.0"),

    # Aplicación
    pre_reservations_scale_up: String.to_integer(System.get_env("PRERESV_SCALE_UP_THRESHOLD") || "500"),
    pre_reservations_scale_down: String.to_integer(System.get_env("PRERESV_SCALE_DOWN_THRESHOLD") || "50"),

    # Cluster
    min_nodes: String.to_integer(System.get_env("MIN_CLUSTER_NODES") || "1"),
    max_nodes: String.to_integer(System.get_env("MAX_CLUSTER_NODES") || "10")
  },

  # === CONFIGURACIÓN DE KUBERNETES ===
  kubernetes: %{
    enabled: System.get_env("KUBERNETES_ENABLED", "false") == "true",
    deployment_name: System.get_env("K8S_DEPLOYMENT_NAME") || "elixir-fast-charge",
    namespace: System.get_env("K8S_NAMESPACE") || "default",
    min_replicas: String.to_integer(System.get_env("K8S_MIN_REPLICAS") || "1"),
    max_replicas: String.to_integer(System.get_env("K8S_MAX_REPLICAS") || "10")
  },

  # === CONFIGURACIÓN DE DOCKER SWARM ===
  docker_swarm: %{
    enabled: System.get_env("DOCKER_SWARM_ENABLED", "false") == "true",
    service_name: System.get_env("DOCKER_SERVICE_NAME") || "elixir-fast-charge",
    min_replicas: String.to_integer(System.get_env("DOCKER_MIN_REPLICAS") || "1"),
    max_replicas: String.to_integer(System.get_env("DOCKER_MAX_REPLICAS") || "10")
  },

  # === CONFIGURACIÓN DE CLOUD PROVIDERS ===
  aws: %{
    enabled: System.get_env("AWS_SCALING_ENABLED", "false") == "true",
    auto_scaling_group: System.get_env("AWS_ASG_NAME"),
    region: System.get_env("AWS_REGION") || "us-east-1"
  },

  gcp: %{
    enabled: System.get_env("GCP_SCALING_ENABLED", "false") == "true",
    instance_group: System.get_env("GCP_INSTANCE_GROUP"),
    zone: System.get_env("GCP_ZONE") || "us-central1-a"
  },

  # === INTERVALOS DE MONITOREO ===
  monitoring: %{
    metrics_collection_interval: String.to_integer(System.get_env("METRICS_INTERVAL") || "10000"),  # 10 segundos
    scaling_evaluation_interval: String.to_integer(System.get_env("SCALING_INTERVAL") || "30000"),  # 30 segundos
    cooldown_period: String.to_integer(System.get_env("SCALING_COOLDOWN") || "300000")  # 5 minutos
  }

# ========================================
# CONFIGURACIÓN ESPECÍFICA POR ENTORNO
# ========================================

# Importar configuración del entorno actual
cond do
  config_env() == :prod ->
    # === PRODUCCIÓN ===
    config :elixir_fast_charge,
      scaling_thresholds: %{
        cpu_scale_up: 70.0,        # Más agresivo en prod
        memory_scale_up: 80.0,     # Más agresivo en prod
        pre_reservations_scale_up: 300  # Escalar antes en prod
      }

  config_env() == :dev ->
    # === DESARROLLO ===
    config :elixir_fast_charge,
      scaling_thresholds: %{
        cpu_scale_up: 90.0,        # Menos agresivo en dev
        memory_scale_up: 95.0,     # Menos agresivo en dev
        pre_reservations_scale_up: 1000  # Threshold alto para dev
      }

  config_env() == :test ->
    # === TESTING ===
    config :elixir_fast_charge,
      scaling_thresholds: %{
        cpu_scale_up: 99.0,        # Desactivar en tests
        memory_scale_up: 99.0,     # Desactivar en tests
        pre_reservations_scale_up: 10000  # No escalar en tests
      },
      monitoring: %{
        metrics_collection_interval: 1000,   # Más rápido para tests
        scaling_evaluation_interval: 2000    # Más rápido para tests
      }

  true ->
    # Default config
    :ok
end
