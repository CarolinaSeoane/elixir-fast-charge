defmodule ElixirFastCharge.Application do

  use Application

    @impl true
  def start(_type, _args) do
          children = [
        {Registry, keys: :unique, name: ElixirFastCharge.UserRegistry},
        {Registry, keys: :unique, name: ElixirFastCharge.StationRegistry},
        {ElixirFastCharge.Finder, []},
        {ElixirFastCharge.Storage.ShiftAgent, []},
        {ElixirFastCharge.Storage.PreReservationAgent, []},
        {ElixirFastCharge.UserDynamicSupervisor, []},
        {DynamicSupervisor, strategy: :one_for_one, name: ElixirFastCharge.ChargingStationSupervisor},
        {ElixirFastCharge.ChargingStations.StationLoader, []},
        {Plug.Cowboy, scheme: :http, plug: ElixirFastCharge.MainRouter, options: [port: 4003, ref: :http_server]}
      ]

    opts = [strategy: :one_for_one, name: ElixirFastCharge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    IO.puts("🛑 Cerrando servidor HTTP en puerto 4003...")
    :cowboy.stop_listener(:http_server)
    :ok
  end
end
