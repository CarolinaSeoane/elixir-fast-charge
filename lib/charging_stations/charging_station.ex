defmodule ElixirFastCharge.ChargingStations.ChargingStation do
  use GenServer

  def start_link(station_id, station_data \\ %{}) do
    GenServer.start_link(__MODULE__, {station_id, station_data})
  end

  def get_status(station_id) do
    GenServer.call(station_id, :get_status)
  end

  def get_active_shifts(station_id) do
    GenServer.call(station_id, :get_active_shifts)
  end

  def get_charging_points(station_id) do
    GenServer.call(station_id, :get_charging_points)
  end

  def get_location(station_id) do
    GenServer.call(station_id, :get_location)
  end

  def get_available_points(station_id) do
    GenServer.call(station_id, :get_available_points)
  end

  def update_point_status(station_id, point_id, new_status) do
    GenServer.call(station_id, {:update_point_status, point_id, new_status})
  end

  def publish_shifts(station_id, shift_params) do
    GenServer.call(station_id, {:publish_shifts, shift_params})
  end

  def publish_shift_for_point(station_id, point_id, shift_params) do
    GenServer.call(station_id, {:publish_shift_for_point, point_id, shift_params})
  end

  @impl true
  def init({station_id, station_data}) do
    case Horde.Registry.register(ElixirFastCharge.ChargingStations.StationRegistry, station_id, self()) do
      {:ok, _} ->
        IO.puts("Estación #{station_id} registrada en Horde Registry (nodo: #{node()})")

        # Try to recover state from other nodes
        recovered_state = try_recover_state(station_id)

        final_state = case recovered_state do
          nil ->
            IO.puts("🆕 Station #{station_id}: Starting with new state")
            %{
              station_id: station_id,
              available: Map.get(station_data, :available, true),
              location: Map.get(station_data, :location, %{}),
              charging_points: Map.get(station_data, :charging_points, [])
            }
          state ->
            IO.puts("🔄 Station #{station_id}: Recovered state with #{length(state.charging_points)} points")
            state
        end

        # Replicate initial state to other nodes
        replicate_state(final_state)

        {:ok, final_state}

      {:error, {:already_registered, _}} ->
        {:stop, :station_already_exists}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_active_shifts, _from, state) do
    shifts = ElixirFastCharge.Storage.ShiftAgent.list_shifts_by_station(state.station_id)
    {:reply, shifts, state}
  end

  @impl true
  def handle_call(:get_charging_points, _from, state) do
    {:reply, state.charging_points, state}
  end

  @impl true
  def handle_call(:get_location, _from, state) do
    {:reply, state.location, state}
  end

  @impl true
  def handle_call(:get_available_points, _from, state) do
    available_points = Enum.filter(state.charging_points, fn point ->
      point.status == :available
    end)
    {:reply, available_points, state}
  end

  @impl true
  def handle_call({:update_point_status, point_id, new_status}, _from, state) do
    updated_points = Enum.map(state.charging_points, fn point ->
      if point.point_id == point_id do
        %{point | status: new_status}
      else
        point
      end
    end)

    new_state = %{state | charging_points: updated_points}

    # Replicate state after change
    replicate_state(new_state)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:publish_shifts, shift_params}, _from, state) do
    available_points = Enum.filter(state.charging_points, fn point ->
      point.status == :available
    end)

    created_shifts = Enum.map(available_points, fn point ->
      shift_data = %{
        station_id: state.station_id,
        point_id: point.point_id,
        connector_type: point.connector_type,
        power_kw: point.power_kw,
        start_time: shift_params.start_time,
        end_time: shift_params.end_time,
        expires_at: shift_params.expires_at,
        location: state.location
      }

      case ElixirFastCharge.Storage.ShiftAgent.create_shift(shift_data) do
        {:ok, shift} ->
          # send alerts
          ElixirFastCharge.Finder.send_alerts(shift)
          shift
      end
    end)
    |> Enum.filter(& &1)

    {:reply, {:ok, created_shifts}, state}
  end

  @impl true
  def handle_call({:publish_shift_for_point, point_id, shift_params}, _from, state) do
    point = Enum.find(state.charging_points, fn point -> point.point_id == point_id end)

    if point do
      shift_data = %{
        station_id: state.station_id,
        point_id: point.point_id,
        connector_type: point.connector_type,
        power_kw: point.power_kw,
        start_time: shift_params.start_time,
        end_time: shift_params.end_time,
        expires_at: shift_params.expires_at,
        location: state.location
      }

      case ElixirFastCharge.Storage.ShiftAgent.create_shift(shift_data) do
        {:ok, shift} ->
          # send alerts
          ElixirFastCharge.Finder.send_alerts(shift)
          {:reply, {:ok, shift}, state}
      end
    else
      IO.puts("Punto de carga #{point_id} no encontrado")
      {:reply, {:error, "Punto de carga no encontrado"}, state}
    end
  end

  # === STATE REPLICATION AND RECOVERY ===

  defp try_recover_state(station_id) do
    # Check all connected nodes for replicated state
    all_nodes = [Node.self() | Node.list()]

    recovered_state = Enum.find_value(all_nodes, fn node ->
      try do
        case :rpc.call(node, __MODULE__, :get_replicated_state, [station_id], 5000) do
          {:ok, state} when is_map(state) ->
            IO.puts("✅ Station #{station_id}: Found replicated state on #{node}")
            state
          _ -> nil
        end
      rescue
        _ -> nil
      end
    end)

    # If no remote state found, check locally
    if recovered_state do
      recovered_state
    else
      case :ets.lookup(:station_replicas, station_id) do
        [{^station_id, state}] ->
          IO.puts("✅ Station #{station_id}: Found state locally!")
          state
        [] ->
          IO.puts("😞 Station #{station_id}: No replicated state found")
          nil
      end
    end
  end

  defp replicate_state(state) do
    station_id = state.station_id

    # Replicate to all other connected nodes asynchronously
    all_nodes = [Node.self() | Node.list()]

    Enum.each(all_nodes, fn node ->
      Task.start(fn ->
        try do
          :rpc.call(node, __MODULE__, :store_replicated_state, [station_id, state], 2000)
        rescue
          _ -> :ok
        end
      end)
    end)
  end

  # === PUBLIC FUNCTIONS FOR RPC ACCESS ===

  def get_replicated_state(station_id) do
    case :ets.lookup(:station_replicas, station_id) do
      [{^station_id, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end

  def store_replicated_state(station_id, state) do
    :ets.insert(:station_replicas, {station_id, state})
    :ok
  end

  # === DEBUG FUNCTIONS ===

  def show_all_replicas do
    all_nodes = [Node.self() | Node.list()]

    IO.puts("\n🔍 === STATION REPLICAS ACROSS CLUSTER ===")

    Enum.each(all_nodes, fn node ->
      try do
        replicas = :rpc.call(node, :ets, :tab2list, [:station_replicas], 5000)
        IO.puts("📍 Node #{node}:")

        case replicas do
          stations when is_list(stations) and length(stations) > 0 ->
            Enum.each(stations, fn {station_id, state} ->
              point_count = length(state.charging_points || [])
              IO.puts("  🏭 #{station_id}: #{point_count} points, available: #{state.available}")
            end)
          _ ->
            IO.puts("  (no station replicas)")
        end
      rescue
        _ -> IO.puts("📍 Node #{node}: (no response)")
      end
    end)

    IO.puts("")
  end

end
