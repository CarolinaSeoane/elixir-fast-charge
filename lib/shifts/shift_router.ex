defmodule ElixirFastCharge.ShiftRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/active" do
    shifts = ElixirFastCharge.Storage.ShiftAgent.list_active_shifts()

    send_json_response(conn, 200, %{
      active_shifts: shifts,
      count: length(shifts)
    })
  end

  get "/inactive" do
    alias ElixirFastCharge.Shifts.ShiftController

    shifts = ShiftController.list_inactive_shifts()

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
    alias ElixirFastCharge.Shifts.ShiftController

    counts = ShiftController.get_shift_counts()

    send_json_response(conn, 200, counts)
  end

  # === PRE-RESERVAS ===

  # Crear una pre-reserva
  post "/pre-reservations" do
    user_id = conn.body_params["user_id"]
    shift_id = conn.body_params["shift_id"]

    cond do
      is_nil(user_id) ->
        send_json_response(conn, 400, %{error: "user_id is required"})

      is_nil(shift_id) ->
        send_json_response(conn, 400, %{error: "shift_id is required"})

      true ->
        case ElixirFastCharge.UserDynamicSupervisor.get_user(user_id) do
          {:ok, _user_pid} ->
            # Verificar que el turno exista y esté activo
            case ElixirFastCharge.Storage.ShiftAgent.get_shift(shift_id) do
              nil ->
                send_json_response(conn, 404, %{error: "Shift not found"})

              shift when shift.status == :active and shift.active == true ->
                case ElixirFastCharge.Storage.PreReservationAgent.create_pre_reservation(user_id, shift_id) do
                  {:ok, pre_reservation} ->
                    send_json_response(conn, 201, %{
                      pre_reservation: pre_reservation,
                      message: "Pre-reservation created successfully. You have 1 minute to confirm payment."
                    })

                  {:error, reason} ->
                    send_json_response(conn, 500, %{error: "Failed to create pre-reservation", reason: inspect(reason)})
                end

              _shift ->
                send_json_response(conn, 409, %{error: "Shift is not available for reservation"})
            end

          {:error, :not_found} ->
            send_json_response(conn, 404, %{error: "User not found"})
        end
    end
  end

  # Actualizar una pre-reserva existente
  put "/pre-reservations" do
    pre_reservation_id = conn.body_params["pre_reservation_id"]
    user_id = conn.body_params["user_id"]
    shift_id = conn.body_params["shift_id"]

    cond do
      is_nil(pre_reservation_id) ->
        send_json_response(conn, 400, %{error: "pre_reservation_id is required"})

      is_nil(user_id) ->
        send_json_response(conn, 400, %{error: "user_id is required"})

      is_nil(shift_id) ->
        send_json_response(conn, 400, %{error: "shift_id is required"})

      true ->
        case ElixirFastCharge.UserDynamicSupervisor.get_user(user_id) do
          {:ok, _user_pid} ->
            # Verificar que el turno exista y esté activo
            case ElixirFastCharge.Storage.ShiftAgent.get_shift(shift_id) do
              nil ->
                send_json_response(conn, 404, %{error: "Shift not found"})

              shift when shift.status == :active and shift.active == true ->
                case ElixirFastCharge.Storage.PreReservationAgent.update_pre_reservation(pre_reservation_id, user_id, shift_id) do
                  {:ok, pre_reservation} ->
                    send_json_response(conn, 200, %{
                      pre_reservation: pre_reservation,
                      message: "Pre-reservation updated successfully"
                    })

                  {:error, :not_found} ->
                    send_json_response(conn, 404, %{error: "Pre-reservation not found"})

                  {:error, reason} ->
                    send_json_response(conn, 500, %{error: "Failed to update pre-reservation", reason: inspect(reason)})
                end

              _shift ->
                send_json_response(conn, 409, %{error: "Shift is not available for reservation"})
            end

          {:error, :not_found} ->
            send_json_response(conn, 404, %{error: "User not found"})
        end
    end
  end

  # Confirmar pre-reserva (pago)
  post "/pre-reservations/:pre_reservation_id/confirm" do
    case ElixirFastCharge.Storage.PreReservationAgent.confirm_pre_reservation(pre_reservation_id) do
      {:ok, confirmed_pre_reservation} ->
        # Ahora reservar el turno definitivamente
        case ElixirFastCharge.Storage.ShiftAgent.reserve_shift(confirmed_pre_reservation.shift_id, confirmed_pre_reservation.user_id) do
          {:ok, reserved_shift} ->
            send_json_response(conn, 200, %{
              message: "Pre-reservation confirmed and shift reserved successfully",
              pre_reservation: confirmed_pre_reservation,
              shift: reserved_shift
            })

          {:error, :shift_not_found} ->
            send_json_response(conn, 404, %{error: "Shift not found"})

          {:error, :shift_not_available} ->
            # El turno ya fue tomado por otro usuario
            send_json_response(conn, 409, %{error: "Shift is no longer available"})

          {:error, reason} ->
            send_json_response(conn, 500, %{error: "Failed to reserve shift", reason: inspect(reason)})
        end

      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Pre-reservation not found"})

      {:error, :expired} ->
        send_json_response(conn, 410, %{error: "Pre-reservation has expired"})

      {:error, :invalid_status} ->
        send_json_response(conn, 409, %{error: "Pre-reservation cannot be confirmed in its current status"})

      {:error, reason} ->
        send_json_response(conn, 500, %{error: "Failed to confirm pre-reservation", reason: inspect(reason)})
    end
  end

  # Cancelar pre-reserva
  delete "/pre-reservations/:pre_reservation_id" do
    case ElixirFastCharge.Storage.PreReservationAgent.cancel_pre_reservation(pre_reservation_id) do
      {:ok, cancelled_pre_reservation} ->
        send_json_response(conn, 200, %{
          message: "Pre-reservation cancelled successfully",
          pre_reservation: cancelled_pre_reservation
        })

      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Pre-reservation not found"})

      {:error, reason} ->
        send_json_response(conn, 500, %{error: "Failed to cancel pre-reservation", reason: inspect(reason)})
    end
  end

  # Listar todas las pre-reservas (endpoint administrativo)
  get "/pre-reservations/all" do
    pre_reservations = ElixirFastCharge.Storage.PreReservationAgent.get_all_pre_reservations()

    send_json_response(conn, 200, %{
      pre_reservations: pre_reservations,
      count: length(pre_reservations)
    })
  end

  # Obtener estadísticas de pre-reservas
  get "/pre-reservations/stats/count" do
    counts = ElixirFastCharge.Storage.PreReservationAgent.count_pre_reservations()
    send_json_response(conn, 200, %{counts: counts})
  end

  # Limpiar pre-reservas expiradas (endpoint administrativo)
  post "/pre-reservations/cleanup/expired" do
    expired_count = ElixirFastCharge.Storage.PreReservationAgent.expire_old_pre_reservations()

    send_json_response(conn, 200, %{
      message: "Expired pre-reservations cleaned up",
      expired_count: expired_count
    })
  end

  # Listar pre-reservas de un usuario
  get "/pre-reservations/user/:user_id" do
    pre_reservations = ElixirFastCharge.Storage.PreReservationAgent.list_pending_pre_reservations_for_user(user_id)

    send_json_response(conn, 200, %{
      pre_reservations: pre_reservations,
      count: length(pre_reservations)
    })
  end

  # Obtener pre-reserva específica
  get "/pre-reservations/:pre_reservation_id" do
    case ElixirFastCharge.Storage.PreReservationAgent.get_pre_reservation(pre_reservation_id) do
      {:ok, pre_reservation} ->
        send_json_response(conn, 200, %{pre_reservation: pre_reservation})

      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "Pre-reservation not found"})
    end
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
        # Verificar si hay pre-reservas pendientes para este turno
        pending_pre_reservations = ElixirFastCharge.Storage.PreReservationAgent.list_pending_pre_reservations_for_shift(shift_id)

        if length(pending_pre_reservations) > 0 do
          send_json_response(conn, 409, %{
            error: "This shift has pending pre-reservations. Direct reservation not allowed.",
            pending_pre_reservations_count: length(pending_pre_reservations),
            message: "Please use the pre-reservation flow: POST /shifts/pre-reservations"
          })
        else
          case ElixirFastCharge.Storage.ShiftAgent.reserve_shift(shift_id, user_id) do
            {:ok, reserved_shift} ->
              send_json_response(conn, 200, %{
                message: "Shift reserved successfully (direct reservation)",
                shift: reserved_shift,
                warning: "Consider using pre-reservations for better experience: POST /shifts/pre-reservations"
              })
            {:error, :shift_not_found} ->
              send_json_response(conn, 404, %{error: "Shift not found"})
            {:error, :shift_not_available} ->
              send_json_response(conn, 400, %{error: "Shift not available"})
            {:error, reason} ->
              send_json_response(conn, 500, %{error: "Failed to reserve shift", reason: inspect(reason)})
          end
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

  # Obtener pre-reservas pendientes para un turno
  get "/:shift_id/pre-reservations" do
    pending_pre_reservations = ElixirFastCharge.Storage.PreReservationAgent.list_pending_pre_reservations_for_shift(shift_id)

    send_json_response(conn, 200, %{
      shift_id: shift_id,
      pending_pre_reservations: pending_pre_reservations,
      count: length(pending_pre_reservations)
    })
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
