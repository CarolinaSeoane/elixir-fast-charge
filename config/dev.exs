import Config

# Configuración para desarrollo con Docker
config :elixir_fast_charge,
  http_port: String.to_integer(System.get_env("HTTP_PORT") || "4002")

# Configuración de libcluster para Docker
config :libcluster,
  topologies: [
    elixir_fast_charge: [
      strategy: Cluster.Strategy.Epmd,
      config: [
        hosts: [
          :"node1@172.18.0.4",
          :"node2@172.18.0.3",
          :"node3@172.18.0.2"
        ]
      ]
    ]
  ]
