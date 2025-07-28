import Config

# Configuración de libcluster para auto-discovery de nodos
config :libcluster,
  topologies: [
    elixir_fast_charge: [
      # Estrategia para desarrollo local
      strategy: Cluster.Strategy.Epmd,
      config: [
        hosts: [
          :"node1@127.0.0.1",
          :"node2@127.0.0.1",
          :"node3@127.0.0.1"
        ]
      ]
    ]
    # Para producción podrías usar:
    # strategy: Cluster.Strategy.Kubernetes.DNS,
    # strategy: Cluster.Strategy.Gossip,
    # etc.
  ]

# Configuración específica del entorno
import_config "#{config_env()}.exs"

# Configuración de escalado automático
import_config "scaling.exs"
