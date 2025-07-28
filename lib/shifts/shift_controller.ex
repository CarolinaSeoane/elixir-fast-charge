defmodule ElixirFastCharge.Shifts.ShiftController do
  @moduledoc """
  Controller que maneja la lógica de negocio para turnos.
  """

  def list_inactive_shifts do
    # Obtener todos los turnos y filtrar los inactivos
    all_shifts = ElixirFastCharge.DistributedShiftManager.list_all_shifts()
    Enum.filter(all_shifts, fn shift -> shift.status == :inactive end)
  end

  def get_shift_counts do
    all_shifts = ElixirFastCharge.DistributedShiftManager.list_all_shifts()
    active_shifts = ElixirFastCharge.DistributedShiftManager.list_active_shifts()

    total_count = length(all_shifts)
    active_count = length(active_shifts)

    %{
      total_shifts: total_count,
      active_shifts: active_count,
      inactive_shifts: total_count - active_count
    }
  end
end
