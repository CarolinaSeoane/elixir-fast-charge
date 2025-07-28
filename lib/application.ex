defmodule ElixirFastCharge.Application do

  use Application

    @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT") || "5014")
    children = [
        {Registry, keys: :unique, name: ElixirFastCharge.UserRegistry},
        {Registry, keys: :unique, name: ElixirFastCharge.ChargingStations.StationRegistry},
        {ElixirFastCharge.Finder, []},
        {ElixirFastCharge.Storage.ShiftAgent, []},
        {ElixirFastCharge.Storage.PreReservationAgent, []},
        {ElixirFastCharge.UserDynamicSupervisor, []},
        {DynamicSupervisor, strategy: :one_for_one, name: ElixirFastCharge.ChargingStationSupervisor},
        {ElixirFastCharge.ChargingStations.StationLoader, []},
        {Plug.Cowboy, scheme: :http, plug: ElixirFastCharge.MainRouter, options: [port: port, ref: :http_server]}
      ]

    opts = [strategy: :one_for_one, name: ElixirFastCharge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    :cowboy.stop_listener(:http_server)
    :ok
  end
end
