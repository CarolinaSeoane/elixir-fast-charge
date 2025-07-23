defmodule ElixirFastCharge.Finder do
  use GenServer

  # Using the standard Registry instead of custom StationRegistry

  def start_link(default) do
    GenServer.start_link(__MODULE__, default, name: __MODULE__)
  end

  @impl true
  def init(initial_state) do
    IO.puts("Finder started")
    {:ok, initial_state}
  end

  def healthcheck do
    GenServer.call(__MODULE__, {:healthcheck})
  end

  def find_station(station_id) do
    GenServer.call(__MODULE__, {:find_station, station_id})
  end

  def list_all_stations do
    GenServer.call(__MODULE__, {:list_all_stations})
  end

  def count_registered_stations do
    GenServer.call(__MODULE__, {:count_registered_stations})
  end

  def register_station(station_id, pid) do
    GenServer.call(__MODULE__, {:register_station, station_id, pid})
  end

  @impl true
  def handle_call({:healthcheck}, _from, state) do
    {:reply, "Finder running", state}
  end

  @impl true
  def handle_call({:find_station, station_id}, _from, state) do
    result = case Registry.lookup(ElixirFastCharge.StationRegistry, station_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
    {:reply, result, state}
  end

  @impl true
  def handle_call({:list_all_stations}, _from, state) do
    stations = Registry.select(ElixirFastCharge.StationRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    {:reply, stations, state}
  end

  @impl true
  def handle_call({:count_registered_stations}, _from, state) do
    count = Registry.count(ElixirFastCharge.StationRegistry)
    {:reply, count, state}
  end

  @impl true
  def handle_call({:register_station, station_id, pid}, _from, state) do
    result = Registry.register(ElixirFastCharge.StationRegistry, station_id, pid)
    {:reply, result, state}
  end
end
