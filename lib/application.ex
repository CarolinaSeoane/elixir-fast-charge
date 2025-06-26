defmodule ElixirFastCharge.Application do

  use Application

    @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: ElixirFastCharge.UserRegistry},
      {Registry, keys: :unique, name: ElixirFastCharge.StationRegistry},
      {ElixirFastCharge.Finder, []},
      {ElixirFastCharge.UserDynamicSupervisor, []},
      {DynamicSupervisor, strategy: :one_for_one, name: ElixirFastCharge.ChargingStationSupervisor},
      {ElixirFastCharge.ChargingStations.StationLoader, []},
      # HTTP server
      {Plug.Cowboy, scheme: :http, plug: ElixirFastCharge.UserRouter, options: [port: 4000]}
    ]

    opts = [strategy: :one_for_one, name: ElixirFastCharge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
