defmodule ElixirFastCharge.Application do

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {ElixirFastCharge.ChargingStations.StationRegistry, []},
      {ElixirFastCharge.Finder, []},
      {ElixirFastCharge.ChargingStations.ChargingStationManager, []}
    ]

    opts = [strategy: :one_for_one, name: ElixirFastCharge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
