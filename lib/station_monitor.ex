defmodule ElixirFastCharge.StationMonitor do
  use GenServer
  require Logger

  @check_interval 5_000 # Check every 5 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("StationMonitor started - monitoring charging stations")
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_stations, state) do
    check_and_recreate_missing_stations()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_stations, @check_interval)
  end

  defp check_and_recreate_missing_stations do
    # Get all stations that should exist (from replicated state)
    expected_stations = get_expected_stations()

    # Get currently running stations
    running_stations = ElixirFastCharge.ChargingStationSupervisor.list_stations()

    # Find missing stations
    missing_stations = expected_stations -- Map.keys(running_stations)

    if length(missing_stations) > 0 do
      Enum.each(missing_stations, fn station_id ->
        recreate_station(station_id)
      end)
    else
      Logger.debug("All expected stations are running (#{length(expected_stations)} stations)")
    end
  end

  defp get_expected_stations do
    # Check all nodes for replicated station state
    all_nodes = [Node.self() | Node.list()]

    all_nodes
    |> Enum.flat_map(fn node ->
      try do
        case :rpc.call(node, :ets, :tab2list, [:station_replicas], 5000) do
          replicas when is_list(replicas) ->
            Enum.map(replicas, fn {station_id, _state} -> station_id end)
          _ -> []
        end
      rescue
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp recreate_station(station_id) do
    # Try to get the station's last known state
    recovered_state = try_recover_station_state(station_id)

    if recovered_state do
      # Use the recovered state for station data
      station_data = %{
        available: recovered_state.available,
        location: recovered_state.location,
        charging_points: recovered_state.charging_points
      }

      case ElixirFastCharge.ChargingStationSupervisor.start_charging_station(station_id, station_data) do
        {:ok, pid} ->
          Logger.info("Station #{station_id} recreated successfully: #{inspect(pid)} on #{node(pid)}")

        {:error, {:already_started, pid}} ->
          Logger.info("Station #{station_id} already running: #{inspect(pid)} on #{node(pid)}")

        {:error, reason} ->
          Logger.error("Failed to recreate station #{station_id}: #{inspect(reason)}")
      end
    else
      Logger.warn("No replicated state found for station #{station_id} - cannot recreate")
    end
  end

  defp try_recover_station_state(station_id) do
    # Check all nodes for this station's state
    all_nodes = [Node.self() | Node.list()]

    Enum.find_value(all_nodes, fn node ->
      try do
        case :rpc.call(node, ElixirFastCharge.ChargingStations.ChargingStation, :get_replicated_state, [station_id], 5000) do
          {:ok, state} when is_map(state) ->
            Logger.debug("Found replicated state for station #{station_id} on #{node}")
            state
          _ -> nil
        end
      rescue
        _ -> nil
      end
    end)
  end
end
