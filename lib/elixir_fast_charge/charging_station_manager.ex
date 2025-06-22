defmodule ElixirFastCharge.ChargingStationManager do

  def start_charging_station(station_id) do
    child_spec = %{
      id: station_id,
      start: {ElixirFastCharge.ChargingStation, :start_link, [station_id]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }

    DynamicSupervisor.start_child(ElixirFastCharge.ChargingStationSupervisor, child_spec)
  end

  def stop_charging_station(station_id) do
    DynamicSupervisor.terminate_child(ElixirFastCharge.ChargingStationSupervisor, station_id)
  end

  def list_charging_stations do
    DynamicSupervisor.which_children(ElixirFastCharge.ChargingStationSupervisor)
  end

  def get_station_status(station_id) do
    pid = Process.whereis(station_id)
    ElixirFastCharge.ChargingStation.get_status(pid)
  end
end
