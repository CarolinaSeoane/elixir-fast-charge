defmodule ElixirFastCharge.Stations.ChargingStation do
  use GenServer

  alias ElixirFastCharge.Stations.StationRegistry

  def start_link(station_id, station_data \\ %{}) do
    GenServer.start_link(__MODULE__, {station_id, station_data}, name: station_id)
  end

  def get_status(station_id) do
    GenServer.call(station_id, :get_status)
  end

  def publish_shift(station_id, shift_data) do
    GenServer.call(station_id, {:publish_shift, shift_data})
  end

  def get_active_shifts(station_id) do
    GenServer.call(station_id, :get_active_shifts)
  end

  @impl true
  def init({station_id, station_data}) do
    IO.puts("Charging Station #{station_id} started")

    # Registrarse en el Registry
    case StationRegistry.register_station(station_id) do
      {:ok, _} ->
        IO.puts("✓ Estación #{station_id} registrada en Registry")
      {:error, reason} ->
        IO.puts("✗ Error registrando #{station_id}: #{inspect(reason)}")
    end

    initial_state = %{
      station_id: station_id,
      available: Map.get(station_data, :available, true),
      active_shifts: []
    }

    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:publish_shift, shift_data}, _from, state) do
    shift = create_shift(state.station_id, shift_data)

    new_state = %{state | active_shifts: [shift | state.active_shifts]}

    # TODO: Alertar a usuarios

    {:reply, {:ok, shift}, new_state}
  end

  @impl true
  def handle_call(:get_active_shifts, _from, state) do
    {:reply, state.active_shifts, state}
  end

  defp create_shift(station_id, shift_data) do
    %{
      shift_id: generate_shift_id(),
      active: true,
      station_id: station_id,
      charging_points: shift_data[:charging_points],
      # todo: implementar turnos
    }
  end

  defp generate_shift_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
