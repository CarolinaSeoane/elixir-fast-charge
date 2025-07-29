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

  def stop_charging_station(station_id) do
    case ElixirFastCharge.ChargingStations.StationRegistry.get_station(station_id) do
      nil -> {:error, :not_found}
      pid -> Horde.DynamicSupervisor.terminate_child(ElixirFastCharge.ChargingStationSupervisor, pid)
    end
  end

  def list_charging_stations do
    ElixirFastCharge.ChargingStations.StationRegistry.list_stations()
    |> Enum.map(fn {station_id, pid} ->
      %{
        id: station_id,
        pid: inspect(pid),
        node: node(pid)
      }
    end)
  end

  def get_station_status(station_id) do
    case ElixirFastCharge.ChargingStations.StationRegistry.get_station(station_id) do
      nil -> {:error, :not_found}
      pid -> ElixirFastCharge.ChargingStations.ChargingStation.get_status(pid)
    end
  end
end
