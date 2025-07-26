defmodule ElixirFastCharge.UserRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/" do
    users_raw = ElixirFastCharge.UserDynamicSupervisor.list_users()

    users = users_raw
    |> Enum.map(fn {username, pid} ->
      %{
        username: username,
        pid: inspect(pid)
      }
    end)

    send_json_response(conn, 200, %{
      users: users,
      count: length(users)
    })
  end

  post "/sign-up" do
    case extract_signup_params(conn.body_params) do
      {:ok, username, password} ->
        case ElixirFastCharge.UserDynamicSupervisor.create_user(username, password) do
          {:ok, user_pid} ->
            send_json_response(conn, 201, %{
              message: "User created successfully",
              username: username,
              user_pid: inspect(user_pid)
            })

          {:error, :username_taken} ->
            send_json_response(conn, 400, %{
              error: "Username taken"
            })

          {:error, reason} ->
            send_json_response(conn, 500, %{
              error: "Failed to create user",
              reason: inspect(reason)
            })
        end

      {:error, error_message} ->
        send_json_response(conn, 400, %{error: error_message})
    end
  end

  post "/preferences" do
    case extract_preference_params(conn.body_params) do
      {:ok, preference_data} ->
        try do
          created_preference = ElixirFastCharge.Finder.add_preference(preference_data)

          send_json_response(conn, 201, %{
            message: "Preference created successfully",
            preference: created_preference
          })
        rescue
          error ->
            send_json_response(conn, 500, %{
              error: "Failed to create preference",
              reason: inspect(error)
            })
        end

      {:error, error_message} ->
        send_json_response(conn, 400, %{error: error_message})
    end
  end

  get "/preferences" do
    preferences = ElixirFastCharge.Finder.get_all_preferences()

    send_json_response(conn, 200, %{
      preferences: preferences,
      count: length(preferences)
    })
  end

  get "/:username/preferences" do
      user_preferences = ElixirFastCharge.Preferences.get_preferences_by_user(username)
      send_json_response(conn, 200, %{
        preferences: user_preferences,
        preferences_count: length(user_preferences)
      })
  end

  get "/:username/shifts" do
    try do
      user_preferences = ElixirFastCharge.Preferences.get_preferences_by_user(username)
      active_shifts = ElixirFastCharge.Storage.ShiftAgent.list_active_shifts()

      # Para cada turno, contar cuántas preferencias lo matchean al 100%
      shifts_with_match_count = active_shifts
      |> Enum.map(fn shift ->
        matching_preferences_count = count_matching_preferences(shift, user_preferences)

        shift
        |> Map.put(:matching_preferences_count, matching_preferences_count)
      end)
      |> Enum.sort_by(& &1.matching_preferences_count, :desc)

      send_json_response(conn, 200, %{
        shifts: shifts_with_match_count,
        username: username,
        preferences_count: length(user_preferences)
      })
    rescue
      error ->
        send_json_response(conn, 500, %{
          error: "Failed to retrieve shifts",
          reason: inspect(error)
        })
    end
  end

  put "/alert" do
    case extract_alert_params(conn.body_params) do
      {:ok, username, preference_id, alert_status} ->
        case ElixirFastCharge.Finder.update_preference_alert(username, preference_id, alert_status) do
          {:ok, updated_preference} ->
            send_json_response(conn, 200, %{
              message: "Alert updated successfully",
              alert: alert_status,
              preference: updated_preference
            })

          {:error, :preference_not_found} ->
            send_json_response(conn, 404, %{
              error: "Preference not found"
            })

          {:error, reason} ->
            send_json_response(conn, 500, %{
              error: "Failed to update alert",
              reason: inspect(reason)
            })
        end

      {:error, error_message} ->
        send_json_response(conn, 400, %{error: error_message})
    end
  end

  get "/health" do
    send_json_response(conn, 200, %{
      status: "ok",
      timestamp: DateTime.utc_now()
    })
  end

  match _ do
    send_json_response(conn, 404, %{error: "Route not found"})
  end

  defp extract_signup_params(body_params) do
    case body_params do
      %{"username" => username, "password" => password}
        when is_binary(username) and is_binary(password) ->
        {:ok, username, password}

      %{"username" => _, "password" => _} ->
        {:error, "username and password must be strings"}

      _ ->
        {:error, "username and password are required"}
    end
  end

  defp extract_preference_params(body_params) do
    case body_params do
      params when is_map(params) and map_size(params) > 0 ->
        preference_data =
          params
          |> Enum.map(fn {key, value} -> {String.to_atom(key), value} end)
          |> Enum.into(%{})
          |> Map.put(:alert, false)
        {:ok, preference_data}
      _ ->
        {:error, "Invalid preference data"}
    end
  end

  defp count_matching_preferences(shift, user_preferences) do
    # Contar cuántas preferencias matchean al 100% con este turno
    Enum.count(user_preferences, fn preference ->
      preference_matches_shift_completely?(preference, shift)
    end)
  end

  defp preference_matches_shift_completely?(preference, shift) do
    system_fields = [:alert, :preference_id, :timestamp, :username]

    # Verificar que todos los campos de la preferencia (excepto los del sistema) coincidan con el turno
    result = Enum.all?(preference, fn {key, value} ->
      if key in system_fields do
        true
      else
        shift_value = Map.get(shift, key)

        # Convertir atoms a strings si es necesario para comparación
        normalized_shift_value = if is_atom(shift_value), do: Atom.to_string(shift_value), else: shift_value
        normalized_pref_value = if is_atom(value), do: Atom.to_string(value), else: value
        match_result = normalized_shift_value == normalized_pref_value
        match_result
      end
    end)
    result
  end

  defp extract_alert_params(body_params) do
    case body_params do
      %{"username" => username, "preference_id" => preference_id, "alert" => alert}
        when is_binary(username) and is_integer(preference_id) and is_boolean(alert) ->
        {:ok, username, preference_id, alert}

      %{"username" => _, "preference_id" => _, "alert" => _} ->
        {:error, "username must be string, preference_id must be number, alert must be boolean"}

      _ ->
        {:error, "username, preference_id, and alert are required"}
    end
  end

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

end
