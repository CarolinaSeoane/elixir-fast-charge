defmodule ElixirFastCharge.User do
  use GenServer

  def start_link({username, password}) do
    GenServer.start_link(__MODULE__, {username, password})
  end

  # @impl true
  def init({username, password}) do
    case Registry.register(ElixirFastCharge.UserRegistry, username, self()) do
      {:ok, _} ->

        initial_state = %{
          username: username,
          password: password,
          created_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now(),
          preferences: %{
            connector_type: nil,
            min_power: nil,
            max_power: nil,
            preferred_stations: []
          }
        }

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

  def get_preferences(user_pid) do
    GenServer.call(user_pid, :get_preferences)
  end

  def update_preferences(user_pid, new_preferences) do
    GenServer.call(user_pid, {:update_preferences, new_preferences})
  end

  # @impl true
  def handle_call(:get_info, _from, state) do
    public_info = %{
      username: state.username,
      created_at: state.created_at,
      last_activity: state.last_activity
    }

    {:reply, public_info, state}
  end

  # @impl true
  def handle_call(:healthcheck, _from, state) do
    new_state = %{state | last_activity: DateTime.utc_now()}
    {:reply, "User #{state.username} running", new_state}
  end

  # @impl true
  def handle_call(:get_preferences, _from, state) do
    {:reply, state.preferences, state}
  end

  # @impl true
  def handle_call({:update_preferences, new_preferences}, _from, state) do
    updated_preferences = Map.merge(state.preferences, new_preferences)
    new_state = %{state | preferences: updated_preferences}
    {:reply, {:ok, updated_preferences}, new_state}
  end
end
