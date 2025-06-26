defmodule ElixirFastCharge.ChargingStationSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

    @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_charging_station(station_id, station_data \\ %{}) do
    child_spec = %{
      id: station_id,
      start: {ElixirFastCharge.ChargingStations.ChargingStation, :start_link, [station_id, station_data]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def stop_charging_station(station_id) do
    DynamicSupervisor.terminate_child(__MODULE__, station_id)
  end

  def list_charging_stations do
    Registry.select(ElixirFastCharge.StationRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3"}}]}])
    |> Enum.map(fn {station_id, pid} ->
      %{
        id: station_id,
        pid: inspect(pid)
      }
    end)
  end

  def get_station_status(station_id) do
    pid = Process.whereis(station_id)
    ElixirFastCharge.ChargingStations.ChargingStation.get_status(pid)
  end

end
