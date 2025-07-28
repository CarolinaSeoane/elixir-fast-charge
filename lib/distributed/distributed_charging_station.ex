defmodule ElixirFastCharge.DistributedChargingStation do
  @moduledoc """
  GenServer distribuido para manejar estaciones de carga individuales.
  Se registra en Horde Registry para distribución automática.
  """
  use GenServer
  require Logger

  # API

  def start_link(station_data) do
    GenServer.start_link(__MODULE__, station_data,
      name: {:via, Horde.Registry, {ElixirFastCharge.HordeRegistry, {:charging_station, station_data.station_id}}}
    )
  end

  def get_station(station_id) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:charging_station, station_id}) do
      [{pid, _}] -> GenServer.call(pid, :get_station)
      [] -> {:error, :not_found}
    end
  end

  def get_charging_points(station_id) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:charging_station, station_id}) do
      [{pid, _}] -> GenServer.call(pid, :get_charging_points)
      [] -> {:error, :not_found}
    end
  end

  def get_available_points(station_id) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:charging_station, station_id}) do
      [{pid, _}] -> GenServer.call(pid, :get_available_points)
      [] -> {:error, :not_found}
    end
  end

  def update_station(station_id, updates) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:charging_station, station_id}) do
      [{pid, _}] -> GenServer.call(pid, {:update_station, updates})
      [] -> {:error, :not_found}
    end
  end

  def add_charging_point(station_id, point_data) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:charging_station, station_id}) do
      [{pid, _}] -> GenServer.call(pid, {:add_charging_point, point_data})
      [] -> {:error, :not_found}
    end
  end

  def update_point_status(station_id, point_id, status) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:charging_station, station_id}) do
      [{pid, _}] -> GenServer.call(pid, {:update_point_status, point_id, status})
      [] -> {:error, :not_found}
    end
  end

  def get_station_info(station_id) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:charging_station, station_id}) do
      [{pid, _}] -> GenServer.call(pid, :get_info)
      [] -> {:error, :not_found}
    end
  end

  # GenServer Callbacks

  @impl true
  def init(station_data) do
    station = %{
      station_id: station_data.station_id,
      name: station_data.name,
      location: station_data.location,
      status: Map.get(station_data, :status, :active),
      charging_points: process_charging_points(Map.get(station_data, :charging_points, [])),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      current_node: Node.self(),
      created_by_node: Node.self(),
      metadata: Map.get(station_data, :metadata, %{})
    }

    Logger.info("Estación #{station.station_id} iniciada en nodo #{Node.self()}")

    {:ok, station}
  end

  @impl true
  def handle_call(:get_station, _from, station) do
    safe_station = Map.drop(station, [:metadata])
    {:reply, {:ok, safe_station}, station}
  end

  @impl true
  def handle_call(:get_charging_points, _from, station) do
    {:reply, {:ok, station.charging_points}, station}
  end

  @impl true
  def handle_call(:get_available_points, _from, station) do
    available_points = station.charging_points
    |> Enum.filter(fn point -> point.status == :available end)

    {:reply, {:ok, available_points}, station}
  end

  @impl true
  def handle_call({:update_station, updates}, _from, station) do
    allowed_updates = Map.take(updates, [:name, :location, :status, :metadata])
    updated_station = station
    |> Map.merge(allowed_updates)
    |> Map.put(:updated_at, DateTime.utc_now())
    |> Map.put(:current_node, Node.self())

    Logger.info("Estación #{station.station_id} actualizada en nodo #{Node.self()}")

    {:reply, {:ok, updated_station}, updated_station}
  end

  @impl true
  def handle_call({:add_charging_point, point_data}, _from, station) do
    new_point = %{
      point_id: point_data.point_id,
      connector_type: point_data.connector_type,
      power_kw: point_data.power_kw,
      status: Map.get(point_data, :status, :available),
      created_at: DateTime.utc_now()
    }

    updated_points = [new_point | station.charging_points]
    updated_station = station
    |> Map.put(:charging_points, updated_points)
    |> Map.put(:updated_at, DateTime.utc_now())
    |> Map.put(:current_node, Node.self())

          Logger.info("Punto de carga #{new_point.point_id} agregado a estación #{station.station_id}")

    {:reply, {:ok, new_point}, updated_station}
  end

  @impl true
  def handle_call({:update_point_status, point_id, status}, _from, station) do
    updated_points = station.charging_points
    |> Enum.map(fn point ->
      if point.point_id == point_id do
        Map.put(point, :status, status)
      else
        point
      end
    end)

    updated_station = station
    |> Map.put(:charging_points, updated_points)
    |> Map.put(:updated_at, DateTime.utc_now())
    |> Map.put(:current_node, Node.self())

            Logger.info("Estado del punto #{point_id} actualizado a #{status} en estación #{station.station_id}")

    {:reply, {:ok, :updated}, updated_station}
  end

  @impl true
  def handle_call(:get_info, _from, station) do
    info = %{
      station_id: station.station_id,
      name: station.name,
      location: station.location,
      status: station.status,
      total_points: length(station.charging_points),
      available_points: Enum.count(station.charging_points, fn p -> p.status == :available end),
      created_at: station.created_at,
      updated_at: station.updated_at,
      current_node: station.current_node,
      created_by_node: station.created_by_node,
      node_info: %{
        pid: self(),
        node: Node.self()
      }
    }

    {:reply, {:ok, info}, station}
  end

  @impl true
  def handle_info(msg, station) do
    Logger.warning("Estación #{station.station_id} recibió mensaje inesperado: #{inspect(msg)}")
    {:noreply, station}
  end

  # Helper Functions

  defp process_charging_points(points) when is_list(points) do
    points
    |> Enum.map(fn point ->
      %{
        point_id: point["point_id"] || point[:point_id],
        connector_type: normalize_atom(point["connector_type"] || point[:connector_type] || "ccs"),
        power_kw: point["power_kw"] || point[:power_kw] || 150,
        status: normalize_atom(point["status"] || point[:status] || "available"),
        created_at: DateTime.utc_now()
      }
    end)
  end

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_atom(value)
  defp normalize_atom(_), do: :unknown

  defp process_charging_points(_), do: []
end
