defmodule ElixirFastCharge.StationRouter do
  use Plug.Router

  plug :match
  plug Plug.Parsers, parsers: [:json],
                     pass: ["application/json"],
                     json_decoder: Jason
  plug :dispatch


  get "/" do
    station_tuples = ElixirFastCharge.ChargingStations.StationRegistry.list_stations()

    stations = Enum.map(station_tuples, fn {station_id, _pid} ->
      try do
        station_data = ElixirFastCharge.ChargingStations.ChargingStation.get_status(station_id)
        Map.put(station_data, :station_id, station_id)
      rescue
        _ ->
          %{
            station_id: station_id,
            available: false,
            error: "Station not responding"
          }
      end
    end)

    send_json_response(conn, 200, %{
      stations: stations,
      count: length(stations)
    })
  end

  get "/:station_id" do
    station_id = String.to_atom(station_id)

    if _pid = ElixirFastCharge.ChargingStations.StationRegistry.get_station(station_id) do
      station_data = ElixirFastCharge.ChargingStations.ChargingStation.get_status(station_id)
      send_json_response(conn, 200, station_data)
    else
      send_json_response(conn, 404, %{error: "Station not found"})
    end
  end

  get "/:station_id/charging-points" do
    station_id = String.to_atom(station_id)

    if _pid = ElixirFastCharge.ChargingStations.StationRegistry.get_station(station_id) do
      points = ElixirFastCharge.ChargingStations.ChargingStation.get_charging_points(station_id)
      send_json_response(conn, 200, %{charging_points: points})
    else
      send_json_response(conn, 404, %{error: "Station not found"})
    end
  end

  get "/:station_id/available-points" do
    station_id = String.to_atom(station_id)

    if _pid = ElixirFastCharge.ChargingStations.StationRegistry.get_station(station_id) do
      points = ElixirFastCharge.ChargingStations.ChargingStation.get_available_points(station_id)
      send_json_response(conn, 200, %{available_points: points})
    else
      send_json_response(conn, 404, %{error: "Station not found"})
    end
  end

  # === RUTAS DE TURNOS ===

  get "/:station_id/shifts" do
    station_id = String.to_atom(station_id)
    shifts = ElixirFastCharge.Storage.ShiftAgent.list_shifts_by_station(station_id)

    send_json_response(conn, 200, %{
      shifts: shifts,
      count: length(shifts)
    })
  end

  post "/:station_id/shifts" do
    station_id = String.to_atom(station_id)

    case extract_shift_params(conn.body_params) do
      {:ok, shift_params} ->
        case ElixirFastCharge.ChargingStations.ChargingStation.publish_shifts(station_id, shift_params) do
          {:ok, created_shifts} ->
            send_json_response(conn, 201, %{
              message: "Shifts created successfully",
              shifts: created_shifts,
              count: length(created_shifts)
            })
          {:error, reason} ->
            send_json_response(conn, 500, %{error: "Failed to create shifts", reason: inspect(reason)})
        end
      {:error, error_message} ->
        send_json_response(conn, 400, %{error: error_message})
    end
  end

  post "/:station_id/points/:point_id/shifts" do
    station_id = String.to_atom(station_id)

    case extract_shift_params(conn.body_params) do
      {:ok, shift_params} ->
        case ElixirFastCharge.ChargingStations.ChargingStation.publish_shift_for_point(station_id, point_id, shift_params) do
          {:ok, shift} ->
            send_json_response(conn, 201, %{
              message: "Shift created successfully",
              shift: shift
            })
          {:error, reason} ->
            send_json_response(conn, 500, %{error: "Failed to create shift", reason: inspect(reason)})
        end
      {:error, error_message} ->
        send_json_response(conn, 400, %{error: error_message})
    end
  end

  # === RUTAS GLOBALES DE TURNOS ===

  get "/shifts/active" do
    shifts = ElixirFastCharge.Storage.ShiftAgent.list_active_shifts()

    send_json_response(conn, 200, %{
      active_shifts: shifts,
      count: length(shifts)
    })
  end

  get "/shifts/:shift_id" do
    case ElixirFastCharge.Storage.ShiftAgent.get_shift(shift_id) do
      nil ->
        send_json_response(conn, 404, %{error: "Shift not found"})
      shift ->
        send_json_response(conn, 200, shift)
    end
  end

  post "/shifts/:shift_id/reserve" do
    case extract_reserve_params(conn.body_params) do
      {:ok, user_id} ->
        case ElixirFastCharge.Storage.ShiftAgent.reserve_shift(shift_id, user_id) do
          {:ok, reserved_shift} ->
            send_json_response(conn, 200, %{
              message: "Shift reserved successfully",
              shift: reserved_shift
            })
          {:error, :shift_not_found} ->
            send_json_response(conn, 404, %{error: "Shift not found"})
          {:error, :shift_not_available} ->
            send_json_response(conn, 400, %{error: "Shift not available"})
          {:error, reason} ->
            send_json_response(conn, 500, %{error: "Failed to reserve shift", reason: inspect(reason)})
        end
      {:error, error_message} ->
        send_json_response(conn, 400, %{error: error_message})
    end
  end

  match _ do
    send_json_response(conn, 404, %{error: "Station route not found"})
  end

  # === HELPERS ===

  defp extract_shift_params(body_params) do
    case body_params do
      %{"start_time" => start_time, "end_time" => end_time, "expires_at" => expires_at} ->
        with {:ok, start_dt, _} <- DateTime.from_iso8601(start_time),
             {:ok, end_dt, _} <- DateTime.from_iso8601(end_time),
             {:ok, expires_dt, _} <- DateTime.from_iso8601(expires_at) do
          {:ok, %{
            start_time: start_dt,
            end_time: end_dt,
            expires_at: expires_dt
          }}
        else
          _ -> {:error, "Invalid datetime format. Use ISO8601 format"}
        end
      _ ->
        {:error, "start_time, end_time, and expires_at are required"}
    end
  end

  defp extract_reserve_params(body_params) do
    case body_params do
      %{"user_id" => user_id} when is_binary(user_id) ->
        {:ok, user_id}
      _ ->
        {:error, "user_id is required"}
    end
  end

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
