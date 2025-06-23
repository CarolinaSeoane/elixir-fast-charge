defmodule ElixirFastCharge.UserDynamicSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def create_user(username, password) do
    case Registry.lookup(ElixirFastCharge.UserRegistry, username) do
      [{_existing_pid, _}] ->
        {:error, :username_taken}

      [] ->
        child_spec = %{
          id: {ElixirFastCharge.User, username},
          start: {ElixirFastCharge.User, :start_link, [{username, password}]},
          restart: :temporary,
          shutdown: 5000,
          type: :worker
        }

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, user_pid} ->
            case Registry.register(ElixirFastCharge.UserRegistry, username, user_pid) do
              {:ok, _} ->
                {:ok, user_pid}

              {:error, {:already_registered, _existing_pid}} ->
                DynamicSupervisor.terminate_child(__MODULE__, user_pid)
                {:error, :username_taken}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def get_user(username) do
    case Registry.lookup(ElixirFastCharge.UserRegistry, username) do
      [{_supervisor_pid, user_pid}] -> {:ok, user_pid}
      [] -> {:error, :not_found}
    end
  end

  def list_users do
    # Returns username -> user_pid mapping
    Registry.select(ElixirFastCharge.UserRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3"}}]}])
    |> Enum.into(%{})
  end

  def delete_user(username) do
    case get_user(username) do
      {:ok, user_pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, user_pid)
      {:error, :not_found} ->
        {:error, :user_not_found}
    end
  end

  def start_child(foo, bar, baz) do
    spec = %{id: ElixirFastCharge.User, start: {ElixirFastCharge.User, :start_link, [foo, bar, baz]}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
