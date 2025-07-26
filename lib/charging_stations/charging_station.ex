defmodule ElixirFastCharge.ChargingStations.ChargingStation do
  use GenServer

  def start_link(station_id, station_data \\ %{}) do
    GenServer.start_link(__MODULE__, {station_id, station_data}, name: station_id)
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
    IO.puts("Charging Station #{station_id} started")

    # Registrarse en el Registry estándar
    case Registry.register(ElixirFastCharge.ChargingStations.StationRegistry, station_id, self()) do
      {:ok, _} ->
        IO.puts("✓ Estación #{station_id} registrada en Registry")
      {:error, reason} ->
        IO.puts("✗ Error registrando #{station_id}: #{inspect(reason)}")
    end

    initial_state = %{
      station_id: station_id,
      available: Map.get(station_data, :available, true),
      location: Map.get(station_data, :location, %{}),
      charging_points: Map.get(station_data, :charging_points, [])
    }

    {:ok, initial_state}
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
        {:ok, shift} -> shift
        {:error, reason} ->
          IO.puts("Error creando turno para #{point.point_id}: #{inspect(reason)}")
          nil
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
          {:reply, {:ok, shift}, state}
        {:error, reason} ->
          IO.puts("Error creando turno para #{point.point_id}: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    else
      IO.puts("Punto de carga #{point_id} no encontrado")
      {:reply, {:error, "Punto de carga no encontrado"}, state}
    end
  end

end
