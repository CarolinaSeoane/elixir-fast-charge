defmodule ElixirFastCharge.PreferenceMonitor do
  use GenServer
  require Logger

  @check_interval 3_000 # Check every 3 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("PreferenceMonitor started - monitoring PreferenceAgent")
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_preference_agent, state) do
    check_and_recreate_preference_agent()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_preference_agent, @check_interval)
  end

  defp check_and_recreate_preference_agent do
    case GenServer.whereis({:via, Horde.Registry, {ElixirFastCharge.DistributedStorageRegistry, ElixirFastCharge.Preferences}}) do
      nil ->
        # Process doesn't exist, check if we have replicated state
        has_replicated_state = check_for_replicated_state()

        if has_replicated_state do
          Logger.info("🔄 PreferenceAgent missing but state exists - recreating...")
          recreate_preference_agent()
        else
          Logger.debug("PreferenceAgent missing but no replicated state found")
        end

      pid when is_pid(pid) ->
        # Process exists, check if it's alive (handle local vs remote PIDs)
        is_alive = if node(pid) == Node.self() do
          # Local PID - use Process.alive?
          Process.alive?(pid)
        else
          # Remote PID - use RPC
          try do
            :rpc.call(node(pid), Process, :alive?, [pid], 5000) == true
          rescue
            _ -> false
          end
        end

        if is_alive do
          Logger.debug("PreferenceAgent is healthy: #{inspect(pid)} on #{node(pid)}")
        else
          Logger.warn("PreferenceAgent PID exists but process is dead - recreating...")
          recreate_preference_agent()
        end
    end
  end

  defp check_for_replicated_state do
    # Check all nodes for replicated preference state
    all_nodes = [Node.self() | Node.list()]

    Enum.any?(all_nodes, fn node ->
      try do
        case :rpc.call(node, :ets, :lookup, [:preference_replicas, :preferences], 5000) do
          [{:preferences, state}] when map_size(state) > 0 ->
            Logger.debug("Found replicated preference state on #{node} with #{map_size(state)} preferences")
            true
          _ -> false
        end
      rescue
        _ -> false
      end
    end)
  end

  defp recreate_preference_agent do
    child_spec = {ElixirFastCharge.Preferences, %{}}

    case Horde.DynamicSupervisor.start_child(ElixirFastCharge.Finder, child_spec) do
      {:ok, pid} ->
        Logger.info("PreferenceAgent recreated successfully: #{inspect(pid)} on #{node(pid)}")

      {:error, {:already_started, pid}} ->
        Logger.info("PreferenceAgent already running: #{inspect(pid)} on #{node(pid)}")

      {:error, reason} ->
        Logger.error("Failed to recreate PreferenceAgent: #{inspect(reason)}")
    end
  end
end
