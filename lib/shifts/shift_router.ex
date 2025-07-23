defmodule ElixirFastCharge.ShiftRouter do
  use Plug.Router

  plug CORSPlug, origin: ["http://localhost:5014"]
  plug :match
  plug Plug.Parsers, parsers: [:json],
                     pass: ["application/json"],
                     json_decoder: Jason
  plug :dispatch

  # === RUTAS PRINCIPALES DE TURNOS ===

  get "/active" do
    shifts = ElixirFastCharge.Storage.ShiftAgent.list_active_shifts()

    send_json_response(conn, 200, %{
      active_shifts: shifts,
      count: length(shifts)
    })
  end

  get "/inactive" do
    shifts = ElixirFastCharge.Storage.ShiftAgent.list_inactive_shifts()

    send_json_response(conn, 200, %{
      inactive_shifts: shifts,
      count: length(shifts)
    })
  end

  get "/all" do
    shifts = ElixirFastCharge.Storage.ShiftAgent.get_all_shifts()

    send_json_response(conn, 200, %{
      all_shifts: Map.values(shifts),
      count: map_size(shifts)
    })
  end

  get "/count" do
    total_count = ElixirFastCharge.Storage.ShiftAgent.count_shifts()
    active_count = ElixirFastCharge.Storage.ShiftAgent.count_active_shifts()

    send_json_response(conn, 200, %{
      total_shifts: total_count,
      active_shifts: active_count,
      inactive_shifts: total_count - active_count
    })
  end

  # === OPERACIONES CON TURNOS ESPECÍFICOS ===

  get "/:shift_id" do
    case ElixirFastCharge.Storage.ShiftAgent.get_shift(shift_id) do
      nil ->
        send_json_response(conn, 404, %{error: "Shift not found"})
      shift ->
        send_json_response(conn, 200, shift)
    end
  end

  post "/:shift_id/reserve" do
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

  put "/:shift_id/activate" do
    case ElixirFastCharge.Storage.ShiftAgent.set_shift_active(shift_id, true) do
      {:ok, updated_shift} ->
        send_json_response(conn, 200, %{
          message: "Shift activated successfully",
          shift: updated_shift
        })
      {:error, :shift_not_found} ->
        send_json_response(conn, 404, %{error: "Shift not found"})
    end
  end

  put "/:shift_id/deactivate" do
    case ElixirFastCharge.Storage.ShiftAgent.set_shift_active(shift_id, false) do
      {:ok, updated_shift} ->
        send_json_response(conn, 200, %{
          message: "Shift deactivated successfully",
          shift: updated_shift
        })
      {:error, :shift_not_found} ->
        send_json_response(conn, 404, %{error: "Shift not found"})
    end
  end

  # === CLEANUP ===

  post "/expire-old" do
    ElixirFastCharge.Storage.ShiftAgent.expire_old_shifts()

    send_json_response(conn, 200, %{
      message: "Old shifts expired successfully"
    })
  end

  match _ do
    send_json_response(conn, 404, %{error: "Shift route not found"})
  end

  # === HELPERS ===

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
