import Config

# Configuración específica para tests
config :logger, level: :warn

# Puerto diferente para tests para evitar conflictos
config :elixir_fast_charge, :http_port, 4003
