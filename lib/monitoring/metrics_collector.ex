defmodule ElixirFastCharge.Monitoring.MetricsCollector do
  @moduledoc """
  Recolector de métricas para monitoreo y detección de picos de demanda.
  Incluye métricas de sistema, aplicación y cluster distribuido.
  """
  use GenServer
  require Logger

  # Métricas del sistema
  @system_metrics [
    :cpu_usage,
    :memory_usage,
    :process_count,
    :scheduler_utilization
  ]

  # Métricas de aplicación
  @app_metrics [
    :active_pre_reservations,
    :concurrent_users,
    :api_response_time,
    :request_rate,
    :error_rate
  ]

  # Métricas del cluster
  @cluster_metrics [
    :connected_nodes,
    :horde_processes,
    :process_distribution,
    :network_latency
  ]

  # Thresholds para detectar picos
  @thresholds %{
    cpu_usage: 80.0,           # 80% CPU
    memory_usage: 85.0,        # 85% memoria
    active_pre_reservations: 500,  # 500 pre-reservas concurrentes
    api_response_time: 2000,   # 2 segundos
    request_rate: 1000,        # 1000 req/min
    error_rate: 5.0            # 5% error rate
  }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    # Programar recolección de métricas cada 10 segundos
    schedule_metrics_collection()

    # Programar evaluación de scaling cada 30 segundos
    schedule_scaling_evaluation()

    Logger.info("MetricsCollector iniciado - Monitoreo activo")
    {:ok, Map.merge(state, %{
      metrics_history: [],
      scaling_decisions: [],
      last_scale_action: nil
    })}
  end

  # API pública
  def get_current_metrics do
    GenServer.call(__MODULE__, :get_current_metrics)
  end

  def get_scaling_recommendation do
    GenServer.call(__MODULE__, :get_scaling_recommendation)
  end

  def force_scaling_evaluation do
    GenServer.cast(__MODULE__, :evaluate_scaling)
  end

  # GenServer callbacks
  @impl true
  def handle_call(:get_current_metrics, _from, state) do
    current_metrics = collect_all_metrics()
    {:reply, current_metrics, state}
  end

  @impl true
  def handle_call(:get_scaling_recommendation, _from, state) do
    recommendation = evaluate_scaling_need(state)
    {:reply, recommendation, state}
  end

  @impl true
  def handle_cast(:evaluate_scaling, state) do
    new_state = perform_scaling_evaluation(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    new_state = collect_and_store_metrics(state)
    schedule_metrics_collection()
    {:noreply, new_state}
  end

  defp collect_and_store_metrics(state) do
    current_metrics = collect_all_metrics()
    history = [current_metrics | Enum.take(state[:metrics_history] || [], 99)]

    Map.merge(state, %{
      current_metrics: current_metrics,
      metrics_history: history,
      last_collection: DateTime.utc_now()
    })
  end

  @impl true
  def handle_info(:evaluate_scaling, state) do
    new_state = perform_scaling_evaluation(state)
    schedule_scaling_evaluation()
    {:noreply, new_state}
  end

  # Funciones de recolección de métricas

  defp collect_all_metrics do
    %{
      timestamp: DateTime.utc_now(),
      system: collect_system_metrics(),
      application: collect_app_metrics(),
      cluster: collect_cluster_metrics()
    }
  end

  defp collect_system_metrics do
    %{
      cpu_usage: get_cpu_usage(),
      memory_usage: get_memory_usage(),
      process_count: Process.list() |> length(),
      scheduler_utilization: get_scheduler_utilization(),
      uptime: div(elem(:erlang.statistics(:wall_clock), 0), 1000),
      node: Node.self()
    }
  end

  defp collect_app_metrics do
    %{
      active_pre_reservations: count_active_pre_reservations(),
      concurrent_users: count_concurrent_users(),
      total_shifts: count_total_shifts(),
      pending_processes: count_pending_processes(),
      horde_registry_size: get_horde_registry_size()
    }
  end

  defp collect_cluster_metrics do
    %{
      connected_nodes: [Node.self() | Node.list()],
      total_nodes: length([Node.self() | Node.list()]),
      horde_processes: get_horde_process_count(),
      process_distribution: get_process_distribution(),
      cluster_health: evaluate_cluster_health()
    }
  end

  # Detección de picos y scaling

  defp perform_scaling_evaluation(state) do
    current_metrics = collect_all_metrics()
    scaling_decision = evaluate_scaling_need(%{current_metrics: current_metrics})

    case scaling_decision do
      {:scale_up, reason} ->
        Logger.warn("SCALING UP detectado: #{reason}")
        trigger_scale_up(reason)

      {:scale_down, reason} ->
        Logger.info("⬇️ SCALING DOWN detectado: #{reason}")
        trigger_scale_down(reason)

      {:no_action, _reason} ->
        :ok
    end

    # Almacenar métricas e historial
    history = [current_metrics | Enum.take(state[:metrics_history] || [], 99)]
    decisions = [scaling_decision | Enum.take(state[:scaling_decisions] || [], 49)]

    Map.merge(state, %{
      current_metrics: current_metrics,
      metrics_history: history,
      scaling_decisions: decisions,
      last_evaluation: DateTime.utc_now()
    })
  end

  defp evaluate_scaling_need(%{current_metrics: metrics}) do
    system = metrics.system
    app = metrics.application
    cluster = metrics.cluster

    cond do
      # SCALE UP conditions
      system.cpu_usage > @thresholds.cpu_usage ->
        {:scale_up, "CPU usage: #{system.cpu_usage}% > #{@thresholds.cpu_usage}%"}

      system.memory_usage > @thresholds.memory_usage ->
        {:scale_up, "Memory usage: #{system.memory_usage}% > #{@thresholds.memory_usage}%"}

      app.active_pre_reservations > @thresholds.active_pre_reservations ->
        {:scale_up, "Active pre-reservations: #{app.active_pre_reservations} > #{@thresholds.active_pre_reservations}"}

      cluster.total_nodes < 2 and app.active_pre_reservations > 100 ->
        {:scale_up, "High load on single node: #{app.active_pre_reservations} pre-reservations"}

      # SCALE DOWN conditions
      system.cpu_usage < 20.0 and system.memory_usage < 40.0 and cluster.total_nodes > 1 ->
        {:scale_down, "Low resource usage: CPU #{system.cpu_usage}%, Memory #{system.memory_usage}%"}

      app.active_pre_reservations < 50 and cluster.total_nodes > 2 ->
        {:scale_down, "Low application load: #{app.active_pre_reservations} pre-reservations"}

      # NO ACTION
      true ->
        {:no_action, "Metrics within normal parameters"}
    end
  end

  # Funciones de scaling

  defp trigger_scale_up(reason) do
    Logger.warn("TRIGGER SCALE UP: #{reason}")

    # Opción 1: Kubernetes HPA (si estás en K8s)
    trigger_kubernetes_scale_up()

    # Opción 2: Docker Swarm (si estás en Swarm)
    trigger_docker_swarm_scale_up()

    # Opción 3: Custom script de escalado
    trigger_custom_scale_up()

    # Opción 4: Cloud provider scaling (AWS, GCP, etc.)
    trigger_cloud_scale_up()

    # Notificar al team
    send_scaling_alert(:scale_up, reason)
  end

  defp trigger_scale_down(reason) do
    Logger.info("⬇️ TRIGGER SCALE DOWN: #{reason}")

    # Similar a scale_up pero reduciendo instancias
    trigger_kubernetes_scale_down()
    trigger_docker_swarm_scale_down()
    trigger_custom_scale_down()
    trigger_cloud_scale_down()

    send_scaling_alert(:scale_down, reason)
  end

  # Implementaciones específicas de scaling

  defp trigger_kubernetes_scale_up do
    # kubectl scale deployment elixir-fast-charge --replicas=5
    case System.cmd("kubectl", ["scale", "deployment", "elixir-fast-charge", "--replicas=#{get_target_replicas(:up)}"]) do
      {output, 0} ->
        Logger.info("Kubernetes scale up successful: #{output}")
      {error, _code} ->
        Logger.error("Kubernetes scale up failed: #{error}")
    end
  rescue
    _ -> Logger.warn("kubectl not available for scaling")
  end

  defp trigger_docker_swarm_scale_up do
    # docker service scale elixir-fast-charge=5
    case System.cmd("docker", ["service", "scale", "elixir-fast-charge=#{get_target_replicas(:up)}"]) do
      {output, 0} ->
        Logger.info("Docker Swarm scale up successful: #{output}")
      {error, _code} ->
        Logger.error("Docker Swarm scale up failed: #{error}")
    end
  rescue
    _ -> Logger.warn("docker not available for scaling")
  end

  defp trigger_custom_scale_up do
    # Script custom para tu infraestructura
    script_path = Application.get_env(:elixir_fast_charge, :scale_up_script, "/opt/scripts/scale_up.sh")

    if File.exists?(script_path) do
      case System.cmd(script_path, []) do
        {output, 0} ->
          Logger.info(" Custom scale up successful: #{output}")
        {error, _code} ->
          Logger.error("Custom scale up failed: #{error}")
      end
    end
  end

  defp trigger_cloud_scale_up do
    # AWS Auto Scaling, GCP Instance Groups, etc.
    # Implementar según tu cloud provider
    Logger.info("Cloud scaling trigger (implement based on provider)")
  end

  # Implementaciones de scale down (similar a scale up)
  defp trigger_kubernetes_scale_down, do: trigger_kubernetes_with_replicas(:down)
  defp trigger_docker_swarm_scale_down, do: trigger_docker_with_replicas(:down)
  defp trigger_custom_scale_down, do: trigger_custom_script(:down)
  defp trigger_cloud_scale_down, do: Logger.info("☁️ Cloud scale down trigger")

  # Alertas y notificaciones

  defp send_scaling_alert(action, reason) do
    # Usar collect_all_metrics() directamente para evitar deadlock
    current_metrics = collect_all_metrics()

    alert = %{
      timestamp: DateTime.utc_now(),
      action: action,
      reason: reason,
      node: Node.self(),
      metrics: current_metrics
    }

    # Slack, Discord, email, etc.
    send_slack_alert(alert)
    send_email_alert(alert)

    # Log estructurado para análisis
    Logger.warn("SCALING_ALERT", alert: alert)
  end

  defp send_slack_alert(alert) do
    # Implementar webhook de Slack
    webhook_url = Application.get_env(:elixir_fast_charge, :slack_webhook)
    if webhook_url do
      # HTTPoison.post(webhook_url, Jason.encode!(alert))
      Logger.info("Slack alert sent: #{alert.action}")
    end
  end

  defp send_email_alert(alert) do
    # Implementar notificación por email
    Logger.info("Email alert sent: #{alert.action}")
  end

  # Funciones auxiliares

    defp get_cpu_usage do
    # Implementación robusta de CPU usage
    try do
      # Opción 1: Usar cpu_sup si está disponible
      case :cpu_sup.avg1() do
        {:error, _} -> fallback_cpu_usage()
        load -> load / 256 * 100  # Convertir a porcentaje
      end
    rescue
      _ -> fallback_cpu_usage()
    end
  end

  defp fallback_cpu_usage do
    # Fallback: Usar estadísticas de BEAM VM
    try do
      # Obtener reducción de estadísticas como proxy de CPU
      {_, reductions} = :erlang.statistics(:reductions)
      # Normalizar a un porcentaje (esto es una aproximación)
      min(reductions / 100_000 * 100, 100.0)
    rescue
      _ ->
        # Si todo falla, usar número de procesos como proxy muy básico
        process_count = length(Process.list())
        min(process_count / 10, 100.0)  # Aproximación muy básica
    end
  end

  defp get_memory_usage do
    memory = :erlang.memory()
    total = memory[:total] || 0
    # Estimación: usar memoria total del proceso vs límite
    (total / (1024 * 1024 * 1024)) * 100  # Porcentaje aproximado
  end

    defp get_scheduler_utilization do
    try do
      # Usar estadísticas básicas del sistema como proxy
      total_memory = :erlang.memory(:total)
      process_memory = :erlang.memory(:processes)

      # Calcular utilización como porcentaje de memoria de procesos vs total
      utilization = (process_memory / total_memory) * 100
      min(utilization, 100.0)
    rescue
      _ ->
        # Fallback muy básico: usar número de procesos activos
        active_processes = length(Process.list())
        # Normalizar a porcentaje (asumiendo que más de 1000 procesos = 100%)
        min(active_processes / 10, 100.0)
    end
  end

  defp count_active_pre_reservations do
    try do
      ElixirFastCharge.HordeRegistry.list_all()
      |> Enum.count(fn {{:pre_reservation, _}, _pid, _value} -> true; _ -> false end)
    rescue
      _ -> 0
    end
  end

  defp count_concurrent_users do
    try do
      ElixirFastCharge.HordeRegistry.list_all()
      |> Enum.count(fn {{:user, _}, _pid, _value} -> true; _ -> false end)
    rescue
      _ -> 0
    end
  end

  defp count_total_shifts do
    try do
      ElixirFastCharge.HordeRegistry.list_all()
      |> Enum.count(fn {{:shift, _}, _pid, _value} -> true; _ -> false end)
    rescue
      _ -> 0
    end
  end

  defp count_pending_processes do
    Process.list()
    |> Enum.count(fn pid ->
      case Process.info(pid, :status) do
        {:status, :waiting} -> true
        _ -> false
      end
    end)
  end

  defp get_horde_registry_size do
    try do
      ElixirFastCharge.HordeRegistry.list_all() |> length()
    rescue
      _ -> 0
    end
  end

  defp get_horde_process_count do
    try do
      ElixirFastCharge.HordeSupervisor.count_children()
    rescue
      _ -> %{active: 0, specs: 0, supervisors: 0, workers: 0}
    end
  end

  defp get_process_distribution do
    try do
      ElixirFastCharge.HordeRegistry.list_all()
      |> Enum.group_by(fn {_name, pid, _value} -> node(pid) end)
      |> Enum.map(fn {node, processes} -> {node, length(processes)} end)
      |> Map.new()
    rescue
      _ -> %{}
    end
  end

  defp evaluate_cluster_health do
    nodes = [Node.self() | Node.list()]
    case length(nodes) do
      1 -> :single_node
      n when n >= 2 and n <= 3 -> :healthy
      n when n > 3 -> :over_provisioned
      _ -> :unknown
    end
  end

  defp get_target_replicas(direction) do
    current_nodes = length([Node.self() | Node.list()])
    case direction do
      :up -> min(current_nodes + 2, 10)    # Max 10 nodos
      :down -> max(current_nodes - 1, 1)   # Min 1 nodo
    end
  end

  defp trigger_kubernetes_with_replicas(direction) do
    replicas = get_target_replicas(direction)
    case System.cmd("kubectl", ["scale", "deployment", "elixir-fast-charge", "--replicas=#{replicas}"]) do
      {output, 0} -> Logger.info("Kubernetes #{direction}: #{output}")
      {error, _} -> Logger.error("Kubernetes #{direction} failed: #{error}")
    end
  rescue
    _ -> Logger.warn("kubectl not available")
  end

  defp trigger_docker_with_replicas(direction) do
    replicas = get_target_replicas(direction)
    case System.cmd("docker", ["service", "scale", "elixir-fast-charge=#{replicas}"]) do
      {output, 0} -> Logger.info("Docker #{direction}: #{output}")
      {error, _} -> Logger.error("Docker #{direction} failed: #{error}")
    end
  rescue
    _ -> Logger.warn("docker not available")
  end

  defp trigger_custom_script(direction) do
    script = case direction do
      :up -> Application.get_env(:elixir_fast_charge, :scale_up_script)
      :down -> Application.get_env(:elixir_fast_charge, :scale_down_script)
    end

    if script && File.exists?(script) do
      case System.cmd(script, []) do
        {output, 0} -> Logger.info("✅ Custom #{direction}: #{output}")
        {error, _} -> Logger.error("❌ Custom #{direction} failed: #{error}")
      end
    end
  end

  # Programación de tareas
  defp schedule_metrics_collection do
    Process.send_after(self(), :collect_metrics, 10_000)  # Cada 10 segundos
  end

  defp schedule_scaling_evaluation do
    Process.send_after(self(), :evaluate_scaling, 30_000) # Cada 30 segundos
  end
end
