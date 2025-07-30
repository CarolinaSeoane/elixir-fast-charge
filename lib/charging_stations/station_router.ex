defmodule ElixirFastCharge.StationRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/" do
    stations_raw = ElixirFastCharge.ChargingStationSupervisor.list_stations()

    stations = stations_raw
    |> Enum.map(fn {station_id, pid} ->

      %{
        station_id: station_id,
        pid: inspect(pid),
      }
    end)

    send_json_response(conn, 200, %{
      stations: stations,
      count: length(stations)
    })
  end

  get "/:station_id" do
    station_id = String.to_atom(station_id)

    case ElixirFastCharge.ChargingStationSupervisor.get_station(station_id) do
      {:ok, station_pid} ->
        try do
          station_data = ElixirFastCharge.ChargingStations.ChargingStation.get_status(station_pid)
          send_json_response(conn, 200, station_data)
        catch
          :exit, _ ->
            send_json_response(conn, 500, %{error: "Station not responding"})
        end
      {:error, :not_found} ->
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
        case ElixirFastCharge.ChargingStationSupervisor.get_station(station_id) do
          {:ok, station_pid} ->
            try do
              case ElixirFastCharge.ChargingStations.ChargingStation.publish_shifts(station_pid, shift_params) do
                {:ok, created_shifts} ->
                  send_json_response(conn, 201, %{
                    message: "Shifts created successfully",
                    shifts: created_shifts,
                    count: length(created_shifts)
                  })
                {:error, reason} ->
                  send_json_response(conn, 500, %{error: "Failed to create shifts", reason: inspect(reason)})
              end
            catch
              :exit, _ ->
                send_json_response(conn, 500, %{error: "Station not responding"})
            end
          {:error, :not_found} ->
            send_json_response(conn, 404, %{error: "Station not found"})
        end
      {:error, error_message} ->
        send_json_response(conn, 400, %{error: error_message})
    end
  end

  post "/:station_id/points/:point_id/shifts" do
    station_id = String.to_atom(station_id)

    case extract_shift_params(conn.body_params) do
      {:ok, shift_params} ->
        case ElixirFastCharge.ChargingStationSupervisor.get_station(station_id) do
          {:ok, station_pid} ->
            try do
              case ElixirFastCharge.ChargingStations.ChargingStation.publish_shift_for_point(station_pid, point_id, shift_params) do
                {:ok, shift} ->
                  send_json_response(conn, 201, %{
                    message: "Shift created successfully",
                    shift: shift
                  })
                {:error, reason} ->
                  send_json_response(conn, 500, %{error: "Failed to create shift", reason: inspect(reason)})
              end
            catch
              :exit, _ ->
                send_json_response(conn, 500, %{error: "Station not responding"})
            end
          {:error, :not_found} ->
            send_json_response(conn, 404, %{error: "Station not found"})
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

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
