defmodule ElixirFastCharge.Application do

  use Application

    @impl true
  def start(_type, _args) do
    # Obtener puerto de configuración
    port = Application.get_env(:elixir_fast_charge, :http_port, 4002)

    children = [
      # === CLUSTER Y DISTRIBUCIÓN ===
      # Auto-discovery de nodos
      {Cluster.Supervisor, [Application.get_env(:libcluster, :topologies, []), [name: ElixirFastCharge.ClusterSupervisor]]},

      # Registro distribuido de Horde
      ElixirFastCharge.HordeRegistry,

      # Supervisor dinámico distribuido de Horde
      ElixirFastCharge.HordeSupervisor,

      # === SERVICIOS DE APLICACIÓN ===
      {ElixirFastCharge.Finder, []},

      # === MONITOREO Y ESCALADO ===
      {ElixirFastCharge.Monitoring.MetricsCollector, []},

      # Cargador de estaciones (actualizado para usar distribuidos)
      {ElixirFastCharge.ChargingStations.StationLoader, []},

      # === SERVIDOR WEB ===
      {Plug.Cowboy, scheme: :http, plug: ElixirFastCharge.MainRouter, options: [port: port, ref: :http_server]}
    ]

    opts = [strategy: :one_for_one, name: ElixirFastCharge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    IO.puts("Cerrando servidor HTTP en puerto 4002...")
    :cowboy.stop_listener(:http_server)
    :ok
  end
end
