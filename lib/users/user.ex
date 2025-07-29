defmodule ElixirFastCharge.User do
  use GenServer

  def start_link({username, password}) do
    GenServer.start_link(__MODULE__, {username, password})
  end

  def init({username, password}) do
    case Horde.Registry.register(ElixirFastCharge.UserRegistry, username, self()) do
      {:ok, _} ->
        IO.puts("Usuario '#{username}' registrado en nodo: #{node()}")

        initial_state = %{
          username: username,
          password: password,
          created_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now(),
          notifications: []
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

  def send_notification(user_pid, notification) do
    GenServer.call(user_pid, {:send_notification, notification})
  end

  def get_notifications(user_pid) do
    GenServer.call(user_pid, :get_notifications)
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

  def handle_call({:send_notification, notification}, _from, state) do
    new_state = %{state | notifications: [notification | state.notifications]}
    {:reply, :ok, new_state}
  end

  def handle_call(:get_notifications, _from, state) do
    {:reply, state.notifications, state}
  end
end
