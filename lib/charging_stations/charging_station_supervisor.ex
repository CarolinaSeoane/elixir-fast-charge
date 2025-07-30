defmodule ElixirFastCharge.ChargingStationSupervisor do

  def start_charging_station(station_id, station_data \\ %{}) do
    child_spec = %{
      id: station_id,
      start: {ElixirFastCharge.ChargingStations.ChargingStation, :start_link, [station_id, station_data]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }

    Horde.DynamicSupervisor.start_child(ElixirFastCharge.ChargingStationSupervisor, child_spec)
  end

  def list_stations do
    Horde.Registry.select(ElixirFastCharge.ChargingStations.StationRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.into(%{})
  end

  def get_station(station_id) do
    case Horde.Registry.lookup(ElixirFastCharge.ChargingStations.StationRegistry, station_id) do
      [{station_pid, _}] -> {:ok, station_pid}
      [] -> {:error, :not_found}
    end
  end

end
