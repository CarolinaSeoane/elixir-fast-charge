defmodule ElixirFastCharge.User do
  use GenServer

  def start_link({username, password}) do
    GenServer.start_link(__MODULE__, {username, password})
  end

  def init({username, password}) do
    case Horde.Registry.register(ElixirFastCharge.UserRegistry, username, self()) do
      {:ok, _} ->
        # try to recover state from other nodes
        recovered_state = try_to_recover_state(username)

        initial_state = case recovered_state do
          nil ->
            IO.puts("#{username} is new. Creating process")
            %{
              username: username,
              password: password,
              created_at: DateTime.utc_now(),
              last_activity: DateTime.utc_now(),
              notifications: []
            }
          state ->
            IO.puts("Recovering state for #{username}")
            state
        end

        replicate_state(username, initial_state)

        {:ok, initial_state}

      {:error, {:already_registered, _}} ->
        {:stop, :username_taken}
    end
  end

  def get_info(user_pid) do
    GenServer.call(user_pid, :get_info)
  end

  def healthcheck(user_pid) do
    GenServer.call(user_pid, :healthcheck)
  end

  def send_notification(user_pid, notification) do
    GenServer.call(user_pid, {:send_notification, notification})
  end

  def get_notifications(user_pid) do
    GenServer.call(user_pid, :get_notifications)
  end

  def handle_call(:get_info, _from, state) do
    public_info = %{
      username: state.username,
      created_at: state.created_at,
      last_activity: state.last_activity
    }

    {:reply, public_info, state}
  end

  def handle_call(:healthcheck, _from, state) do
    new_state = %{state | last_activity: DateTime.utc_now()}

    # replicate state when state changes
    replicate_state(state.username, new_state)

    {:reply, "User #{state.username} running", new_state}
  end

  def handle_call({:send_notification, notification}, _from, state) do
    new_state = %{state | notifications: [notification | state.notifications]}

    # replicate state when state changes
    replicate_state(state.username, new_state)

    {:reply, :ok, new_state}
  end

  def handle_call(:get_notifications, _from, state) do
    {:reply, state.notifications, state}
  end

  # === replication ===

  # Recuperar estado desde otros nodos
  defp try_to_recover_state(username) do
    other_nodes = Node.list()

    # try other nodes
    recovered_state = if length(other_nodes) > 0 do
      Enum.find_value(other_nodes, fn node ->
        try do
          case :rpc.call(node, __MODULE__, :get_replicated_state, [username], 5000) do
            {:ok, state} ->
              IO.puts("recovered state from node #{node}")
              state
            {:error, _reason} -> nil
            _other -> nil
          end
        rescue
          _error -> nil
        end
      end)
    else
      nil
    end

    # try locally if other nodes failed / not found
    final_state = if recovered_state == nil do
      case get_replicated_state(username) do
        {:ok, local_state} ->
          IO.puts("state recovered locally")
          local_state
        {:error, _reason} ->
          nil
      end
    else
      recovered_state
    end
    final_state
  end

  # replicate state to other nodes
  defp replicate_state(username, state) do
    other_nodes = Node.list()
    if length(other_nodes) > 0 do
      IO.puts("replicating user state to other nodes")
    end

    Enum.each(other_nodes, fn node ->
      spawn(fn ->
        try do
          :rpc.call(node, __MODULE__, :store_replicated_state, [username, state], 3000)
        rescue
          _error -> :ok
        end
      end)
    end)
  end

  def get_replicated_state(username) do
    table_name = :user_replicas

    case :ets.whereis(table_name) do
      :undefined -> {:error, :no_table}
      _ ->
        case :ets.lookup(table_name, username) do
          [{^username, state}] -> {:ok, state}
          [] -> {:error, :not_found}
        end
    end
  end

  # store state from other nodes
  def store_replicated_state(username, state) do
    table_name = :user_replicas
    :ets.insert(table_name, {username, state})
    :ok
  end
end
