defmodule ElixirFastCharge.DistributedPreReservation do
  @moduledoc """
  GenServer distribuido para manejar una pre-reserva individual.
  Cada pre-reserva es un proceso independiente con expiración automática.
  """
  use GenServer
  require Logger

  # Client API

  def start_link(pre_reservation_data) do
    pre_reservation_id = pre_reservation_data.pre_reservation_id
    GenServer.start_link(
      __MODULE__,
      pre_reservation_data,
      name: {:via, Horde.Registry, {ElixirFastCharge.HordeRegistry, {:pre_reservation, pre_reservation_id}}}
    )
  end

  def get_pre_reservation(pre_reservation_id) do
    case ElixirFastCharge.HordeRegistry.lookup({:pre_reservation, pre_reservation_id}) do
      {:ok, pid} -> GenServer.call(pid, :get_pre_reservation)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def confirm_pre_reservation(pre_reservation_id) do
    case ElixirFastCharge.HordeRegistry.lookup({:pre_reservation, pre_reservation_id}) do
      {:ok, pid} -> GenServer.call(pid, :confirm)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def cancel_pre_reservation(pre_reservation_id) do
    case ElixirFastCharge.HordeRegistry.lookup({:pre_reservation, pre_reservation_id}) do
      {:ok, pid} -> GenServer.call(pid, :cancel)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def update_shift(pre_reservation_id, new_shift_id) do
    case ElixirFastCharge.HordeRegistry.lookup({:pre_reservation, pre_reservation_id}) do
      {:ok, pid} -> GenServer.call(pid, {:update_shift, new_shift_id})
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def get_info(pre_reservation_id) do
    case ElixirFastCharge.HordeRegistry.lookup({:pre_reservation, pre_reservation_id}) do
      {:ok, pid} -> GenServer.call(pid, :get_info)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def sync_pre_reservation(pre_reservation_data) do
    GenServer.cast(__MODULE__, {:sync_pre_reservation, pre_reservation_data})
  end

  # Server callbacks

  @impl true
  def init(pre_reservation_data) do
    pre_reservation = %{
      pre_reservation_id: pre_reservation_data.pre_reservation_id,
      user_id: pre_reservation_data.user_id,
      shift_id: pre_reservation_data.shift_id,
      status: :pending,
      created_at: DateTime.utc_now(),
      expires_at: pre_reservation_data.expires_at,
      # Metadatos del cluster
      created_by_node: Node.self(),
      current_node: Node.self()
    }

    pre_reservation_id = Map.get(pre_reservation, :pre_reservation_id, "unknown")
    expires_at = Map.get(pre_reservation, :expires_at)

    Logger.info("Pre-reserva #{pre_reservation_id} iniciada en nodo #{Node.self()}")

    # Programar expiración automática (2 minutos)
    if expires_at, do: schedule_expiration(expires_at)

    {:ok, pre_reservation}
  end

  @impl true
  def handle_call(:get_pre_reservation, _from, pre_reservation) do
    # Verificar si expiró
    status = Map.get(pre_reservation, :status, :unknown)
    if expired?(pre_reservation) and status == :pending do
      expired_pre_reservation = Map.merge(pre_reservation, %{
        status: :expired,
        expired_at: DateTime.utc_now(),
        current_node: Node.self()
      })
      {:reply, {:ok, expired_pre_reservation}, expired_pre_reservation}
    else
      updated_pre_reservation = Map.merge(pre_reservation, %{current_node: Node.self()})
      {:reply, {:ok, updated_pre_reservation}, updated_pre_reservation}
    end
  end

  @impl true
  def handle_call(:confirm, _from, pre_reservation) do
    status = Map.get(pre_reservation, :status, :unknown)
    pre_reservation_id = Map.get(pre_reservation, :pre_reservation_id, "unknown")

    cond do
      status != :pending ->
        {:reply, {:error, :invalid_status}, pre_reservation}

      expired?(pre_reservation) ->
        expired_pre_reservation = Map.merge(pre_reservation, %{
          status: :expired,
          expired_at: DateTime.utc_now(),
          current_node: Node.self()
        })
        {:reply, {:error, :expired}, expired_pre_reservation}

      true ->
        confirmed_pre_reservation = Map.merge(pre_reservation, %{
          status: :confirmed,
          confirmed_at: DateTime.utc_now(),
          current_node: Node.self()
        })

        Logger.info("Pre-reserva #{pre_reservation_id} confirmada en nodo #{Node.self()}")
        {:reply, {:ok, confirmed_pre_reservation}, confirmed_pre_reservation}
    end
  end

  @impl true
  def handle_call(:cancel, _from, pre_reservation) do
    pre_reservation_id = Map.get(pre_reservation, :pre_reservation_id, "unknown")
    cancelled_pre_reservation = Map.merge(pre_reservation, %{
      status: :cancelled,
      cancelled_at: DateTime.utc_now(),
      current_node: Node.self()
    })

    Logger.info("Pre-reserva #{pre_reservation_id} cancelada en nodo #{Node.self()}")
    {:reply, {:ok, cancelled_pre_reservation}, cancelled_pre_reservation}
  end

  @impl true
  def handle_call({:update_shift, new_shift_id}, _from, pre_reservation) do
    status = Map.get(pre_reservation, :status, :unknown)
    if status == :pending and not expired?(pre_reservation) do
      # Extender el tiempo de expiración cuando se actualiza
      new_expires_at = DateTime.add(DateTime.utc_now(), 2 * 60, :second)

      updated_pre_reservation = Map.merge(pre_reservation, %{
        shift_id: new_shift_id,
        expires_at: new_expires_at,
        updated_at: DateTime.utc_now(),
        current_node: Node.self()
      })

      # Reprogramar expiración
      schedule_expiration(new_expires_at)

      pre_reservation_id = Map.get(updated_pre_reservation, :pre_reservation_id, "unknown")
      Logger.info("Pre-reserva #{pre_reservation_id} actualizada con turno #{new_shift_id} en nodo #{Node.self()}")
      {:reply, {:ok, updated_pre_reservation, :updated}, updated_pre_reservation}
    else
      {:reply, {:error, :cannot_update}, pre_reservation}
    end
  end

  @impl true
  def handle_call(:get_info, _from, pre_reservation) do
    info = %{
      pre_reservation_data: pre_reservation,
      process_info: %{
        pid: self(),
        node: Node.self(),
        registry_name: {:pre_reservation, pre_reservation.pre_reservation_id}
      },
      cluster_info: %{
        created_by_node: pre_reservation.created_by_node,
        current_node: Node.self(),
        is_expired: expired?(pre_reservation)
      }
    }
    {:reply, info, pre_reservation}
  end

  @impl true
  def handle_info(:expire, pre_reservation) do
    status = Map.get(pre_reservation, :status, :unknown)
    pre_reservation_id = Map.get(pre_reservation, :pre_reservation_id, "unknown")

    if status == :pending do
      expired_pre_reservation = Map.merge(pre_reservation, %{
        status: :expired,
        expired_at: DateTime.utc_now(),
        current_node: Node.self()
      })

      Logger.info("Pre-reserva #{pre_reservation_id} expirada automáticamente en nodo #{Node.self()}")

      # Terminar el proceso después de expirar
      {:stop, :normal, expired_pre_reservation}
    else
      {:noreply, pre_reservation}
    end
  end

  @impl true
  def handle_info(msg, pre_reservation) do
    Logger.debug("Mensaje no manejado en pre-reserva #{pre_reservation.pre_reservation_id}: #{inspect(msg)}")
    {:noreply, pre_reservation}
  end

  @impl true
  def handle_cast({:sync_pre_reservation, pre_reservation_data}, state) do
    Logger.info("Sincronizando pre-reserva #{pre_reservation_data.pre_reservation_id} en nodo #{Node.self()}")

    # Lógica para actualizar el estado local con pre_reservation_data
    # ...

    # Enviar el estado actualizado a otros nodos
    Node.list()
    |> Enum.each(fn node ->
      Logger.info("Enviando actualización de pre-reserva a nodo #{node}")
      Node.spawn(node, __MODULE__, :sync_pre_reservation, [pre_reservation_data])
    end)

    {:noreply, state}
  end

  # Funciones auxiliares

  defp expired?(pre_reservation) do
    case Map.get(pre_reservation, :expires_at) do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end

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
