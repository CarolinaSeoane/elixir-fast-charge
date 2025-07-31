defmodule ElixirFastCharge.UserDynamicSupervisor do

  def create_user(username, password) do
    case Horde.Registry.lookup(ElixirFastCharge.UserRegistry, username) do
      [{_existing_pid, _}] ->
        {:error, :username_taken}

      [] ->
        child_spec = %{
          id: {ElixirFastCharge.User, username},
          start: {ElixirFastCharge.User, :start_link, [{username, password}]},
          restart: :permanent,
          shutdown: 5000,
          type: :worker
        }

        # Usa Horde.DynamicSupervisor en lugar de DynamicSupervisor normal
        case Horde.DynamicSupervisor.start_child(ElixirFastCharge.UserDynamicSupervisor, child_spec) do
          {:ok, user_pid} ->
            IO.puts("Usuario '#{username}' creado en nodo: #{node(user_pid)}")
            {:ok, user_pid}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def get_user(username) do
    case Horde.Registry.lookup(ElixirFastCharge.UserRegistry, username) do
      [{user_pid, _}] -> {:ok, user_pid}
      [] -> {:error, :not_found}
    end
  end

  def list_users do
    Horde.Registry.select(ElixirFastCharge.UserRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.into(%{})
  end

end
