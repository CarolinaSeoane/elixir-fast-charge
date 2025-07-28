defmodule ElixirFastCharge.DistributedChargingStationManager do
  @moduledoc """
  Manager para operaciones distribuidas con estaciones de carga.
  Interfaz principal para interactuar con estaciones distribuidas en el cluster.
  """
  require Logger

  # API PRINCIPAL

  def create_station(station_data) do
    # Verificar si la estación ya existe en el cluster
    case get_station(station_data.station_id) do
      {:ok, _existing_station} ->
        {:error, :station_already_exists}

      {:error, :not_found} ->
        # Estación no existe, crear nueva
        case ElixirFastCharge.HordeSupervisor.start_child({ElixirFastCharge.DistributedChargingStation, station_data}) do
          {:ok, pid} ->
            Logger.info("Estación #{station_data.station_id} creada exitosamente en cluster")
            {:ok, pid}

          {:error, reason} ->
            Logger.error("Error creando estación #{station_data.station_id}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  def get_station(station_id) do
    ElixirFastCharge.DistributedChargingStation.get_station(station_id)
  end

  def get_charging_points(station_id) do
    ElixirFastCharge.DistributedChargingStation.get_charging_points(station_id)
  end

  def get_available_points(station_id) do
    ElixirFastCharge.DistributedChargingStation.get_available_points(station_id)
  end

  def update_station(station_id, updates) do
    ElixirFastCharge.DistributedChargingStation.update_station(station_id, updates)
  end

  def add_charging_point(station_id, point_data) do
    ElixirFastCharge.DistributedChargingStation.add_charging_point(station_id, point_data)
  end

  def update_point_status(station_id, point_id, status) do
    ElixirFastCharge.DistributedChargingStation.update_point_status(station_id, point_id, status)
  end

  def list_all_stations() do
    case ElixirFastCharge.HordeRegistry.list_all() do
      processes when is_list(processes) ->
        processes
        |> Enum.filter(fn {{type, _id}, _pid, _value} -> type == :charging_station end)
        |> Enum.map(fn {{:charging_station, station_id}, pid, _value} ->
          case ElixirFastCharge.DistributedChargingStation.get_station(station_id) do
            {:ok, station} -> station
            {:error, _} ->
              %{station_id: station_id, status: :error, pid: inspect(pid)}
          end
        end)
        |> Enum.reject(fn station -> station.status == :error end)

      _ -> []
    end
  end

  def list_active_stations() do
    list_all_stations()
    |> Enum.filter(fn station -> station.status == :active end)
  end

  def count_stations() do
    case ElixirFastCharge.HordeRegistry.list_all() do
      processes when is_list(processes) ->
        station_count = processes
        |> Enum.count(fn {{type, _id}, _pid, _value} -> type == :charging_station end)

        %{
          total_stations: station_count,
          node: Node.self(),
          cluster_nodes: [Node.self() | Node.list()]
        }

      _ ->
        %{
          total_stations: 0,
          node: Node.self(),
          cluster_nodes: [Node.self() | Node.list()]
        }
    end
  end

  def get_station_info(station_id) do
    ElixirFastCharge.DistributedChargingStation.get_station_info(station_id)
  end

  def list_stations_by_node() do
    case ElixirFastCharge.HordeRegistry.list_all() do
      processes when is_list(processes) ->
        station_processes = processes
        |> Enum.filter(fn {{type, _id}, _pid, _value} -> type == :charging_station end)

        station_processes
        |> Enum.group_by(fn {{:charging_station, _station_id}, pid, _value} -> node(pid) end)
        |> Enum.map(fn {node, station_list} ->
          {Atom.to_string(node), length(station_list)}
        end)
        |> Map.new()

      _ -> %{}
    end
  end

  def get_cluster_stats() do
    all_nodes = [Node.self() | Node.list()]
    station_count = count_stations()
    station_distribution = list_stations_by_node()

    # Estadísticas adicionales
    all_stations = list_all_stations()
    total_points = all_stations
    |> Enum.map(fn station -> length(Map.get(station, :charging_points, [])) end)
    |> Enum.sum()

    available_points = all_stations
    |> Enum.flat_map(fn station -> Map.get(station, :charging_points, []) end)
    |> Enum.count(fn point -> point.status == :available end)

    %{
      node: Atom.to_string(Node.self()),
      cluster_nodes: Enum.map(all_nodes, &Atom.to_string/1),
      total_stations: station_count.total_stations,
      active_stations: Enum.count(all_stations, fn s -> s.status == :active end),
      total_charging_points: total_points,
      available_charging_points: available_points,
      station_distribution: station_distribution,
      distributed: true
    }
  end

  # FUNCIONES DE UTILIDAD

  def station_exists?(station_id) do
    case get_station(station_id) do
      {:ok, _station} -> true
      {:error, :not_found} -> false
    end
  end

  def delete_station(station_id) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:charging_station, station_id}) do
      [{pid, _}] ->
        case ElixirFastCharge.HordeSupervisor.terminate_child(pid) do
          :ok ->
            Logger.info("Estación #{station_id} eliminada del cluster")
            {:ok, :deleted}

          {:error, reason} ->
            Logger.error("Error eliminando estación #{station_id}: #{inspect(reason)}")
            {:error, reason}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def get_stations_by_status(status) do
    list_all_stations()
    |> Enum.filter(fn station -> station.status == status end)
  end

  def get_stations_by_connector_type(connector_type) do
    list_all_stations()
    |> Enum.filter(fn station ->
      station.charging_points
      |> Enum.any?(fn point -> point.connector_type == connector_type end)
    end)
  end

  def get_stations_by_location(location_filter) do
    list_all_stations()
    |> Enum.filter(fn station ->
      address = get_in(station, [:location, :address]) || ""
      String.contains?(String.downcase(address), String.downcase(location_filter))
    end)
  end

  # FUNCIONES DE CARGA MASIVA

  def load_stations_from_data(stations_data) when is_list(stations_data) do
    results = stations_data
    |> Enum.map(fn station_data ->
      case create_station(station_data) do
        {:ok, pid} -> {:ok, station_data.station_id, pid}
        {:error, reason} -> {:error, station_data.station_id, reason}
      end
    end)

    successful = Enum.count(results, fn {status, _, _} -> status == :ok end)
    failed = Enum.count(results, fn {status, _, _} -> status == :error end)

    Logger.info("Carga masiva completada: #{successful} exitosas, #{failed} fallidas")

    %{
      total: length(stations_data),
      successful: successful,
      failed: failed,
      results: results
    }
  end

  # FUNCIONES DE DIAGNÓSTICO

  def cluster_health() do
    all_nodes = [Node.self() | Node.list()]
    station_stats = get_cluster_stats()

    %{
      cluster_status: if(length(all_nodes) > 1, do: "clustered", else: "standalone"),
      total_nodes: length(all_nodes),
      connected_nodes: Enum.map(Node.list(), &Atom.to_string/1),
      current_node: Atom.to_string(Node.self()),
      station_stats: station_stats,
      timestamp: DateTime.utc_now()
    }
  end

  # OPERACIONES DE MANTENIMIENTO

  def sync_station_data(station_id) do
    case get_station(station_id) do
      {:ok, station} ->
        # Re-registrar la estación si es necesario
        Logger.info("Sincronizando datos de estación #{station_id}")
        {:ok, station}

      {:error, reason} ->
        Logger.warning("No se pudo sincronizar estación #{station_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def health_check_all_stations() do
    all_stations = list_all_stations()

    health_results = all_stations
    |> Enum.map(fn station ->
      case get_station_info(station.station_id) do
        {:ok, info} -> %{station_id: station.station_id, status: :healthy, info: info}
        {:error, reason} -> %{station_id: station.station_id, status: :unhealthy, reason: reason}
      end
    end)

    healthy_count = Enum.count(health_results, fn result -> result.status == :healthy end)
    unhealthy_count = length(health_results) - healthy_count

    %{
      total_stations: length(health_results),
      healthy_stations: healthy_count,
      unhealthy_stations: unhealthy_count,
      health_percentage: if(length(health_results) > 0, do: (healthy_count / length(health_results)) * 100, else: 0),
      results: health_results,
      timestamp: DateTime.utc_now()
    }
  end
end
