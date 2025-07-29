defmodule ElixirFastCharge.DistributedPreference do
  @moduledoc """
  GenServer distribuido para manejar preferencias de usuarios individuales.
  Se registra en Horde Registry para distribución automática.
  """
  use GenServer
  require Logger

  # API

  def start_link(preference_data) do
    preference_id = generate_preference_id(preference_data)
    GenServer.start_link(__MODULE__, preference_data,
      name: {:via, Horde.Registry, {ElixirFastCharge.HordeRegistry, {:preference, preference_id}}}
    )
  end

  def get_preference(preference_id) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:preference, preference_id}) do
      [{pid, _}] -> GenServer.call(pid, :get_preference)
      [] -> {:error, :not_found}
    end
  end

  def update_preference(preference_id, updates) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:preference, preference_id}) do
      [{pid, _}] -> GenServer.call(pid, {:update_preference, updates})
      [] -> {:error, :not_found}
    end
  end

  def update_alert_status(preference_id, alert_status) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:preference, preference_id}) do
      [{pid, _}] -> GenServer.call(pid, {:update_alert, alert_status})
      [] -> {:error, :not_found}
    end
  end

  def get_preference_info(preference_id) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:preference, preference_id}) do
      [{pid, _}] -> GenServer.call(pid, :get_info)
      [] -> {:error, :not_found}
    end
  end

  def sync_preference(preference_data) do
    GenServer.cast(__MODULE__, {:sync_preference, preference_data})
  end

  # GenServer Callbacks

  @impl true
  def init(preference_data) do
    preference = %{
      preference_id: generate_preference_id(preference_data),
      username: preference_data.username,
      station_id: Map.get(preference_data, :station_id),
      connector_type: Map.get(preference_data, :connector_type),
      power_kw: Map.get(preference_data, :power_kw),
      location: Map.get(preference_data, :location),
      fecha: Map.get(preference_data, :fecha),
      hora_inicio: Map.get(preference_data, :hora_inicio),
      hora_fin: Map.get(preference_data, :hora_fin),
      alert: Map.get(preference_data, :alert, false),
      priority: Map.get(preference_data, :priority, :normal),
      status: Map.get(preference_data, :status, :active),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      current_node: Node.self(),
      created_by_node: Node.self(),
      metadata: Map.get(preference_data, :metadata, %{})
    }

    Logger.info("❤️ Preferencia #{preference.preference_id} para usuario #{preference.username} iniciada en nodo #{Node.self()}")

    {:ok, preference}
  end

  @impl true
  def handle_call(:get_preference, _from, preference) do
    safe_preference = Map.drop(preference, [:metadata])
    {:reply, {:ok, safe_preference}, preference}
  end

  @impl true
  def handle_call({:update_preference, updates}, _from, preference) do
    # Campos permitidos para actualización
    allowed_updates = Map.take(updates, [
      :station_id, :connector_type, :power_kw, :location,
      :fecha, :hora_inicio, :hora_fin, :priority, :status, :metadata
    ])

    updated_preference = preference
    |> Map.merge(allowed_updates)
    |> Map.put(:updated_at, DateTime.utc_now())
    |> Map.put(:current_node, Node.self())

    Logger.info("❤️ Preferencia #{preference.preference_id} actualizada en nodo #{Node.self()}")

    {:reply, {:ok, updated_preference}, updated_preference}
  end

  @impl true
  def handle_call({:update_alert, alert_status}, _from, preference) do
    updated_preference = preference
    |> Map.put(:alert, alert_status)
    |> Map.put(:updated_at, DateTime.utc_now())
    |> Map.put(:current_node, Node.self())

    Logger.info("❤️ Estado de alerta actualizado a #{alert_status} para preferencia #{preference.preference_id}")

    {:reply, {:ok, updated_preference}, updated_preference}
  end

  @impl true
  def handle_call(:get_info, _from, preference) do
    info = %{
      preference_id: preference.preference_id,
      username: preference.username,
      station_id: preference.station_id,
      connector_type: preference.connector_type,
      power_kw: preference.power_kw,
      location: preference.location,
      alert: preference.alert,
      priority: preference.priority,
      status: preference.status,
      created_at: preference.created_at,
      updated_at: preference.updated_at,
      current_node: preference.current_node,
      created_by_node: preference.created_by_node,
      node_info: %{
        pid: self(),
        node: Node.self()
      }
    }

    {:reply, {:ok, info}, preference}
  end

  @impl true
  def handle_cast({:sync_preference, preference_data}, state) do
    Logger.info("Sincronizando preferencia #{preference_data.preference_id} en nodo #{Node.self()}")

    # Lógica para actualizar el estado local con preference_data
    # ...

    # Enviar el estado actualizado a otros nodos
    Node.list()
    |> Enum.each(fn node ->
      Logger.info("Enviando actualización de preferencia a nodo #{node}")
      Node.spawn(node, __MODULE__, :sync_preference, [preference_data])
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, preference) do
    Logger.warning("Preferencia #{preference.preference_id} recibió mensaje inesperado: #{inspect(msg)}")
    {:noreply, preference}
  end

  # Helper Functions

  defp generate_preference_id(preference_data) do
    base = "#{preference_data.username}_#{DateTime.utc_now() |> DateTime.to_unix()}"
    hash = :crypto.hash(:md5, base) |> Base.encode16(case: :lower)
    "pref_#{String.slice(hash, 0, 8)}"
  end
end
