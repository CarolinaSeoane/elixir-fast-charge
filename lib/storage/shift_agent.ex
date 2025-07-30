defmodule ElixirFastCharge.Storage.ShiftAgent do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: via_tuple())
  end

  defp via_tuple do
    {:via, Horde.Registry, {ElixirFastCharge.DistributedStorageRegistry, __MODULE__}}
  end

  def create_shift(shift_data) do
    shift_id = generate_shift_id(shift_data.station_id, shift_data.point_id)

    shift = %{
      shift_id: shift_id,
      station_id: shift_data.station_id,
      point_id: shift_data.point_id,
      connector_type: shift_data.connector_type,
      power_kw: shift_data.power_kw,
      location: shift_data.location.address,

      # Temporal
      start_time: shift_data.start_time,
      end_time: shift_data.end_time,
      published_at: DateTime.utc_now(),
      expires_at: shift_data.expires_at,

      # Estado
      status: :active,
      active: true,
      reserved_by: nil,
      reserved_at: nil
    }

    Agent.update(via_tuple(), fn shifts ->
      Map.put(shifts, shift_id, shift)
    end)

    {:ok, shift}
  end

  def get_shift(shift_id) do
    Agent.get(via_tuple(), fn shifts ->
      Map.get(shifts, shift_id)
    end)
  end

  def list_active_shifts do
    Agent.get(via_tuple(), fn shifts ->
      shifts
      |> Enum.filter(fn {_id, shift} -> shift.status == :active end)
      |> Enum.map(fn {_id, shift} -> shift end)
    end)
  end

  def list_active_shifts_boolean do
    Agent.get(via_tuple(), fn shifts ->
      shifts
      |> Enum.filter(fn {_id, shift} -> shift.active == true end)
      |> Enum.map(fn {_id, shift} -> shift end)
    end)
  end

  def list_inactive_shifts do
    Agent.get(via_tuple(), fn shifts ->
      shifts
      |> Enum.filter(fn {_id, shift} -> shift.active == false end)
      |> Enum.map(fn {_id, shift} -> shift end)
    end)
  end

  def count_active_shifts do
    Agent.get(via_tuple(), fn shifts ->
      shifts
      |> Enum.count(fn {_id, shift} -> shift.active == true end)
    end)
  end

  def list_shifts_by_station(station_id) do
    Agent.get(via_tuple(), fn shifts ->
      shifts
      |> Enum.filter(fn {_id, shift} -> shift.station_id == station_id end)
      |> Enum.map(fn {_id, shift} -> shift end)
    end)
  end

  def reserve_shift(shift_id, user_id) do
    Agent.get_and_update(via_tuple(), fn shifts ->
      case Map.get(shifts, shift_id) do
        nil ->
          {{:error, :shift_not_found}, shifts}

        shift when shift.status != :active ->
          {{:error, :shift_not_available}, shifts}

                shift ->
          updated_shift = %{shift |
            status: :reserved,
            active: false,
            reserved_by: user_id,
            reserved_at: DateTime.utc_now()
          }
          updated_shifts = Map.put(shifts, shift_id, updated_shift)
          {{:ok, updated_shift}, updated_shifts}
      end
    end)
  end

  def expire_old_shifts do
    now = DateTime.utc_now()

    Agent.update(via_tuple(), fn shifts ->
      Enum.map(shifts, fn {shift_id, shift} ->
        if shift.status == :active and DateTime.compare(now, shift.expires_at) == :gt do
          {shift_id, %{shift | status: :expired, active: false}}
        else
          {shift_id, shift}
        end
      end)
      |> Enum.into(%{})
    end)
  end

  def get_all_shifts do
    Agent.get(via_tuple(), & &1)
  end

  def count_shifts do
    Agent.get(via_tuple(), fn shifts -> map_size(shifts) end)
  end

  def set_shift_active(shift_id, active_status) when is_boolean(active_status) do
    Agent.get_and_update(via_tuple(), fn shifts ->
      case Map.get(shifts, shift_id) do
        nil ->
          {{:error, :shift_not_found}, shifts}

        shift ->
          updated_shift = %{shift | active: active_status}
          updated_shifts = Map.put(shifts, shift_id, updated_shift)
          {{:ok, updated_shift}, updated_shifts}
      end
    end)
  end

  defp generate_shift_id(station_id, point_id) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    "shift_#{station_id}_#{point_id}_#{timestamp}"
  end
end
