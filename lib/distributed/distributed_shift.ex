defmodule ElixirFastCharge.DistributedShift do
  @moduledoc """
  GenServer distribuido para manejar un turno individual.
  Cada turno es un proceso independiente que puede migrar entre nodos.
  """
  use GenServer
  require Logger

  # Client API

  def start_link(shift_data) do
    shift_id = shift_data.shift_id
    GenServer.start_link(
      __MODULE__,
      shift_data,
      name: {:via, Horde.Registry, {ElixirFastCharge.HordeRegistry, {:shift, shift_id}}}
    )
  end

  def get_shift(shift_id) do
    case ElixirFastCharge.HordeRegistry.lookup({:shift, shift_id}) do
      {:ok, pid} ->
        shift = GenServer.call(pid, :get_shift)
        {:ok, shift}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def reserve_shift(shift_id, user_id) do
    case ElixirFastCharge.HordeRegistry.lookup({:shift, shift_id}) do
      {:ok, pid} -> GenServer.call(pid, {:reserve, user_id})
      {:error, :not_found} -> {:error, :shift_not_found}
    end
  end

  def update_status(shift_id, status) do
    case ElixirFastCharge.HordeRegistry.lookup({:shift, shift_id}) do
      {:ok, pid} -> GenServer.call(pid, {:update_status, status})
      {:error, :not_found} -> {:error, :shift_not_found}
    end
  end

  def get_info(shift_id) do
    case ElixirFastCharge.HordeRegistry.lookup({:shift, shift_id}) do
      {:ok, pid} -> GenServer.call(pid, :get_info)
      {:error, :not_found} -> {:error, :shift_not_found}
    end
  end

  def sync_shift(shift_data) do
    GenServer.cast(__MODULE__, {:sync_shift, shift_data})
  end

  # Server callbacks

  @impl true
  def init(shift_data) do
    shift = %{
      shift_id: shift_data.shift_id,
      station_id: shift_data.station_id,
      point_id: shift_data.point_id,
      connector_type: shift_data.connector_type,
      power_kw: shift_data.power_kw,
      location: shift_data.location,
      start_time: shift_data.start_time,
      end_time: shift_data.end_time,
      published_at: DateTime.utc_now(),
      expires_at: shift_data.expires_at,
      status: :active,
      active: true,
      reserved_by: nil,
      reserved_at: nil,
      # Metadatos del cluster
      created_by_node: Node.self(),
      current_node: Node.self(),
      created_at: DateTime.utc_now()
    }

    Logger.info("Turno #{shift.shift_id} iniciado en nodo #{Node.self()}")

    # Programar expiración automática
    if shift.expires_at do
      schedule_expiration(shift.expires_at)
    end

    {:ok, shift}
  end

  @impl true
  def handle_call(:get_shift, _from, shift) do
    # Actualizar metadatos del nodo actual
    updated_shift = %{shift | current_node: Node.self()}
    {:reply, updated_shift, updated_shift}
  end

  @impl true
  def handle_call({:reserve, user_id}, _from, shift) do
    cond do
      shift.status != :active or not shift.active ->
        {:reply, {:error, :shift_not_available}, shift}

      not is_nil(shift.reserved_by) ->
        {:reply, {:error, :shift_already_reserved}, shift}

      true ->
        reserved_shift = %{shift |
          reserved_by: user_id,
          reserved_at: DateTime.utc_now(),
          status: :reserved,
          current_node: Node.self()
        }

        Logger.info("Turno #{shift.shift_id} reservado por #{user_id} en nodo #{Node.self()}")
        {:reply, {:ok, reserved_shift}, reserved_shift}
    end
  end

  @impl true
  def handle_call({:update_status, new_status}, _from, shift) do
    updated_shift = %{shift |
      status: new_status,
      current_node: Node.self(),
      updated_at: DateTime.utc_now()
    }

    Logger.info("Turno #{shift.shift_id} actualizado a #{new_status} en nodo #{Node.self()}")
    {:reply, {:ok, updated_shift}, updated_shift}
  end

  @impl true
  def handle_call(:get_info, _from, shift) do
    info = %{
      shift_data: shift,
      process_info: %{
        pid: self(),
        node: Node.self(),
        registry_name: {:shift, shift.shift_id}
      },
      cluster_info: %{
        created_by_node: shift.created_by_node,
        current_node: Node.self(),
        migrations: shift[:migrations] || []
      }
    }
    {:reply, info, shift}
  end

  @impl true
  def handle_cast({:sync_shift, shift_data}, state) do
    Logger.info("Sincronizando turno \\#{shift_data.shift_id} en nodo \\#{Node.self()}")

    # Lógica para actualizar el estado local con shift_data
    # ...

    # Enviar el estado actualizado a otros nodos
    Node.list()
    |> Enum.each(fn node ->
      Logger.info("Enviando actualización de turno a nodo \\#{node}")
      Node.spawn(node, __MODULE__, :sync_shift, [shift_data])
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:expire, shift) do
    if shift.status == :active and is_nil(shift.reserved_by) do
      expired_shift = %{shift |
        status: :expired,
        active: false,
        expired_at: DateTime.utc_now(),
        current_node: Node.self()
      }

      Logger.info("Turno #{shift.shift_id} expirado automáticamente en nodo #{Node.self()}")
      {:noreply, expired_shift}
    else
      {:noreply, shift}
    end
  end

  @impl true
  def handle_info(msg, shift) do
    Logger.debug("Mensaje no manejado en turno #{shift.shift_id}: #{inspect(msg)}")
    {:noreply, shift}
  end

  # Funciones auxiliares

  defp schedule_expiration(expires_at) do
    now = DateTime.utc_now()

    case DateTime.compare(expires_at, now) do
      :gt ->
        diff_ms = DateTime.diff(expires_at, now, :millisecond)
        Process.send_after(self(), :expire, diff_ms)
      _ ->
        # Ya expiró
        send(self(), :expire)
    end
  end
end
