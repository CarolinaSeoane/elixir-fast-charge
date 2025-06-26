defmodule ElixirFastCharge.ChargingStations.ChargingStationManager do
  use DynamicSupervisor

  alias ElixirFastCharge.ChargingStations.StationRegistry

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Task.start(fn ->
      wait_for_registry()
      load_default_stations()
    end)

    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp wait_for_registry do
    case Process.whereis(ElixirFastCharge.ChargingStations.StationRegistry) do
      nil ->
        Process.sleep(100)
        wait_for_registry()
      _pid ->
        IO.puts("Registry is ready, loading stations...")
        :ok
    end
  end

  def load_default_stations do
    case read_default_stations_config() do
      {:ok, stations} ->
        Enum.each(stations, fn station ->
          station_id = String.to_atom(station["station_id"])
          station_data = %{
            available: station["available"]
          }
          case start_charging_station(station_id, station_data) do
            {:ok, _pid} ->
              IO.puts("✓ Estación #{station["station_id"]} cargada (disponible: #{station["available"]})")
            {:error, {:already_started, _pid}} ->
              IO.puts("⚠ Estación #{station["station_id"]} ya estaba iniciada")
            {:error, reason} ->
              IO.puts("✗ Error cargando estación #{station["station_id"]}: #{inspect(reason)}")
          end
        end)
        {:ok, length(stations)}
      {:error, reason} ->
        IO.puts("Error cargando estaciones por defecto: #{inspect(reason)}")
        {:error, reason}
    end
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
    StationRegistry.unregister_station(station_id)
    DynamicSupervisor.terminate_child(__MODULE__, station_id)
  end

  def list_charging_stations do
    DynamicSupervisor.which_children(__MODULE__)
  end

  def get_station_status(station_id) do
    pid = Process.whereis(station_id)
    ElixirFastCharge.ChargingStations.ChargingStation.get_status(pid)
  end

  defp read_default_stations_config do
    config_path = Path.join([
      :code.priv_dir(:elixir_fast_charge),
      "..",
      "lib",
      "charging_stations",
      "default_stations.json"
    ])

    fallback_path = Path.join([
      File.cwd!(),
      "lib",
      "charging_stations",
      "default_stations.json"
    ])

    config_file = if File.exists?(config_path), do: config_path, else: fallback_path

    case File.read(config_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"stations" => stations}} -> {:ok, stations}
          {:ok, _} -> {:error, "Formato JSON inválido: debe contener 'stations'"}
          {:error, reason} -> {:error, "Error decodificando JSON: #{inspect(reason)}"}
        end
      {:error, reason} ->
        {:error, "Error leyendo archivo: #{inspect(reason)}"}
    end
  end
end
