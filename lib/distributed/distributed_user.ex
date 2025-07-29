defmodule ElixirFastCharge.DistributedUser do
  @moduledoc """
  GenServer distribuido para manejar usuarios individuales.
  Se registra en Horde Registry para distribución automática.
  """
  use GenServer
  require Logger

  # API

  def start_link(user_data) do
    GenServer.start_link(__MODULE__, user_data,
      name: {:via, Horde.Registry, {ElixirFastCharge.HordeRegistry, {:user, user_data.username}}}
    )
  end

  def get_user(username) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:user, username}) do
      [{pid, _}] -> GenServer.call(pid, :get_user)
      [] -> {:error, :not_found}
    end
  end

  def authenticate(username, password) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:user, username}) do
      [{pid, _}] -> GenServer.call(pid, {:authenticate, password})
      [] -> {:error, :user_not_found}
    end
  end

  def update_user(username, updates) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:user, username}) do
      [{pid, _}] -> GenServer.call(pid, {:update_user, updates})
      [] -> {:error, :not_found}
    end
  end

  def get_info(username) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:user, username}) do
      [{pid, _}] -> GenServer.call(pid, :get_info)
      [] -> {:error, :not_found}
    end
  end

  def sync_user(user_data) do
    GenServer.cast(__MODULE__, {:sync_user, user_data})
  end

  # GenServer Callbacks

  @impl true
  def init(user_data) do
    # Hash de la contraseña para seguridad
    hashed_password = :crypto.hash(:sha256, user_data.password) |> Base.encode64()

    # Extraer mail de metadata para ponerlo como campo principal
    metadata = Map.get(user_data, :metadata, %{})
    mail = Map.get(metadata, :mail, "")

    user = %{
      username: user_data.username,
      mail: mail, # Campo principal para el email
      password_hash: hashed_password,
      status: :active,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      current_node: Node.self(),
      created_by_node: Node.self(),
      metadata: metadata
    }

    Logger.info("👤 Usuario #{user.username} iniciado en nodo #{Node.self()}")

    {:ok, user}
  end

  @impl true
  def handle_call(:get_user, _from, user) do
    # No devolver el hash de contraseña en la respuesta
    safe_user = Map.drop(user, [:password_hash])
    {:reply, {:ok, safe_user}, user}
  end

  @impl true
  def handle_call({:authenticate, password}, _from, user) do
    hashed_input = :crypto.hash(:sha256, password) |> Base.encode64()

    if hashed_input == user.password_hash do
      {:reply, {:ok, :authenticated}, user}
    else
      {:reply, {:error, :invalid_password}, user}
    end
  end

  @impl true
  def handle_call({:update_user, updates}, _from, user) do
    # Actualizar campos permitidos
    allowed_updates = Map.take(updates, [:metadata, :status])
    updated_user = user
    |> Map.merge(allowed_updates)
    |> Map.put(:updated_at, DateTime.utc_now())
    |> Map.put(:current_node, Node.self())

    Logger.info("👤 Usuario #{user.username} actualizado en nodo #{Node.self()}")

    {:reply, {:ok, updated_user}, updated_user}
  end

  @impl true
  def handle_call(:get_info, _from, user) do
    info = %{
      username: user.username,
      mail: user.mail, # Incluir email en la información detallada
      status: user.status,
      created_at: user.created_at,
      updated_at: user.updated_at,
      current_node: user.current_node,
      created_by_node: user.created_by_node,
      node_info: %{
        pid: self(),
        node: Node.self()
      }
    }

    {:reply, {:ok, info}, user}
  end

  @impl true
  def handle_cast({:sync_user, user_data}, state) do
    Logger.info("Sincronizando usuario \\#{user_data.username} en nodo \\#{Node.self()}")

    # Lógica para actualizar el estado local con user_data
    # ...

    # Enviar el estado actualizado a otros nodos
    Node.list()
    |> Enum.each(fn node ->
      Logger.info("Enviando actualización de usuario a nodo \\#{node}")
      Node.spawn(node, __MODULE__, :sync_user, [user_data])
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, user) do
    Logger.warning("Usuario #{user.username} recibió mensaje inesperado: #{inspect(msg)}")
    {:noreply, user}
  end
end
