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

      IO.inspect(active_shifts, label: "Active shifts")

      # Calcular score para cada turno y ordenar
      shifts_with_scores = active_shifts
      |> Enum.map(fn shift ->
        preference_details = calculate_preference_details(shift, user_preferences)
        total_score = Enum.sum(Enum.map(preference_details, & &1.score))

        shift
        |> Map.put(:preference_score, total_score)
        |> Map.put(:preference_details, preference_details)
      end)
      |> Enum.sort_by(& &1.preference_score, :desc)

      send_json_response(conn, 200, %{
        shifts: shifts_with_scores,
        # count: length(shifts_with_scores),
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

  get "/preferences" do
    preferences = ElixirFastCharge.Finder.get_all_preferences()

    send_json_response(conn, 200, %{
      preferences: preferences,
      count: length(preferences)
    })
  end

  get "/:username/notifications" do
    case Registry.lookup(ElixirFastCharge.UserRegistry, username) do
      [{user_pid, _}] ->
        notifications = ElixirFastCharge.User.get_notifications(user_pid)

        send_json_response(conn, 200, %{
          username: username,
          notifications: notifications,
          count: length(notifications)
        })

      [] ->
        send_json_response(conn, 404, %{
          error: "User not found"
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
        IO.puts("preference_data: #{inspect(preference_data)}")
        {:ok, preference_data}
      _ ->
        {:error, "Invalid preference data"}
    end
  end

  # defp calculate_preference_details(shift, user_preferences) do
  #   if Enum.empty?(user_preferences) do
  #     []
  #   else
  #     user_preferences
  #     |> Enum.with_index()
  #     |> Enum.map(fn {preference, index} ->
  #       score = calculate_single_preference_score(shift, preference)
  #       matches = get_preference_matches(shift, preference)

  #       %{
  #         preference_id: index,
  #         score: score,
  #         matches: matches,
  #         preference_data: preference
  #       }
  #     end)
  #   end
  # end

  defp calculate_preference_details(shift, user_preferences) do
    if Enum.empty?(user_preferences) do
      []
    else
      user_preferences
      |> Enum.with_index()
      |> Enum.map(fn {preference, index} ->
        {score, matches_log, matches_map} = match_and_score(shift, preference)

        IO.puts("🔎 Preference ##{index} for Shift ID: #{shift.shift_id}")
        Enum.each(matches_log, &IO.puts(&1))

        %{
          preference_id: index,
          score: score,
          matches: matches_map,
          preference_data: preference
        }
      end)
    end
  end

  defp match_and_score(shift, preference) do
    expected_station = Map.get(preference, :station_id)
    actual_station = Atom.to_string(shift.station_id)
    station_match = expected_station == actual_station

    expected_connector = Map.get(preference, :connector_type)
    actual_connector = Atom.to_string(shift.connector_type)
    connector_match = expected_connector == actual_connector

    expected_power = Map.get(preference, :power)
    actual_power = shift.power_kw
    power_match = expected_power == actual_power

    location_pref = Map.get(preference, :location)
    actual_location = get_station_location(shift.station_id)
    location_match = location_pref == actual_location

    matches = %{
      station_id: station_match,
      connector_type: connector_match,
      power: power_match,
      location: location_match
    }

    log = [
      "  🔁 station_id match: #{station_match} (expected: #{expected_station}, got: #{actual_station})",
      "  🔌 connector_type match: #{connector_match} (expected: #{expected_connector}, got: #{actual_connector})",
      "  ⚡ power match: #{power_match} (expected: #{expected_power}, got: #{actual_power})",
      "  📍 location match: #{location_match} (expected to include: #{location_pref || "N/A"}, got: #{actual_location})"
    ]

    score = Enum.count(Map.values(matches), & &1)

    {score, log, matches}
  end


  # defp get_preference_matches(shift, preference) do
  #   %{
  #     station_id: Map.get(preference, :station_id) == Atom.to_string(shift.station_id),
  #     connector_type: Map.get(preference, :connector_type) == Atom.to_string(shift.connector_type),
  #     power: Map.get(preference, :power) == shift.power_kw,
  #     location: Map.get(preference, :location) && String.contains?(get_station_location(shift.station_id), Map.get(preference, :location)),
  #     # date: check_date_preference(preference, shift)
  #   }
  # end

  # defp calculate_single_preference_score(shift, preference) do
  #   matches = get_preference_matches(shift, preference)

  #   matches
  #   |> Map.values()
  #   |> Enum.count(& &1)
  # end

  defp get_station_location(station_id) do
    case ElixirFastCharge.ChargingStations.ChargingStation.get_location(station_id) do
      %{address: address} -> address
      _ -> ""
    end
  rescue
    _ -> ""
  end

  defp check_date_preference(preference, shift) do
    case Map.get(preference, :fecha) do
      nil -> false
      fecha_str ->
        case Date.from_iso8601(fecha_str) do
          {:ok, fecha_preferencia} ->
            shift_date = DateTime.to_date(shift.start_time)
            Date.compare(fecha_preferencia, shift_date) == :eq
          _ -> false
        end
    end
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
