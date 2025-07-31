defmodule ElixirFastCharge.PreReservationMonitor do
  use GenServer
  require Logger

  @check_interval 3_000 # Check every 3 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("PreReservationMonitor started - monitoring PreReservationAgent")
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_pre_reservation_agent, state) do
    check_and_recreate_pre_reservation_agent()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_pre_reservation_agent, @check_interval)
  end

  defp check_and_recreate_pre_reservation_agent do
    case GenServer.whereis({:via, Horde.Registry, {ElixirFastCharge.DistributedStorageRegistry, ElixirFastCharge.Storage.PreReservationAgent}}) do
      nil ->
        # Process doesn't exist, check if we have replicated state
        has_replicated_state = check_for_replicated_state()

        if has_replicated_state do
          Logger.info("🔄 PreReservationAgent missing but state exists - recreating...")
          recreate_pre_reservation_agent()
        else
          Logger.debug("PreReservationAgent missing but no replicated state found")
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
          Logger.debug("PreReservationAgent is healthy: #{inspect(pid)} on #{node(pid)}")
        else
          Logger.warn("PreReservationAgent PID exists but process is dead - recreating...")
          recreate_pre_reservation_agent()
        end
    end
  end

  defp check_for_replicated_state do
    # Check all nodes for replicated pre-reservation state
    all_nodes = [Node.self() | Node.list()]

    Enum.any?(all_nodes, fn node ->
      try do
        case :rpc.call(node, :ets, :lookup, [:pre_reservation_replicas, :pre_reservations], 5000) do
          [{:pre_reservations, state}] when map_size(state) > 0 ->
            Logger.debug("Found replicated pre-reservation state on #{node} with #{map_size(state)} pre-reservations")
            true
          _ -> false
        end
      rescue
        _ -> false
      end
    end)
  end

  defp recreate_pre_reservation_agent do
    child_spec = {ElixirFastCharge.Storage.PreReservationAgent, []}

    case Horde.DynamicSupervisor.start_child(ElixirFastCharge.Finder, child_spec) do
      {:ok, pid} ->
        Logger.info("✅ PreReservationAgent recreated successfully: #{inspect(pid)} on #{node(pid)}")

      {:error, {:already_started, pid}} ->
        Logger.info("⚠️  PreReservationAgent already running: #{inspect(pid)} on #{node(pid)}")

      {:error, reason} ->
        Logger.error("❌ Failed to recreate PreReservationAgent: #{inspect(reason)}")
    end
  end
end
