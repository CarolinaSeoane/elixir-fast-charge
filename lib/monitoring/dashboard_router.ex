defmodule ElixirFastCharge.Monitoring.DashboardRouter do
  @moduledoc """
  Router para dashboard de monitoreo en tiempo real.
  Expone métricas del sistema, aplicación y cluster distribuido.
  """
  use Plug.Router

  plug :match
  plug :dispatch

  # === MÉTRICAS EN TIEMPO REAL ===

  get "/metrics" do
    metrics = ElixirFastCharge.Monitoring.MetricsCollector.get_current_metrics()
    send_json_response(conn, 200, metrics)
  end

  get "/health" do
    health_status = %{
      status: "healthy",
      timestamp: DateTime.utc_now(),
      node: Node.self(),
      cluster_nodes: [Node.self() | Node.list()],
      uptime_seconds: div(elem(:erlang.statistics(:wall_clock), 0), 1000),
      version: Application.spec(:elixir_fast_charge, :vsn) || "unknown"
    }

    send_json_response(conn, 200, health_status)
  end

  # === SCALING ===

  get "/scaling/recommendation" do
    recommendation = ElixirFastCharge.Monitoring.MetricsCollector.get_scaling_recommendation()
    send_json_response(conn, 200, %{recommendation: recommendation})
  end

  post "/scaling/evaluate" do
    ElixirFastCharge.Monitoring.MetricsCollector.force_scaling_evaluation()
    send_json_response(conn, 200, %{
      message: "Scaling evaluation triggered",
      timestamp: DateTime.utc_now()
    })
  end

  # === CLUSTER INFO ===

  get "/cluster" do
    cluster_info = %{
      current_node: Node.self(),
      connected_nodes: Node.list(),
      total_nodes: length([Node.self() | Node.list()]),
      cluster_status: get_cluster_status(),
      horde_registry: get_horde_registry_info(),
      horde_supervisor: get_horde_supervisor_info()
    }

    send_json_response(conn, 200, cluster_info)
  end

  # === ALERTS ===

  get "/alerts" do
    current_metrics = ElixirFastCharge.Monitoring.MetricsCollector.get_current_metrics()
    alerts = generate_current_alerts(current_metrics)

    send_json_response(conn, 200, %{
      alerts: alerts,
      count: length(alerts),
      timestamp: DateTime.utc_now()
    })
  end

  # === DASHBOARD HTML ===

  get "/" do
    html_dashboard = generate_dashboard_html()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html_dashboard)
  end

  # === PROMETHEUS METRICS ===

  get "/prometheus" do
    prometheus_metrics = generate_prometheus_metrics()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, prometheus_metrics)
  end

  match _ do
    send_json_response(conn, 404, %{error: "Monitoring route not found"})
  end

  # === FUNCIONES AUXILIARES ===

  defp get_cluster_status do
    nodes = [Node.self() | Node.list()]
    case length(nodes) do
      1 -> "single_node"
      n when n >= 2 and n <= 5 -> "healthy"
      n when n > 5 -> "over_provisioned"
      _ -> "unknown"
    end
  end

  defp get_horde_registry_info do
    try do
      processes = ElixirFastCharge.HordeRegistry.list_all()
      process_types = Enum.group_by(processes, fn {name, _pid, _value} ->
        case name do
          {:shift, _} -> :shifts
          {:pre_reservation, _} -> :pre_reservations
          {:user, _} -> :users
          _ -> :other
        end
      end)

      %{
        total_processes: length(processes),
        shifts: length(process_types[:shifts] || []),
        pre_reservations: length(process_types[:pre_reservations] || []),
        users: length(process_types[:users] || []),
        other: length(process_types[:other] || [])
      }
    rescue
      _ -> %{error: "Horde Registry not available"}
    end
  end

  defp get_horde_supervisor_info do
    try do
      children_info = ElixirFastCharge.HordeSupervisor.count_children()
      cluster_info = ElixirFastCharge.HordeSupervisor.get_cluster_info()

      %{
        children: children_info,
        cluster: cluster_info
      }
    rescue
      _ -> %{error: "Horde Supervisor not available"}
    end
  end

  defp generate_current_alerts(metrics) do
    alerts = []
    system = metrics.system
    app = metrics.application
    cluster = metrics.cluster

    alerts =
      if system.cpu_usage > 80.0 do
        [%{
          type: :warning,
          category: :system,
          message: "High CPU usage: #{system.cpu_usage}%",
          threshold: 80.0,
          current_value: system.cpu_usage,
          timestamp: DateTime.utc_now()
        } | alerts]
      else
        alerts
      end

    alerts =
      if system.memory_usage > 85.0 do
        [%{
          type: :warning,
          category: :system,
          message: "High memory usage: #{system.memory_usage}%",
          threshold: 85.0,
          current_value: system.memory_usage,
          timestamp: DateTime.utc_now()
        } | alerts]
      else
        alerts
      end

    alerts =
      if app.active_pre_reservations > 500 do
        [%{
          type: :info,
          category: :application,
          message: "High pre-reservation load: #{app.active_pre_reservations} active",
          threshold: 500,
          current_value: app.active_pre_reservations,
          timestamp: DateTime.utc_now()
        } | alerts]
      else
        alerts
      end

    alerts =
      if cluster.total_nodes == 1 and app.active_pre_reservations > 100 do
        [%{
          type: :warning,
          category: :cluster,
          message: "Single node with high load: #{app.active_pre_reservations} pre-reservations",
          threshold: 100,
          current_value: app.active_pre_reservations,
          timestamp: DateTime.utc_now()
        } | alerts]
      else
        alerts
      end

    Enum.reverse(alerts)
  end

  defp generate_dashboard_html do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <title>ElixirFastCharge - Monitoring Dashboard</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f5f5f5; }
            .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
            .header { background: #2563eb; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
            .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
            .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            .metric { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
            .metric-label { font-weight: 500; color: #374151; }
            .metric-value { font-weight: bold; color: #1f2937; }
            .status-healthy { color: #10b981; }
            .status-warning { color: #f59e0b; }
            .status-error { color: #ef4444; }
            .refresh-btn { background: #2563eb; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; }
            .alert { padding: 10px; margin: 5px 0; border-radius: 4px; }
            .alert-warning { background: #fef3c7; border-left: 4px solid #f59e0b; }
            .alert-error { background: #fee2e2; border-left: 4px solid #ef4444; }
            .alert-info { background: #dbeafe; border-left: 4px solid #2563eb; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>ElixirFastCharge - Monitoring Dashboard</h1>
                <p>Sistema Distribuido de Reservas de Carga Rápida</p>
                                  <button class="refresh-btn" onclick="location.reload()">Refresh</button>
            </div>

            <div class="grid">
                <div class="card">
                    <h3>System Metrics</h3>
                    <div id="system-metrics">Loading...</div>
                </div>

                <div class="card">
                    <h3>Application Metrics</h3>
                    <div id="app-metrics">Loading...</div>
                </div>

                <div class="card">
                    <h3>Cluster Status</h3>
                    <div id="cluster-metrics">Loading...</div>
                </div>

                <div class="card">
                    <h3>Active Alerts</h3>
                    <div id="alerts">Loading...</div>
                </div>

                <div class="card">
                    <h3>Scaling Recommendation</h3>
                    <div id="scaling">Loading...</div>
                </div>

                <div class="card">
                                      <h3>Actions</h3>
                  <button class="refresh-btn" onclick="forceScalingEvaluation()">Force Scaling Evaluation</button>
                    <div id="action-result"></div>
                </div>
            </div>
        </div>

        <script>
            async function loadMetrics() {
                try {
                    const [metrics, alerts, scaling, cluster] = await Promise.all([
                        fetch('/monitoring/metrics').then(r => r.json()),
                        fetch('/monitoring/alerts').then(r => r.json()),
                        fetch('/monitoring/scaling/recommendation').then(r => r.json()),
                        fetch('/monitoring/cluster').then(r => r.json())
                    ]);

                    // System Metrics
                    document.getElementById('system-metrics').innerHTML = `
                        <div class="metric">
                            <span class="metric-label">CPU Usage:</span>
                            <span class="metric-value ${metrics.system.cpu_usage > 80 ? 'status-error' : 'status-healthy'}">${metrics.system.cpu_usage.toFixed(1)}%</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Memory Usage:</span>
                            <span class="metric-value ${metrics.system.memory_usage > 85 ? 'status-error' : 'status-healthy'}">${metrics.system.memory_usage.toFixed(1)}%</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Processes:</span>
                            <span class="metric-value">${metrics.system.process_count}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Uptime:</span>
                            <span class="metric-value">${Math.floor(metrics.system.uptime / 3600)}h ${Math.floor((metrics.system.uptime % 3600) / 60)}m</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Node:</span>
                            <span class="metric-value">${metrics.system.node}</span>
                        </div>
                    `;

                    // App Metrics
                    document.getElementById('app-metrics').innerHTML = `
                        <div class="metric">
                            <span class="metric-label">Active Pre-reservations:</span>
                            <span class="metric-value ${metrics.application.active_pre_reservations > 500 ? 'status-warning' : 'status-healthy'}">${metrics.application.active_pre_reservations}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Concurrent Users:</span>
                            <span class="metric-value">${metrics.application.concurrent_users}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Total Shifts:</span>
                            <span class="metric-value">${metrics.application.total_shifts}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Horde Registry Size:</span>
                            <span class="metric-value">${metrics.application.horde_registry_size}</span>
                        </div>
                    `;

                    // Cluster Metrics
                    document.getElementById('cluster-metrics').innerHTML = `
                        <div class="metric">
                            <span class="metric-label">Total Nodes:</span>
                            <span class="metric-value ${cluster.total_nodes > 1 ? 'status-healthy' : 'status-warning'}">${cluster.total_nodes}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Cluster Status:</span>
                            <span class="metric-value ${cluster.cluster_status === 'healthy' ? 'status-healthy' : 'status-warning'}">${cluster.cluster_status}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Connected Nodes:</span>
                            <span class="metric-value">${cluster.connected_nodes.join(', ') || 'None'}</span>
                        </div>
                    `;

                    // Alerts
                    const alertsHtml = alerts.alerts.length > 0
                        ? alerts.alerts.map(alert => `
                            <div class="alert alert-${alert.type}">
                                <strong>${alert.category.toUpperCase()}:</strong> ${alert.message}
                            </div>
                        `).join('')
                        : '<div class="status-healthy">No active alerts</div>';
                    document.getElementById('alerts').innerHTML = alertsHtml;

                    // Scaling
                    const scalingAction = scaling.recommendation[0];
                    const scalingReason = scaling.recommendation[1] || 'No scaling needed';
                    const scalingClass = scalingAction === 'scale_up' ? 'status-warning' :
                                       scalingAction === 'scale_down' ? 'status-info' : 'status-healthy';
                    document.getElementById('scaling').innerHTML = `
                        <div class="metric">
                            <span class="metric-label">Recommendation:</span>
                            <span class="metric-value ${scalingClass}">${scalingAction || 'no_action'}</span>
                        </div>
                        <div class="metric">
                            <span class="metric-label">Reason:</span>
                            <span class="metric-value">${scalingReason}</span>
                        </div>
                    `;

                } catch (error) {
                    console.error('Error loading metrics:', error);
                }
            }

            async function forceScalingEvaluation() {
                try {
                    const response = await fetch('/monitoring/scaling/evaluate', { method: 'POST' });
                    const result = await response.json();
                    document.getElementById('action-result').innerHTML = `
                        <div style="margin-top: 10px; padding: 10px; background: #d1fae5; border-radius: 4px;">
                            ${result.message}
                        </div>
                    `;
                    setTimeout(() => document.getElementById('action-result').innerHTML = '', 3000);
                    setTimeout(loadMetrics, 1000);
                } catch (error) {
                    document.getElementById('action-result').innerHTML = `
                        <div style="margin-top: 10px; padding: 10px; background: #fee2e2; border-radius: 4px;">
                            Error: ${error.message}
                        </div>
                    `;
                }
            }

            // Load metrics on page load
            loadMetrics();

            // Auto-refresh every 30 seconds
            setInterval(loadMetrics, 30000);
        </script>
    </body>
    </html>
    """
  end

  defp generate_prometheus_metrics do
    try do
      metrics = ElixirFastCharge.Monitoring.MetricsCollector.get_current_metrics()
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

      """
      # HELP elixir_fast_charge_cpu_usage Current CPU usage percentage
      # TYPE elixir_fast_charge_cpu_usage gauge
      elixir_fast_charge_cpu_usage{node="#{metrics.system.node}"} #{metrics.system.cpu_usage} #{timestamp}

      # HELP elixir_fast_charge_memory_usage Current memory usage percentage
      # TYPE elixir_fast_charge_memory_usage gauge
      elixir_fast_charge_memory_usage{node="#{metrics.system.node}"} #{metrics.system.memory_usage} #{timestamp}

      # HELP elixir_fast_charge_active_pre_reservations Number of active pre-reservations
      # TYPE elixir_fast_charge_active_pre_reservations gauge
      elixir_fast_charge_active_pre_reservations{node="#{metrics.system.node}"} #{metrics.application.active_pre_reservations} #{timestamp}

      # HELP elixir_fast_charge_cluster_nodes Number of nodes in cluster
      # TYPE elixir_fast_charge_cluster_nodes gauge
      elixir_fast_charge_cluster_nodes{node="#{metrics.system.node}"} #{metrics.cluster.total_nodes} #{timestamp}

      # HELP elixir_fast_charge_uptime_seconds System uptime in seconds
      # TYPE elixir_fast_charge_uptime_seconds counter
      elixir_fast_charge_uptime_seconds{node="#{metrics.system.node}"} #{metrics.system.uptime} #{timestamp}
      """
    rescue
      _ -> "# Error generating metrics\n"
    end
  end

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
