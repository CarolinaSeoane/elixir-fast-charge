defmodule ElixirFastCharge.User do
  use GenServer

  def start_link({username, password}) do
    GenServer.start_link(__MODULE__, {username, password})
  end

  # @impl true
  def init({username, password}) do
    initial_state = %{
      username: username,
      password: password,
      created_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now()
    }
    IO.puts("User #{username} initialized")
    {:ok, initial_state}
  end

  def get_info(user_pid) do
    GenServer.call(user_pid, :get_info)
  end

  def healthcheck(user_pid) do
    GenServer.call(user_pid, :healthcheck)
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
end
