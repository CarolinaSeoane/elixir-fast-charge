defmodule ElixirFastCharge.Preferences do
  use Agent

  def start_link(initial_state \\ %{}) do
    # Try to recover state from other nodes
    recovered_state = try_recover_state()

    final_state = case recovered_state do
      nil ->
        initial_state
      state ->
        IO.puts("recovered state with #{map_size(state)} preferences")
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

  defp generate_preference_id do
    System.unique_integer([:positive])
  end

  def add_preference(preference_data) when is_map(preference_data) do
    preference_id = generate_preference_id()
    preference =
      preference_data
      |> Map.put_new(:timestamp, DateTime.utc_now())
      |> Map.put(:preference_id, preference_id)
      |> Map.put(:pid, inspect(self()))

    new_state = Agent.get_and_update(via_tuple(), fn preferences ->
      updated_preferences = Map.put(preferences, preference_id, preference)
      {updated_preferences, updated_preferences}
    end)

    replicate_state(new_state)

    preference
  end

  def get_all_preferences do
    Agent.get(via_tuple(), fn preferences ->
      Map.values(preferences)
    end)
  end

  def get_preferences_by_user(usuario) do
    Agent.get(via_tuple(), fn preferences ->
      preferences
      |> Map.values()
      |> Enum.filter(fn pref -> Map.get(pref, :username) == usuario end)
    end)
  end

  def delete_preferences_by_user(usuario) do
    new_state = Agent.get_and_update(via_tuple(), fn preferences ->
      updated_preferences = Enum.reject(preferences, fn {_id, pref} -> Map.get(pref, :username) == usuario end)
                           |> Enum.into(%{})
      {updated_preferences, updated_preferences}
    end)

    replicate_state(new_state)

    new_state
  end

  def find_preferences(criteria) do
    Agent.get(via_tuple(), fn preferences ->
      preferences
      |> Map.values()
      |> Enum.filter(fn pref ->
        Enum.all?(criteria, fn {key, value} ->
          Map.get(pref, key) == value
        end)
      end)
    end)
  end

    def update_preference_alert(username, preference_id, alert_status) do
    result = Agent.get_and_update(via_tuple(), fn preferences ->
      case Map.get(preferences, preference_id) do
        nil ->
          {{:error, :preference_not_found}, preferences}

        preference ->
          # Verify preference belongs to the user
          if Map.get(preference, :username) == username do
            updated_pref = Map.put(preference, :alert, alert_status)
            updated_preferences = Map.put(preferences, preference_id, updated_pref)
            {{:ok, updated_pref}, updated_preferences}
          else
            {{:error, :preference_not_found}, preferences}
          end
      end
    end)

    # Extract the result and new state
    case result do
      {:ok, updated_pref} ->
        # Success - replicate the new state and return success
        current_state = Agent.get(via_tuple(), & &1)
        replicate_state(current_state)
        {:ok, updated_pref}

      {:error, reason} ->
        # Error - no replication needed
        {:error, reason}
    end
  end

  # ==============================================================================
  # REPLICATION FUNCTIONS
  # ==============================================================================

  defp try_recover_state do
    other_nodes = Node.list()

    if length(other_nodes) > 0 do
      recovered_state = Enum.find_value(other_nodes, fn node ->
        try do
          case :rpc.call(node, __MODULE__, :get_replicated_state, [], 5000) do
            {:ok, state} when map_size(state) > 0 ->
              state
            _ -> nil
          end
        rescue
          _ -> nil
        end
      end)

      if recovered_state do
        recovered_state
      else
        # try local ETS as fallback
        case :ets.lookup(:preference_replicas, :preferences) do
          [{:preferences, state}] when map_size(state) > 0 ->
            state
          _ ->
            nil
        end
      end
    else
      # no other nodes, try local ETS
      case :ets.lookup(:preference_replicas, :preferences) do
        [{:preferences, state}] when map_size(state) > 0 ->
          state
        _ ->
          nil
      end
    end
  end

  # Replicate state to all other nodes
  defp replicate_state(state) do
    other_nodes = Node.list()

    if length(other_nodes) > 0 do
      # Store locally
      :ets.insert(:preference_replicas, {:preferences, state})

      # Replicate to other nodes asynchronously
      Enum.each(other_nodes, fn node ->
        Task.start(fn ->
          try do
            :rpc.call(node, __MODULE__, :store_replicated_state, [state], 5000)
          rescue
            error ->
              IO.puts("failed to replicate preference to #{node}: #{inspect(error)}")
          end
        end)
      end)
    else
      # No other nodes, just store locally
      :ets.insert(:preference_replicas, {:preferences, state})
    end
  end

  # ==============================================================================
  # RPC FUNCTIONS (called by other nodes)
  # ==============================================================================

  def get_replicated_state do
    case :ets.lookup(:preference_replicas, :preferences) do
      [{:preferences, state}] -> {:ok, state}
      [] -> {:ok, %{}}
    end
  end

  def store_replicated_state(state) do
    :ets.insert(:preference_replicas, {:preferences, state})
    :ok
  end

end
