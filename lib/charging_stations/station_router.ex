defmodule ElixirFastCharge.StationRouter do
  use Plug.Router

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug :match
  plug :dispatch

  get "/" do
    stations = ElixirFastCharge.DistributedChargingStationManager.list_all_stations()

    send_json_response(conn, 200, %{
      stations: stations,
      count: length(stations),
      cluster_info: %{
        node: Node.self(),
        distributed: true
      }
    })
  end

  get "/:station_id" do
    case ElixirFastCharge.DistributedChargingStationManager.get_station(station_id) do
      {:ok, station} ->
        send_json_response(conn, 200, %{
          station: station,
          cluster_info: %{
            node: Node.self(),
            distributed: true
          }
        })
      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Station not found"})
    end
  end

  get "/:station_id/charging-points" do
    case ElixirFastCharge.DistributedChargingStationManager.get_charging_points(station_id) do
      {:ok, points} ->
        send_json_response(conn, 200, %{
          charging_points: points,
          cluster_info: %{
            node: Node.self(),
            distributed: true
          }
        })
      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Station not found"})
    end
  end

  get "/:station_id/available-points" do
    case ElixirFastCharge.DistributedChargingStationManager.get_available_points(station_id) do
      {:ok, points} ->
        send_json_response(conn, 200, %{
          available_points: points,
          cluster_info: %{
            node: Node.self(),
            distributed: true
          }
        })
      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Station not found"})
    end
  end

  # === CREAR TURNOS PARA PUNTO ESPECÍFICO ===
  post "/:station_id/points/:point_id/shifts" do
    # Verificar que la estación existe
    case ElixirFastCharge.DistributedChargingStationManager.get_station(station_id) do
      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Station not found"})

      {:ok, station} ->
        # Verificar que el punto de carga existe en la estación
        case ElixirFastCharge.DistributedChargingStationManager.get_charging_points(station_id) do
          {:ok, charging_points} ->
            charging_point = Enum.find(charging_points, fn point ->
              point.point_id == point_id
            end)

            if charging_point do
              # Parámetros opcionales del body
              shifts_count = Map.get(conn.body_params, "shifts_count", 3)
              duration_hours = Map.get(conn.body_params, "duration_hours", 2)
              start_hour = Map.get(conn.body_params, "start_hour", 8)
              power_kw = Map.get(conn.body_params, "power_kw", nil)

              # Crear turnos para este punto específico
              {created_shifts, errors} =
                create_shifts_for_point(station_id, charging_point, shifts_count, duration_hours, start_hour, power_kw)

              # Respuesta
              response = %{
                message: "Shifts created successfully for point #{point_id} in station #{station_id}",
                station_id: station_id,
                station_name: station.name,
                point_id: point_id,
                connector_type: charging_point.connector_type,
                power_kw: power_kw || charging_point.power_kw,
                created_shifts: created_shifts,
                total_shifts_created: length(created_shifts),
                shifts_count: shifts_count,
                cluster_info: %{
                  node: Node.self(),
                  distributed: true
                }
              }

              response = if Enum.any?(errors) do
                Map.put(response, :errors, errors)
              else
                response
              end

              status_code = if Enum.empty?(created_shifts), do: 500, else: 201
              send_json_response(conn, status_code, response)
            else
              send_json_response(conn, 404, %{
                error: "Charging point not found",
                station_id: station_id,
                point_id: point_id,
                available_points: Enum.map(charging_points, & &1.point_id)
              })
            end

          {:error, _reason} ->
            send_json_response(conn, 500, %{
              error: "Failed to get charging points for station",
              station_id: station_id
            })
        end
    end
  end

  # === CREAR TURNOS PARA ESTACIÓN ===
  post "/:station_id/shifts" do
    # Verificar que la estación existe
    case ElixirFastCharge.DistributedChargingStationManager.get_station(station_id) do
      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Station not found"})

      {:ok, station} ->
        # Parámetros opcionales del body
        shifts_per_point = Map.get(conn.body_params, "shifts_per_point", 3)
        duration_hours = Map.get(conn.body_params, "duration_hours", 2)
        start_hour = Map.get(conn.body_params, "start_hour", 8)
        connector_type = Map.get(conn.body_params, "connector_type", nil)
        power_kw = Map.get(conn.body_params, "power_kw", nil)

        # Obtener puntos de carga de la estación
        case ElixirFastCharge.DistributedChargingStationManager.get_charging_points(station_id) do
          {:ok, charging_points} ->
            created_shifts = []
            errors = []

            # Filtrar puntos por tipo de conector si se especifica
            filtered_points = if connector_type do
              Enum.filter(charging_points, fn point ->
                Atom.to_string(point.connector_type) == connector_type
              end)
            else
              charging_points
            end

            if Enum.empty?(filtered_points) do
              send_json_response(conn, 400, %{
                error: "No charging points found with the specified criteria",
                station_id: station_id,
                requested_connector_type: connector_type
              })
            else
              # Crear turnos para cada punto de carga
              {created_shifts, errors} =
                Enum.reduce(filtered_points, {[], []}, fn point, {shifts_acc, errors_acc} ->
                  # Crear múltiples turnos por punto
                  {point_shifts, point_errors} =
                    create_shifts_for_point(station_id, point, shifts_per_point, duration_hours, start_hour, power_kw)

                  {shifts_acc ++ point_shifts, errors_acc ++ point_errors}
                end)

              # Respuesta
              response = %{
                message: "Shifts created successfully for station #{station_id}",
                station_id: station_id,
                station_name: station.name,
                created_shifts: created_shifts,
                total_shifts_created: length(created_shifts),
                charging_points_used: length(filtered_points),
                shifts_per_point: shifts_per_point,
                cluster_info: %{
                  node: Node.self(),
                  distributed: true
                }
              }

              response = if Enum.any?(errors) do
                Map.put(response, :errors, errors)
              else
                response
              end

              status_code = if Enum.empty?(created_shifts), do: 500, else: 201
              send_json_response(conn, status_code, response)
            end

          {:error, _reason} ->
            send_json_response(conn, 500, %{
              error: "Failed to get charging points for station",
              station_id: station_id
            })
        end
    end
  end

  get "/:station_id/info" do
    case ElixirFastCharge.DistributedChargingStationManager.get_station_info(station_id) do
      {:ok, info} ->
        send_json_response(conn, 200, %{
          station_info: info,
          cluster_info: %{
            node: Node.self(),
            distributed: true
          }
        })
      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Station not found"})
    end
  end

  get "/active" do
    active_stations = ElixirFastCharge.DistributedChargingStationManager.list_active_stations()

    send_json_response(conn, 200, %{
      active_stations: active_stations,
      count: length(active_stations),
      cluster_info: %{
        node: Node.self(),
        distributed: true
      }
    })
  end

  get "/cluster/stats" do
    cluster_stats = ElixirFastCharge.DistributedChargingStationManager.get_cluster_stats()

    send_json_response(conn, 200, %{
      cluster_stats: cluster_stats,
      cluster_info: %{
        node: Node.self(),
        distributed: true
      }
    })
  end

  # === NOTA: OPERACIONES DE TURNOS ===
  # Las operaciones de turnos están disponibles en /shifts
  # Ejemplo: GET /shifts/all, POST /shifts/pre-reservations, etc.

  match _ do
    send_json_response(conn, 404, %{error: "Station route not found"})
  end

  # === HELPERS ===

  defp create_shifts_for_point(station_id, charging_point, shifts_count, duration_hours, start_hour, override_power_kw) do
    base_datetime = DateTime.utc_now()
    today = DateTime.to_date(base_datetime)

    {created_shifts, errors} =
      Enum.reduce(1..shifts_count, {[], []}, fn shift_num, {shifts_acc, errors_acc} ->
        # Calcular horarios escalonados
        shift_start_hour = start_hour + ((shift_num - 1) * duration_hours)
        shift_end_hour = shift_start_hour + duration_hours

        # Crear DateTime para start_time y end_time
        {:ok, start_time} = DateTime.new(today, Time.new!(shift_start_hour, 0, 0))
        {:ok, end_time} = DateTime.new(today, Time.new!(shift_end_hour, 0, 0))

        # Si los horarios pasan de medianoche, ajustar al día siguiente
        {start_time, end_time} = if shift_start_hour >= 24 do
          tomorrow = Date.add(today, 1)
          adjusted_start_hour = rem(shift_start_hour, 24)
          adjusted_end_hour = rem(shift_end_hour, 24)

          {:ok, start_adj} = DateTime.new(tomorrow, Time.new!(adjusted_start_hour, 0, 0))
          {:ok, end_adj} = DateTime.new(tomorrow, Time.new!(adjusted_end_hour, 0, 0))
          {start_adj, end_adj}
        else
          {start_time, end_time}
        end

        # Datos del turno
        shift_data = %{
          station_id: station_id,
          point_id: charging_point.point_id,
          connector_type: charging_point.connector_type,
          power_kw: override_power_kw || charging_point.power_kw,
          location: %{
            station_id: station_id,
            point_id: charging_point.point_id
          },
          start_time: start_time,
          end_time: end_time,
          expires_at: DateTime.add(base_datetime, 30 * 60, :second), # 30 minutos para expirar
          metadata: %{
            created_via: "station_endpoint",
            shift_number: shift_num,
            total_shifts_in_batch: shifts_count
          }
        }

        # Crear el turno
        case ElixirFastCharge.DistributedShiftManager.create_shift(shift_data) do
          {:ok, created_shift} ->
            {shifts_acc ++ [created_shift], errors_acc}
          {:error, reason} ->
            error_info = %{
              point_id: charging_point.point_id,
              shift_number: shift_num,
              reason: inspect(reason),
              attempted_start_time: DateTime.to_iso8601(start_time)
            }
            {shifts_acc, errors_acc ++ [error_info]}
        end
      end)

    {created_shifts, errors}
  end

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
