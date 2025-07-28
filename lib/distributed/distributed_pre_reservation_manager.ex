defmodule ElixirFastCharge.DistributedPreReservationManager do
  @moduledoc """
  Manager para coordinar operaciones de pre-reservas distribuidas.
  Incluye la lógica de actualización automática de pre-reservas existentes.
  """
  require Logger

  # API pública

  def create_pre_reservation(user_id, shift_id) do
    # Primero verificar si el usuario ya tiene una pre-reserva pendiente
    case find_user_pending_pre_reservation(user_id) do
      nil ->
        # No tiene pre-reserva pendiente, crear nueva
        create_new_pre_reservation(user_id, shift_id)

      existing_pre_reservation_id ->
        # Ya tiene pre-reserva pendiente, actualizarla
        update_existing_pre_reservation(existing_pre_reservation_id, shift_id)
    end
  end

  def get_pre_reservation(pre_reservation_id) do
    ElixirFastCharge.DistributedPreReservation.get_pre_reservation(pre_reservation_id)
  end

  def confirm_pre_reservation(pre_reservation_id) do
    ElixirFastCharge.DistributedPreReservation.confirm_pre_reservation(pre_reservation_id)
  end

  def cancel_pre_reservation(pre_reservation_id) do
    ElixirFastCharge.DistributedPreReservation.cancel_pre_reservation(pre_reservation_id)
  end

  def list_pending_pre_reservations_for_shift(shift_id) do
    ElixirFastCharge.HordeRegistry.list_all()
    |> Enum.filter(fn {{:pre_reservation, _id}, _pid, _value} -> true; _ -> false end)
    |> Enum.map(fn {{:pre_reservation, pre_reservation_id}, _pid, _value} ->
      case ElixirFastCharge.DistributedPreReservation.get_pre_reservation(pre_reservation_id) do
        {:ok, pre_reservation} -> pre_reservation
        _ -> nil
      end
    end)
    |> Enum.filter(fn pre_reservation ->
      pre_reservation &&
      pre_reservation.shift_id == shift_id &&
      pre_reservation.status == :pending &&
      not expired?(pre_reservation)
    end)
  end

  def list_pending_pre_reservations_for_user(user_id) do
    ElixirFastCharge.HordeRegistry.list_all()
    |> Enum.filter(fn {{:pre_reservation, _id}, _pid, _value} -> true; _ -> false end)
    |> Enum.map(fn {{:pre_reservation, pre_reservation_id}, _pid, _value} ->
      case ElixirFastCharge.DistributedPreReservation.get_pre_reservation(pre_reservation_id) do
        {:ok, pre_reservation} -> pre_reservation
        _ -> nil
      end
    end)
    |> Enum.filter(fn pre_reservation ->
      pre_reservation &&
      pre_reservation.user_id == user_id &&
      pre_reservation.status == :pending &&
      not expired?(pre_reservation)
    end)
  end

  def get_all_pre_reservations do
    ElixirFastCharge.HordeRegistry.list_all()
    |> Enum.filter(fn {{:pre_reservation, _id}, _pid, _value} -> true; _ -> false end)
    |> Enum.map(fn {{:pre_reservation, pre_reservation_id}, _pid, _value} ->
      case ElixirFastCharge.DistributedPreReservation.get_pre_reservation(pre_reservation_id) do
        {:ok, pre_reservation} -> pre_reservation
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  def count_pre_reservations do
    all_pre_reservations = get_all_pre_reservations()

    counts_by_status = all_pre_reservations
    |> Enum.group_by(& &1.status)
    |> Enum.map(fn {status, list} -> {status, length(list)} end)
    |> Map.new()

    Map.put(counts_by_status, :total, length(all_pre_reservations))
  end

  def get_cluster_stats do
    all_pre_reservations = get_all_pre_reservations()

    %{
      node: Node.self(),
      cluster_nodes: [Node.self() | Node.list()],
      total_pre_reservations: length(all_pre_reservations),
      pending_pre_reservations: Enum.count(all_pre_reservations, &(&1.status == :pending)),
      confirmed_pre_reservations: Enum.count(all_pre_reservations, &(&1.status == :confirmed)),
      expired_pre_reservations: Enum.count(all_pre_reservations, &(&1.status == :expired)),
      cancelled_pre_reservations: Enum.count(all_pre_reservations, &(&1.status == :cancelled)),
      pre_reservation_distribution: get_pre_reservation_distribution(all_pre_reservations)
    }
  end

  def expire_old_pre_reservations do
    # Las pre-reservas se expiran automáticamente, pero podemos contar cuántas expiraron
    all_pre_reservations = get_all_pre_reservations()

    expired_count = Enum.count(all_pre_reservations, fn pre_reservation ->
      pre_reservation.status == :expired || expired?(pre_reservation)
    end)

    Logger.info("⏰ #{expired_count} pre-reservas expiradas en el cluster")
    expired_count
  end

  # Funciones privadas

  defp find_user_pending_pre_reservation(user_id) do
    pending_pre_reservations = list_pending_pre_reservations_for_user(user_id)

    case pending_pre_reservations do
      [pre_reservation | _] -> pre_reservation.pre_reservation_id
      [] -> nil
    end
  end

  defp create_new_pre_reservation(user_id, shift_id) do
    pre_reservation_id = generate_pre_reservation_id()
    expires_at = DateTime.add(DateTime.utc_now(), 2 * 60, :second) # 2 minutos

    pre_reservation_data = %{
      pre_reservation_id: pre_reservation_id,
      user_id: user_id,
      shift_id: shift_id,
      expires_at: expires_at
    }

    case ElixirFastCharge.HordeSupervisor.start_child({ElixirFastCharge.DistributedPreReservation, pre_reservation_data}) do
      {:ok, _pid} ->
        Logger.info("📝 Pre-reserva #{pre_reservation_id} creada exitosamente en cluster")
        {:ok, Map.put(pre_reservation_data, :status, :pending), :created}
      {:error, reason} ->
        Logger.error("Error creando pre-reserva #{pre_reservation_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_existing_pre_reservation(pre_reservation_id, new_shift_id) do
    case ElixirFastCharge.DistributedPreReservation.update_shift(pre_reservation_id, new_shift_id) do
      {:ok, updated_pre_reservation, :updated} ->
        Logger.info("Pre-reserva #{pre_reservation_id} actualizada con turno #{new_shift_id}")
        {:ok, updated_pre_reservation, :updated}
      {:error, reason} ->
                  Logger.error("Error actualizando pre-reserva #{pre_reservation_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_pre_reservation_id do
    timestamp = DateTime.utc_now()
                |> DateTime.to_unix(:millisecond)
                |> Integer.to_string()

    random_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    node_suffix = Node.self() |> Atom.to_string() |> String.slice(0..3)

    "pre_res_#{timestamp}_#{random_suffix}_#{node_suffix}"
  end

  defp expired?(pre_reservation) do
    DateTime.compare(DateTime.utc_now(), pre_reservation.expires_at) == :gt
  end

  defp get_pre_reservation_distribution(pre_reservations) do
    pre_reservations
    |> Enum.group_by(& &1.current_node)
    |> Enum.map(fn {node, node_pre_reservations} ->
      {node, length(node_pre_reservations)}
    end)
    |> Map.new()
  end
end
