import Config

# Configuración específica para producción
config :logger, level: :info

# Puerto desde variable de entorno
config :elixir_fast_charge, :http_port, String.to_integer(System.get_env("PORT") || "4002")
