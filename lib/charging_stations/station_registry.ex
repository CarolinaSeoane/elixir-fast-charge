defmodule ElixirFastCharge.ChargingStations.StationRegistry do

  def register_station(station_id, pid) do
    Horde.Registry.register(ElixirFastCharge.ChargingStations.StationRegistry, station_id, pid)
  end

  def register_station(station_id) do
    Horde.Registry.register(ElixirFastCharge.ChargingStations.StationRegistry, station_id, self())
  end

  def unregister_station(station_id) do
    Horde.Registry.unregister(ElixirFastCharge.ChargingStations.StationRegistry, station_id)
  end

  def get_station(station_id) do
    case Horde.Registry.lookup(ElixirFastCharge.ChargingStations.StationRegistry, station_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def list_stations do
    Horde.Registry.select(ElixirFastCharge.ChargingStations.StationRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.into(%{})
  end

  def count_stations do
    Horde.Registry.select(ElixirFastCharge.ChargingStations.StationRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
    |> length()
  end
end
