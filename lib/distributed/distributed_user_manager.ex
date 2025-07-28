defmodule ElixirFastCharge.DistributedUserManager do
  @moduledoc """
  Manager para operaciones distribuidas con usuarios.
  Interfaz principal para interactuar con usuarios distribuidos en el cluster.
  """
  require Logger

  # API PRINCIPAL

  def create_user(username, password, metadata \\ %{}) do
    # Verificar si el usuario ya existe en el cluster
    case get_user(username) do
      {:ok, _existing_user} ->
        {:error, :username_taken}

      {:error, :not_found} ->
        # Usuario no existe, crear nuevo
        user_data = %{
          username: username,
          password: password,
          metadata: metadata
        }

        case ElixirFastCharge.HordeSupervisor.start_child({ElixirFastCharge.DistributedUser, user_data}) do
          {:ok, pid} ->
            Logger.info("👤 Usuario #{username} creado exitosamente en cluster")
            {:ok, pid}

          {:error, reason} ->
            Logger.error("Error creando usuario #{username}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  def get_user(username) do
    ElixirFastCharge.DistributedUser.get_user(username)
  end

  def authenticate_user(username, password) do
    ElixirFastCharge.DistributedUser.authenticate(username, password)
  end

  def update_user(username, updates) do
    ElixirFastCharge.DistributedUser.update_user(username, updates)
  end

  def list_all_users() do
    case ElixirFastCharge.HordeRegistry.list_all() do
      processes when is_list(processes) ->
        processes
        |> Enum.filter(fn {{type, _id}, _pid, _value} -> type == :user end)
        |> Enum.map(fn {{:user, username}, pid, _value} ->
          case ElixirFastCharge.DistributedUser.get_user(username) do
            {:ok, user} -> user
            {:error, _} ->
              %{username: username, status: :error, pid: inspect(pid)}
          end
        end)
        |> Enum.reject(fn user -> user.status == :error end)

      _ -> []
    end
  end

  def count_users() do
    case ElixirFastCharge.HordeRegistry.list_all() do
      processes when is_list(processes) ->
        user_count = processes
        |> Enum.count(fn {{type, _id}, _pid, _value} -> type == :user end)

        %{
          total_users: user_count,
          node: Node.self(),
          cluster_nodes: [Node.self() | Node.list()]
        }

      _ ->
        %{
          total_users: 0,
          node: Node.self(),
          cluster_nodes: [Node.self() | Node.list()]
        }
    end
  end

  def get_user_info(username) do
    ElixirFastCharge.DistributedUser.get_info(username)
  end

  def list_users_by_node() do
    case ElixirFastCharge.HordeRegistry.list_all() do
      processes when is_list(processes) ->
        user_processes = processes
        |> Enum.filter(fn {{type, _id}, _pid, _value} -> type == :user end)

        user_processes
        |> Enum.group_by(fn {{:user, _username}, pid, _value} -> node(pid) end)
        |> Enum.map(fn {node, user_list} ->
          {Atom.to_string(node), length(user_list)}
        end)
        |> Map.new()

      _ -> %{}
    end
  end

  def get_cluster_stats() do
    all_nodes = [Node.self() | Node.list()]
    user_count = count_users()
    user_distribution = list_users_by_node()

    %{
      node: Atom.to_string(Node.self()),
      cluster_nodes: Enum.map(all_nodes, &Atom.to_string/1),
      total_users: user_count.total_users,
      user_distribution: user_distribution,
      distributed: true
    }
  end

  # FUNCIONES DE UTILIDAD

  def username_exists?(username) do
    case get_user(username) do
      {:ok, _user} -> true
      {:error, :not_found} -> false
    end
  end

  def delete_user(username) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:user, username}) do
      [{pid, _}] ->
        case ElixirFastCharge.HordeSupervisor.terminate_child(pid) do
          :ok ->
            Logger.info("👤 Usuario #{username} eliminado del cluster")
            {:ok, :deleted}

          {:error, reason} ->
            Logger.error("Error eliminando usuario #{username}: #{inspect(reason)}")
            {:error, reason}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def list_active_users() do
    list_all_users()
    |> Enum.filter(fn user -> user.status == :active end)
  end

  def get_users_by_status(status) do
    list_all_users()
    |> Enum.filter(fn user -> user.status == status end)
  end

  # FUNCIONES DE DIAGNÓSTICO

  def cluster_health() do
    all_nodes = [Node.self() | Node.list()]
    user_stats = get_cluster_stats()

    %{
      cluster_status: if(length(all_nodes) > 1, do: "clustered", else: "standalone"),
      total_nodes: length(all_nodes),
      connected_nodes: Enum.map(Node.list(), &Atom.to_string/1),
      current_node: Atom.to_string(Node.self()),
      user_stats: user_stats,
      timestamp: DateTime.utc_now()
    }
  end
end
