defmodule ElixirFastCharge.DistributedShiftManager do
  @moduledoc """
  Manager para coordinar operaciones de turnos distribuidos.
  Actúa como facade y coordinador para el sistema distribuido.
  """
  require Logger

  # API pública

  def create_shift(shift_data) do
    shift_id = generate_shift_id(shift_data.station_id, shift_data.point_id)

    shift_data_with_id = %{
      shift_id: shift_id,
      station_id: shift_data.station_id,
      point_id: shift_data.point_id,
      connector_type: shift_data.connector_type,
      power_kw: shift_data.power_kw,
      location: shift_data.location,
      start_time: shift_data.start_time,
      end_time: shift_data.end_time,
      expires_at: shift_data.expires_at
    }

    case ElixirFastCharge.HordeSupervisor.start_child({ElixirFastCharge.DistributedShift, shift_data_with_id}) do
      {:ok, _pid} ->
        Logger.info("Turno #{shift_id} creado exitosamente en cluster")
        {:ok, shift_data_with_id}
      {:error, reason} ->
        Logger.error(" Error creando turno #{shift_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_shift(shift_id) do
    ElixirFastCharge.DistributedShift.get_shift(shift_id)
  end

  def reserve_shift(shift_id, user_id) do
    ElixirFastCharge.DistributedShift.reserve_shift(shift_id, user_id)
  end

  def list_active_shifts do
    ElixirFastCharge.HordeRegistry.list_all()
    |> Enum.filter(fn {{:shift, _shift_id}, _pid, _value} -> true; _ -> false end)
    |> Enum.map(fn {{:shift, shift_id}, _pid, _value} ->
      case ElixirFastCharge.DistributedShift.get_shift(shift_id) do
        {:ok, shift} -> shift
        {:error, :not_found} -> nil
      end
    end)
    |> Enum.filter(fn shift ->
      shift && shift.status == :active && shift.active == true
    end)
  end

  def list_all_shifts do
    ElixirFastCharge.HordeRegistry.list_all()
    |> Enum.filter(fn {{:shift, _shift_id}, _pid, _value} -> true; _ -> false end)
    |> Enum.map(fn {{:shift, shift_id}, _pid, _value} ->
      case ElixirFastCharge.DistributedShift.get_shift(shift_id) do
        {:ok, shift} -> shift
        {:error, :not_found} -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  def get_cluster_stats do
    all_shifts = list_all_shifts()

    %{
      node: Node.self(),
      cluster_nodes: [Node.self() | Node.list()],
      total_shifts: length(all_shifts),
      active_shifts: Enum.count(all_shifts, &(&1.status == :active)),
      reserved_shifts: Enum.count(all_shifts, &(&1.status == :reserved)),
      expired_shifts: Enum.count(all_shifts, &(&1.status == :expired)),
      shift_distribution: get_shift_distribution(all_shifts)
    }
  end

  def get_shift_info(shift_id) do
    ElixirFastCharge.DistributedShift.get_info(shift_id)
  end

  def update_shift_status(shift_id, status) do
    ElixirFastCharge.DistributedShift.update_status(shift_id, status)
  end

  def expire_old_shifts do
    # Los turnos se expiran automáticamente, pero podemos forzar la expiración
    active_shifts = list_active_shifts()
    now = DateTime.utc_now()

    expired_count = Enum.count(active_shifts, fn shift ->
      if shift.expires_at && DateTime.compare(now, shift.expires_at) == :gt do
        update_shift_status(shift.shift_id, :expired)
        true
      else
        false
      end
    end)

    Logger.info("⏰ #{expired_count} turnos expirados manualmente")
    expired_count
  end

  # Funciones auxiliares

  defp generate_shift_id(station_id, point_id) do
    timestamp = DateTime.utc_now()
                |> DateTime.to_unix(:millisecond)
                |> Integer.to_string()
    "shift_#{station_id}_#{point_id}_#{timestamp}"
  end

  defp get_shift_distribution(shifts) do
    shifts
    |> Enum.group_by(& &1.current_node)
    |> Enum.map(fn {node, node_shifts} ->
      {node, length(node_shifts)}
    end)
    |> Map.new()
  end
end
