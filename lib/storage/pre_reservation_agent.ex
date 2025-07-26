defmodule ElixirFastCharge.Storage.PreReservationAgent do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def create_pre_reservation(user_id, shift_id) do
    pre_reservation_id = generate_pre_reservation_id()
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, 2 * 60, :second) # 2 minutos

    pre_reservation = %{
      pre_reservation_id: pre_reservation_id,
      user_id: user_id,
      shift_id: shift_id,
      status: :pending,
      created_at: now,
      expires_at: expires_at
    }

    Agent.get_and_update(__MODULE__, fn pre_reservations ->
      # Verificar que no haya una pre-reserva activa para este user_id y shift_id
      existing = Enum.find(Map.values(pre_reservations), fn pr ->
        pr.user_id == user_id and pr.shift_id == shift_id and pr.status == :pending
      end)

      case existing do
        nil ->
          updated_pre_reservations = Map.put(pre_reservations, pre_reservation_id, pre_reservation)
          {{:ok, pre_reservation}, updated_pre_reservations}

        _existing_pre_reservation ->
          {{:error, :already_pre_reserved}, pre_reservations}
      end
    end)
  end

  def get_pre_reservation(pre_reservation_id) do
    Agent.get(__MODULE__, fn pre_reservations ->
      case Map.get(pre_reservations, pre_reservation_id) do
        nil -> {:error, :not_found}
        pre_reservation -> {:ok, pre_reservation}
      end
    end)
  end

  def confirm_pre_reservation(pre_reservation_id) do
    Agent.get_and_update(__MODULE__, fn pre_reservations ->
      case Map.get(pre_reservations, pre_reservation_id) do
        nil ->
          {{:error, :not_found}, pre_reservations}

        pre_reservation when pre_reservation.status != :pending ->
          {{:error, :invalid_status}, pre_reservations}

        pre_reservation ->
          now = DateTime.utc_now()
          if DateTime.compare(now, pre_reservation.expires_at) == :gt do
            # Pre-reserva expirada
            expired_pre_reservation = %{pre_reservation | status: :expired}
            updated_pre_reservations = Map.put(pre_reservations, pre_reservation_id, expired_pre_reservation)
            {{:error, :expired}, updated_pre_reservations}
          else
            # Confirmar pre-reserva
            confirmed_pre_reservation = Map.merge(pre_reservation, %{status: :confirmed, confirmed_at: now})
            updated_pre_reservations = Map.put(pre_reservations, pre_reservation_id, confirmed_pre_reservation)
            {{:ok, confirmed_pre_reservation}, updated_pre_reservations}
          end
      end
    end)
  end

  def cancel_pre_reservation(pre_reservation_id) do
    Agent.get_and_update(__MODULE__, fn pre_reservations ->
      case Map.get(pre_reservations, pre_reservation_id) do
        nil ->
          {{:error, :not_found}, pre_reservations}

        pre_reservation ->
          cancelled_pre_reservation = Map.merge(pre_reservation, %{status: :cancelled, cancelled_at: DateTime.utc_now()})
          updated_pre_reservations = Map.put(pre_reservations, pre_reservation_id, cancelled_pre_reservation)
          {{:ok, cancelled_pre_reservation}, updated_pre_reservations}
      end
    end)
  end

  def list_pending_pre_reservations_for_shift(shift_id) do
    Agent.get(__MODULE__, fn pre_reservations ->
      now = DateTime.utc_now()

      pre_reservations
      |> Map.values()
      |> Enum.filter(fn pr ->
        pr.shift_id == shift_id and
        pr.status == :pending and
        DateTime.compare(now, pr.expires_at) == :lt
      end)
    end)
  end

  def list_pending_pre_reservations_for_user(user_id) do
    Agent.get(__MODULE__, fn pre_reservations ->
      now = DateTime.utc_now()

      pre_reservations
      |> Map.values()
      |> Enum.filter(fn pr ->
        pr.user_id == user_id and
        pr.status == :pending and
        DateTime.compare(now, pr.expires_at) == :lt
      end)
    end)
  end

  def expire_old_pre_reservations do
    Agent.get_and_update(__MODULE__, fn pre_reservations ->
      now = DateTime.utc_now()

      {expired_count, updated_pre_reservations} =
        Enum.map_reduce(pre_reservations, 0, fn {id, pr}, count ->
          if pr.status == :pending and DateTime.compare(now, pr.expires_at) == :gt do
            expired_pr = Map.merge(pr, %{status: :expired})
            {{id, expired_pr}, count + 1}
          else
            {{id, pr}, count}
          end
        end)
        |> then(fn {updated_list, count} -> {count, Map.new(updated_list)} end)

      {expired_count, updated_pre_reservations}
    end)
  end

  def count_pre_reservations do
    Agent.get(__MODULE__, fn pre_reservations ->
      all_count = map_size(pre_reservations)

      counts_by_status =
        pre_reservations
        |> Map.values()
        |> Enum.group_by(& &1.status)
        |> Enum.map(fn {status, list} -> {status, length(list)} end)
        |> Map.new()

      Map.put(counts_by_status, :total, all_count)
    end)
  end

  def get_all_pre_reservations do
    Agent.get(__MODULE__, &Map.values(&1))
  end

    defp generate_pre_reservation_id do
    timestamp = DateTime.utc_now()
                |> DateTime.to_unix(:millisecond)
                |> Integer.to_string()

    random_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    "pre_res_" <> timestamp <> "_" <> random_suffix
  end
end
