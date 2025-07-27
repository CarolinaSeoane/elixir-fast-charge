defmodule ElixirFastCharge.Shifts.ShiftController do
  @moduledoc """
  Controller que maneja la lógica de negocio para turnos.
  """

  def list_inactive_shifts do
    ElixirFastCharge.Storage.ShiftAgent.list_inactive_shifts()
  end

  def get_shift_counts do
    total_count = ElixirFastCharge.Storage.ShiftAgent.count_shifts()
    active_count = ElixirFastCharge.Storage.ShiftAgent.count_active_shifts()

    %{
      total_shifts: total_count,
      active_shifts: active_count,
      inactive_shifts: total_count - active_count
    }
  end
end
