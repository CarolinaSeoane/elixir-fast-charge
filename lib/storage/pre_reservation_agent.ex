defmodule ElixirFastCharge.Storage.PreReservationAgent do
  use Agent

  def start_link(_opts) do
    # Try to recover state from other nodes
    recovered_state = try_recover_state()

    final_state = case recovered_state do
      nil ->
        IO.puts("🆕 PreReservationAgent: Starting with new state")
        %{}
      state ->
        IO.puts("🔄 PreReservationAgent: Recovered state with #{map_size(state)} pre-reservations")
        state
    end

    case Agent.start_link(fn -> final_state end, name: via_tuple()) do
      {:ok, pid} ->
        # Replicate initial state to other nodes
        replicate_state(final_state)
        {:ok, pid}
      error -> error
    end
  end

  defp via_tuple do
    {:via, Horde.Registry, {ElixirFastCharge.DistributedStorageRegistry, __MODULE__}}
  end

  def create_pre_reservation(user_id, shift_id) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, 1 * 60, :second) # 1 minuto

    pre_reservation_id = generate_pre_reservation_id()
    pre_reservation = %{
      pre_reservation_id: pre_reservation_id,
      user_id: user_id,
      shift_id: shift_id,
      status: :pending,
      created_at: now,
      expires_at: expires_at,
      updated_at: now
    }

    new_state = Agent.get_and_update(via_tuple(), fn pre_reservations ->
      updated_state = Map.put(pre_reservations, pre_reservation_id, pre_reservation)
      {updated_state, updated_state}
    end)

    # Replicate state after change
    replicate_state(new_state)

    {:ok, pre_reservation}
  end

  def get_pre_reservation(pre_reservation_id) do
    Agent.get(via_tuple(), fn pre_reservations ->
      case Map.get(pre_reservations, pre_reservation_id) do
        nil -> {:error, :not_found}
        pre_reservation -> {:ok, pre_reservation}
      end
    end)
  end

  def confirm_pre_reservation(pre_reservation_id) do
    result = Agent.get_and_update(via_tuple(), fn pre_reservations ->
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

            # Get current state for replication
    current_state = Agent.get(via_tuple(), & &1)
    replicate_state(current_state)

    result
  end

  def cancel_pre_reservation(pre_reservation_id) do
    result = Agent.get_and_update(via_tuple(), fn pre_reservations ->
      case Map.get(pre_reservations, pre_reservation_id) do
        nil ->
          {{:error, :not_found}, pre_reservations}

        pre_reservation ->
          cancelled_pre_reservation = Map.merge(pre_reservation, %{status: :cancelled, cancelled_at: DateTime.utc_now()})
          updated_pre_reservations = Map.put(pre_reservations, pre_reservation_id, cancelled_pre_reservation)
          {{:ok, cancelled_pre_reservation}, updated_pre_reservations}
      end
    end)

        # Get current state for replication
    current_state = Agent.get(via_tuple(), & &1)
    replicate_state(current_state)

    result
  end

  def list_pending_pre_reservations_for_shift(shift_id) do
    Agent.get(via_tuple(), fn pre_reservations ->
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

  def list_confirmed_pre_reservations_for_user(user_id) do
    result = Agent.get(via_tuple(), fn pre_reservations ->
      filtered_result = pre_reservations
      |> Map.values()
      |> Enum.filter(fn pr ->
        user_match = pr.user_id == user_id
        status_match = pr.status == :confirmed
        overall_match = user_match and status_match
        overall_match
      end)
      filtered_result
    end)

    result
  end

  def expire_old_pre_reservations do
    expired_count = Agent.get_and_update(via_tuple(), fn pre_reservations ->
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

        # Get current state for replication
    current_state = Agent.get(via_tuple(), & &1)
    replicate_state(current_state)

    expired_count
  end

  def get_all_pre_reservations do
    Agent.get(via_tuple(), &Map.values(&1))
  end

  def update_pre_reservation(pre_reservation_id, user_id, shift_id) do
    now = DateTime.utc_now()

            result = Agent.get_and_update(via_tuple(), fn pre_reservations ->
      case Map.get(pre_reservations, pre_reservation_id) do
        nil ->
          {{:error, :not_found}, pre_reservations}

        existing_pre_reservation ->
          # Verificar que la pre-reserva pertenece al usuario
          if existing_pre_reservation.user_id == user_id do
            # Actualizar la pre-reserva con el nuevo shift_id
            updated_pre_reservation = %{existing_pre_reservation |
              shift_id: shift_id,
              updated_at: now
            }

            updated_pre_reservations = Map.put(pre_reservations, pre_reservation_id, updated_pre_reservation)
            {{:ok, updated_pre_reservation}, updated_pre_reservations}
          else
            {{:error, :unauthorized}, pre_reservations}
          end
      end
    end)

    # Get current state for replication
    current_state = Agent.get(via_tuple(), & &1)
    replicate_state(current_state)

    result
  end

  defp generate_pre_reservation_id do
    timestamp = DateTime.utc_now()
                |> DateTime.to_unix(:millisecond)
                |> Integer.to_string()

    random_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    "pre_res_" <> timestamp <> "_" <> random_suffix
  end

  # === STATE REPLICATION AND RECOVERY ===

  defp try_recover_state do
    # Check all connected nodes for replicated state
    all_nodes = [Node.self() | Node.list()]

    recovered_state = Enum.find_value(all_nodes, fn node ->
      try do
        case :rpc.call(node, __MODULE__, :get_replicated_state, [], 5000) do
          {:ok, state} when is_map(state) ->
            IO.puts("✅ PreReservationAgent: Found replicated state on #{node}")
            state
          _ -> nil
        end
      rescue
        _ -> nil
      end
    end)

    # If no remote state found, check locally
    if recovered_state do
      recovered_state
    else
      case :ets.lookup(:pre_reservation_replicas, :pre_reservations) do
        [{:pre_reservations, state}] ->
          IO.puts("✅ PreReservationAgent: Found state locally!")
          state
        [] ->
          IO.puts("😞 PreReservationAgent: No replicated state found")
          nil
      end
    end
  end

  defp replicate_state(state) do
    # Replicate to all other connected nodes asynchronously
    all_nodes = [Node.self() | Node.list()]

    Enum.each(all_nodes, fn node ->
      Task.start(fn ->
        try do
          :rpc.call(node, __MODULE__, :store_replicated_state, [state], 2000)
        rescue
          _ -> :ok
        end
      end)
    end)

    # Return :ok explicitly to avoid confusion
    :ok
  end

  # === PUBLIC FUNCTIONS FOR RPC ACCESS ===

  def get_replicated_state do
    case :ets.lookup(:pre_reservation_replicas, :pre_reservations) do
      [{:pre_reservations, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end

  def store_replicated_state(state) do
    :ets.insert(:pre_reservation_replicas, {:pre_reservations, state})
    :ok
  end

  # === DEBUG FUNCTIONS ===

  def show_all_replicas do
    all_nodes = [Node.self() | Node.list()]

    IO.puts("\n🔍 === PRE-RESERVATION REPLICAS ACROSS CLUSTER ===")

    Enum.each(all_nodes, fn node ->
      try do
        case :rpc.call(node, :ets, :lookup, [:pre_reservation_replicas, :pre_reservations], 5000) do
          [{:pre_reservations, state}] when is_map(state) and map_size(state) > 0 ->
            IO.puts("📍 Node #{node}: #{map_size(state)} pre-reservations")
            Enum.each(state, fn {id, pr} ->
              IO.puts("  🎫 #{id}: #{pr.user_id} -> #{pr.shift_id} (#{pr.status})")
            end)
          _ ->
            IO.puts("📍 Node #{node}: (no pre-reservation replicas)")
        end
      rescue
        _ -> IO.puts("📍 Node #{node}: (no response)")
      end
    end)

  end

end
