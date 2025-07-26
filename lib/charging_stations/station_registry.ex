defmodule ElixirFastCharge.ChargingStations.StationRegistry do
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(_) do
    Registry.start_link(keys: :unique, name: __MODULE__)
  end

  def register_station(station_id, pid) do
    Registry.register(__MODULE__, station_id, pid)
  end

  def register_station(station_id) do
    Registry.register(__MODULE__, station_id, self())
  end

  def unregister_station(station_id) do
    Registry.unregister(__MODULE__, station_id)
  end

  def get_station(station_id) do
    case Registry.lookup(__MODULE__, station_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def list_stations do
    Registry.select(__MODULE__, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.into(%{})
  end

  def count_stations do
    Registry.count(__MODULE__)
  end
end
