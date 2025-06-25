defmodule ElixirFastCharge.Application do

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {ElixirFastCharge.Stations.StationRegistry, []},
      {ElixirFastCharge.Finder, []},
      {ElixirFastCharge.Stations.ChargingStationManager, []}
    ]

    opts = [strategy: :one_for_one, name: ElixirFastCharge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
