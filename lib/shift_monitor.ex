defmodule ElixirFastCharge.ShiftMonitor do
  use GenServer
  require Logger

  @check_interval 3_000 # Check every 3 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("ShiftMonitor started - monitoring ShiftAgent")
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_shift_agent, state) do
    check_and_recreate_shift_agent()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_shift_agent, @check_interval)
  end

  defp check_and_recreate_shift_agent do
    case GenServer.whereis({:via, Horde.Registry, {ElixirFastCharge.DistributedStorageRegistry, ElixirFastCharge.Storage.ShiftAgent}}) do
      nil ->
        # Process doesn't exist, check if we have replicated state
        has_replicated_state = check_for_replicated_state()

        if has_replicated_state do
          Logger.info("ShiftAgent missing but state exists - recreating...")
          recreate_shift_agent()
        else
          Logger.debug("ShiftAgent missing but no replicated state found")
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
          Logger.debug("ShiftAgent is healthy: #{inspect(pid)} on #{node(pid)}")
        else
          Logger.warn("ShiftAgent PID exists but process is dead - recreating...")
          recreate_shift_agent()
        end
    end
  end

  defp check_for_replicated_state do
    # Check all nodes for replicated shift state
    all_nodes = [Node.self() | Node.list()]

    Enum.any?(all_nodes, fn node ->
      try do
        case :rpc.call(node, :ets, :lookup, [:shift_replicas, :shifts], 5000) do
          [{:shifts, state}] when map_size(state) > 0 ->
            Logger.debug("Found replicated shift state on #{node} with #{map_size(state)} shifts")
            true
          _ -> false
        end
      rescue
        _ -> false
      end
    end)
  end

  defp recreate_shift_agent do
    child_spec = {ElixirFastCharge.Storage.ShiftAgent, []}

    case Horde.DynamicSupervisor.start_child(ElixirFastCharge.Finder, child_spec) do
      {:ok, pid} ->
        Logger.info("ShiftAgent recreated successfully: #{inspect(pid)} on #{node(pid)}")

      {:error, {:already_started, pid}} ->
        Logger.info("ShiftAgent already running: #{inspect(pid)} on #{node(pid)}")

      {:error, reason} ->
        Logger.error("Failed to recreate ShiftAgent: #{inspect(reason)}")
    end
  end
end
