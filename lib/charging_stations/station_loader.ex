defmodule ElixirFastCharge.ChargingStations.StationLoader do
  use GenServer

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    IO.puts("StationLoader iniciado - cargando estaciones por defecto...")
    # Cargar estaciones después de que todo esté listo
    Process.send_after(self(), :load_stations, 100)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:load_stations, state) do
    load_default_stations()
    {:noreply, state}
  end

  defp load_default_stations do
    case read_default_stations_config() do
      {:ok, stations} ->
        Enum.each(stations, fn station ->
          station_id = String.to_atom(station["station_id"])
          station_data = %{
            available: station["available"]
          }
          case ElixirFastCharge.ChargingStationSupervisor.start_charging_station(station_id, station_data) do
            {:ok, _pid} ->
              IO.puts("✓ Estación #{station["station_id"]} cargada (disponible: #{station["available"]})")
            {:error, {:already_started, _pid}} ->
              IO.puts("⚠ Estación #{station["station_id"]} ya estaba iniciada")
            {:error, reason} ->
              IO.puts("✗ Error cargando estación #{station["station_id"]}: #{inspect(reason)}")
          end
        end)
        IO.puts("✓ Carga de estaciones completada: #{length(stations)} estaciones")
        {:ok, length(stations)}
      {:error, reason} ->
        IO.puts("✗ Error cargando estaciones por defecto: #{inspect(reason)}")
        {:error, reason}
    end
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
