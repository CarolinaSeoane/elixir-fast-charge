defmodule ElixirFastCharge.ClusterRouter do
  @moduledoc """
  Router para operaciones de cluster y monitoreo del sistema distribuido.
  """
  use Plug.Router

  plug :match
  plug :dispatch

  # === INFORMACIÓN DEL CLUSTER ===

  get "/info" do
    uptime_ms = elem(:erlang.statistics(:wall_clock), 0)
    memory_info = :erlang.memory()

    cluster_info = %{
      current_node: Atom.to_string(Node.self()),
      connected_nodes: Enum.map(Node.list(), &Atom.to_string/1),
      total_nodes: length(Node.list()) + 1,
      cluster_status: if(length(Node.list()) > 0, do: "clustered", else: "standalone"),
      uptime_seconds: div(uptime_ms, 1000),
      memory_usage: %{
        total: memory_info[:total],
        processes: memory_info[:processes],
        system: memory_info[:system],
        atom: memory_info[:atom],
        binary: memory_info[:binary],
        ets: memory_info[:ets]
      },
      system_info: %{
        otp_release: System.otp_release(),
        elixir_version: System.version(),
        erts_version: List.to_string(:erlang.system_info(:version))
      }
    }

    send_json_response(conn, 200, cluster_info)
  end

  # === ESTADÍSTICAS DISTRIBUIDAS ===

  get "/stats" do
    # Obtener estadísticas de todos los componentes distribuidos
    stats = %{
      cluster: get_cluster_basic_info(),
      shifts: ElixirFastCharge.DistributedShiftManager.get_cluster_stats(),
      pre_reservations: ElixirFastCharge.DistributedPreReservationManager.get_cluster_stats(),
      horde_registry: get_horde_registry_stats(),
      horde_supervisor: get_horde_supervisor_stats()
    }

    send_json_response(conn, 200, stats)
  end

  # === OPERACIONES DE NODOS ===

  post "/nodes/connect" do
    node_name = conn.body_params["node_name"]

    if is_nil(node_name) do
      send_json_response(conn, 400, %{error: "node_name is required"})
    else
      case Node.connect(String.to_atom(node_name)) do
        true ->
          send_json_response(conn, 200, %{
            message: "Successfully connected to node",
            node_name: node_name,
            cluster_nodes: [Node.self() | Node.list()]
          })
        false ->
          send_json_response(conn, 400, %{
            error: "Failed to connect to node",
            node_name: node_name
          })
      end
    end
  end

  post "/nodes/disconnect" do
    node_name = conn.body_params["node_name"]

    if is_nil(node_name) do
      send_json_response(conn, 400, %{error: "node_name is required"})
    else
      case Node.disconnect(String.to_atom(node_name)) do
        true ->
          send_json_response(conn, 200, %{
            message: "Successfully disconnected from node",
            node_name: node_name,
            cluster_nodes: [Node.self() | Node.list()]
          })
        false ->
          send_json_response(conn, 400, %{
            error: "Failed to disconnect from node",
            node_name: node_name
          })
      end
    end
  end

  # === PROCESOS DISTRIBUIDOS ===

  get "/processes" do
    # Listar todos los procesos registrados en Horde
    processes = ElixirFastCharge.HordeRegistry.list_all()
    |> Enum.map(fn {name, pid, value} ->
      %{
        name: inspect(name),
        pid: inspect(pid),
        node: node(pid),
        value: inspect(value),
        process_info: get_process_info(pid)
      }
    end)

    send_json_response(conn, 200, %{
      processes: processes,
      total_count: length(processes),
      current_node: Node.self()
    })
  end

  get "/processes/shifts" do
    shifts_info = ElixirFastCharge.HordeRegistry.list_all()
    |> Enum.filter(fn {{:shift, _}, _pid, _value} -> true; _ -> false end)
    |> Enum.map(fn {{:shift, shift_id}, pid, _value} ->
      case ElixirFastCharge.DistributedShift.get_info(shift_id) do
        {:ok, info} -> info
        _ -> %{shift_id: shift_id, pid: inspect(pid), error: "Could not get info"}
      end
    end)

    send_json_response(conn, 200, %{
      shifts: shifts_info,
      count: length(shifts_info),
      current_node: Node.self()
    })
  end

  get "/processes/pre-reservations" do
    pre_reservations_info = ElixirFastCharge.HordeRegistry.list_all()
    |> Enum.filter(fn {{:pre_reservation, _}, _pid, _value} -> true; _ -> false end)
    |> Enum.map(fn {{:pre_reservation, pre_reservation_id}, pid, _value} ->
      case ElixirFastCharge.DistributedPreReservation.get_info(pre_reservation_id) do
        {:ok, info} -> info
        _ -> %{pre_reservation_id: pre_reservation_id, pid: inspect(pid), error: "Could not get info"}
      end
    end)

    send_json_response(conn, 200, %{
      pre_reservations: pre_reservations_info,
      count: length(pre_reservations_info),
      current_node: Node.self()
    })
  end

  # === TESTING Y SIMULACIÓN ===

  post "/test/create-shift" do
    shift_data = %{
      station_id: "test_station",
      point_id: "test_point_#{:rand.uniform(1000)}",
      connector_type: "ccs",
      power_kw: 150,
      location: %{address: "Test Location"},
      start_time: DateTime.utc_now(),
      end_time: DateTime.add(DateTime.utc_now(), 2 * 60 * 60, :second),
      expires_at: DateTime.add(DateTime.utc_now(), 30 * 60, :second)
    }

    case ElixirFastCharge.DistributedShiftManager.create_shift(shift_data) do
      {:ok, shift} ->
        send_json_response(conn, 201, %{
          message: "Test shift created successfully",
          shift: shift,
          node: Node.self()
        })
      {:error, reason} ->
        send_json_response(conn, 500, %{
          error: "Failed to create test shift",
          reason: inspect(reason)
        })
    end
  end

  post "/test/create-pre-reservation" do
    user_id = conn.body_params["user_id"] || "test_user_#{:rand.uniform(1000)}"
    shift_id = conn.body_params["shift_id"]

    if is_nil(shift_id) do
      send_json_response(conn, 400, %{error: "shift_id is required"})
    else
      case ElixirFastCharge.DistributedPreReservationManager.create_pre_reservation(user_id, shift_id) do
        {:ok, pre_reservation, action} ->
          send_json_response(conn, 201, %{
            message: "Test pre-reservation #{action} successfully",
            pre_reservation: pre_reservation,
            action: action,
            node: Node.self()
          })
        {:error, reason} ->
          send_json_response(conn, 500, %{
            error: "Failed to create test pre-reservation",
            reason: inspect(reason)
          })
      end
    end
  end

  # Crear estación de prueba distribuida
  post "/test/create-station" do
    test_station_data = %{
      station_id: "test_station_#{:rand.uniform(1000)}_#{DateTime.utc_now() |> DateTime.to_unix(:millisecond)}",
      name: "Test Charging Station",
      location: %{
        address: "Test Address #{:rand.uniform(100)}",
        city: "Test City",
        coordinates: %{lat: 40.7128, lng: -74.0060}
      },
      status: :active,
      charging_points: [
        %{
          point_id: "point_1",
          connector_type: :ccs,
          power_kw: 150,
          status: :available
        },
        %{
          point_id: "point_2",
          connector_type: :type2,
          power_kw: 22,
          status: :available
        }
      ]
    }

    case ElixirFastCharge.DistributedChargingStationManager.create_station(test_station_data) do
      {:ok, pid} ->
        send_json_response(conn, 201, %{
          message: "Test station created successfully",
          station: test_station_data,
          node: Node.self()
        })

      {:error, reason} ->
        send_json_response(conn, 500, %{
          error: "Failed to create test station",
          reason: inspect(reason)
        })
    end
  end

  # Crear preferencia de prueba distribuida
  post "/test/create-preference" do
    test_preference_data = %{
      username: conn.body_params["username"] || "test_user_#{:rand.uniform(100)}",
      station_id: conn.body_params["station_id"] || "test_station_001",
      connector_type: String.to_atom(conn.body_params["connector_type"] || "ccs"),
      power_kw: conn.body_params["power_kw"] || 150,
      location: conn.body_params["location"] || "Test City",
      fecha: conn.body_params["fecha"] || Date.utc_today() |> Date.to_iso8601(),
      hora_inicio: conn.body_params["hora_inicio"] || "09:00",
      hora_fin: conn.body_params["hora_fin"] || "18:00",
      alert: conn.body_params["alert"] || true,
      priority: String.to_atom(conn.body_params["priority"] || "normal")
    }

    case ElixirFastCharge.DistributedPreferenceManager.create_preference(test_preference_data) do
      {:ok, pid} ->
        send_json_response(conn, 201, %{
          message: "Test preference created successfully",
          preference_data: test_preference_data,
          node: Node.self()
        })

      {:error, reason} ->
        send_json_response(conn, 500, %{
          error: "Failed to create test preference",
          reason: inspect(reason)
        })
    end
  end

  # === MANTENIMIENTO ===

  post "/maintenance/cleanup" do
    # Limpiar procesos terminados, etc.
    send_json_response(conn, 200, %{
      message: "Maintenance cleanup completed",
      node: Node.self()
    })
  end

  match _ do
    send_json_response(conn, 404, %{error: "Cluster route not found"})
  end

  # === FUNCIONES AUXILIARES ===

  defp get_cluster_basic_info do
    %{
      current_node: Atom.to_string(Node.self()),
      connected_nodes: Enum.map(Node.list(), &Atom.to_string/1),
      total_nodes: length(Node.list()) + 1,
      cluster_status: if(length(Node.list()) > 0, do: "clustered", else: "standalone")
    }
  end

  defp get_horde_registry_stats do
    try do
      processes = ElixirFastCharge.HordeRegistry.list_all()
      %{
        total_processes: length(processes),
        process_types: get_process_type_distribution(processes),
        node_distribution: get_node_distribution(processes)
      }
    rescue
      _ -> %{error: "HordeRegistry not available"}
    end
  end

  defp get_horde_supervisor_stats do
    try do
      children_info = ElixirFastCharge.HordeSupervisor.count_children()
      # Convertir children_info a un formato JSON-serializable
      children_map = children_info
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
      |> Map.new()

      %{
        children_count: children_map,
        supervisor_available: true
      }
    rescue
      _ -> %{error: "HordeSupervisor not available"}
    end
  end

  defp get_process_type_distribution(processes) do
    processes
    |> Enum.group_by(fn {name, _pid, _value} ->
      case name do
        {:shift, _} -> "shift"
        {:pre_reservation, _} -> "pre_reservation"
        {:user, _} -> "user"
        _ -> "other"
      end
    end)
    |> Enum.map(fn {type, list} -> {type, length(list)} end)
    |> Map.new()
  end

  defp get_node_distribution(processes) do
    processes
    |> Enum.group_by(fn {_name, pid, _value} -> Atom.to_string(node(pid)) end)
    |> Enum.map(fn {node, list} -> {node, length(list)} end)
    |> Map.new()
  end

  defp get_process_info(pid) do
    try do
      if Process.alive?(pid) do
        info = Process.info(pid)
        %{
          status: info[:status],
          message_queue_len: info[:message_queue_len],
          heap_size: info[:heap_size],
          stack_size: info[:stack_size]
        }
      else
        %{status: :dead}
      end
    rescue
      _ -> %{status: :unknown}
    end
  end

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
