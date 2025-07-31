defmodule ElixirFastCharge.UserMonitor do
  use GenServer
  require Logger

  @check_interval 5_000  # Check every 5 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("UserMonitor iniciado - monitoreando procesos de usuarios")
    schedule_check()
    {:ok, %{monitored_users: %{}}}
  end

  @impl true
  def handle_info(:check_users, state) do
    new_state = check_and_restore_users(state)
    schedule_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.warn("Proceso monitoreado murió: #{inspect(pid)}, razón: #{inspect(reason)}")
    # Buscar qué usuario era y recrearlo
    case find_user_by_pid(state.monitored_users, pid) do
      {:ok, username} ->
        Logger.info("Recreando usuario #{username} después de fallo...")
        recreate_user_async(username)
        new_monitored = Map.delete(state.monitored_users, username)
        {:noreply, %{state | monitored_users: new_monitored}}
      :not_found ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("UserMonitor recibió mensaje inesperado: #{inspect(msg)}")
    {:noreply, state}
  end

  # Funciones privadas

  defp schedule_check do
    Process.send_after(self(), :check_users, @check_interval)
  end

  defp check_and_restore_users(state) do
    # Obtener todos los usuarios que deberían existir
    all_replicas = get_all_user_replicas()
    current_users = get_current_users()

    Logger.debug("UserMonitor: #{length(all_replicas)} replicas, #{map_size(current_users)} usuarios activos")

    # Encontrar usuarios que tienen replicas pero no están activos
    missing_users = find_missing_users(all_replicas, current_users)

    if length(missing_users) > 0 do
      Logger.info("Encontrados #{length(missing_users)} usuarios perdidos: #{inspect(missing_users)}")

      # Recrear usuarios perdidos
      Enum.each(missing_users, fn username ->
        recreate_user_async(username)
      end)
    end

    # Actualizar monitoreo de usuarios activos
    new_monitored = setup_monitoring(current_users, state.monitored_users)

    %{state | monitored_users: new_monitored}
  end

    defp get_all_user_replicas do
    # Buscar replicas en TODOS los nodos, no solo localmente
    all_nodes = [Node.self() | Node.list()]

    all_replicas = Enum.flat_map(all_nodes, fn node ->
      try do
        case :rpc.call(node, :ets, :whereis, [:user_replicas], 3000) do
          :undefined -> []
          _ ->
            replicas = :rpc.call(node, :ets, :tab2list, [:user_replicas], 3000)
            case replicas do
              list when is_list(list) ->
                Enum.map(list, fn {username, _state} -> username end)
              _ -> []
            end
        end
      rescue
        _error -> []
      end
    end)

    Enum.uniq(all_replicas)
  end

  defp get_current_users do
    try do
      ElixirFastCharge.UserDynamicSupervisor.list_users()
    rescue
      _ -> %{}
    end
  end

  defp find_missing_users(all_replicas, current_users) do
    current_usernames = Map.keys(current_users)
    Enum.filter(all_replicas, fn username ->
      not Enum.member?(current_usernames, username)
    end)
  end

  defp setup_monitoring(current_users, old_monitored) do
    # Cancelar monitoreo de usuarios que ya no existen
    Enum.each(old_monitored, fn {username, ref} ->
      if not Map.has_key?(current_users, username) do
        Process.demonitor(ref, [:flush])
      end
    end)

    # Configurar monitoreo para usuarios actuales
    Enum.reduce(current_users, %{}, fn {username, pid}, acc ->
      if Map.has_key?(old_monitored, username) do
        # Ya está siendo monitoreado
        Map.put(acc, username, old_monitored[username])
      else
        # Nuevo usuario, configurar monitoreo
        ref = Process.monitor(pid)
        Logger.debug("Monitoreando usuario #{username} (PID: #{inspect(pid)})")
        Map.put(acc, username, ref)
      end
    end)
  end

  defp find_user_by_pid(monitored_users, target_pid) do
    case Enum.find(monitored_users, fn {_username, _ref} ->
      # Necesitaríamos una forma de mapear ref a PID, pero esto es complejo
      # Por simplicidad, usaremos el check periódico
      false
    end) do
      {username, _ref} -> {:ok, username}
      nil -> :not_found
    end
  end

  defp recreate_user_async(username) do
    Task.start(fn ->
      try do
        Logger.info("🔄 Intentando recrear usuario #{username}...")

        # Intentar recrear con password dummy (será recuperado del estado)
        case ElixirFastCharge.UserDynamicSupervisor.create_user(username, "recovered") do
          {:ok, new_pid} ->
            Logger.info("✅ Usuario #{username} recreado exitosamente en #{node(new_pid)}")
          {:error, :username_taken} ->
            Logger.info("ℹ️  Usuario #{username} ya existe (recuperado en otro nodo)")
          {:error, reason} ->
            Logger.error("❌ Error recreando usuario #{username}: #{inspect(reason)}")
        end
      rescue
        error ->
          Logger.error("❌ Excepción recreando usuario #{username}: #{inspect(error)}")
      end
    end)
  end

  # API Pública

  def force_check do
    GenServer.cast(__MODULE__, :force_check)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @impl true
  def handle_cast(:force_check, state) do
    new_state = check_and_restore_users(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      monitored_users: Map.keys(state.monitored_users),
      monitored_count: map_size(state.monitored_users)
    }
    {:reply, status, state}
  end
end
