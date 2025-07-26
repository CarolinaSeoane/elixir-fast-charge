defmodule ElixirFastCharge.UserRouter do
  use Plug.Router

  plug CORSPlug, origin: ["http://localhost:4003"]
  plug :match
  plug Plug.Parsers, parsers: [:json],
                     pass: ["application/json"],
                     json_decoder: Jason
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

  get "/health" do
    send_json_response(conn, 200, %{
      status: "ok",
      timestamp: DateTime.utc_now()
    })
  end

  put "/:username/preferences" do
    case ElixirFastCharge.UserDynamicSupervisor.get_user(username) do
      {:ok, user_pid} ->
        new_preferences = %{
          connector_type: parse_connector_type(conn.body_params["connector_type"]),
          min_power: conn.body_params["min_power"],
          max_power: conn.body_params["max_power"],
          preferred_stations: conn.body_params["preferred_stations"] || []
        }

        ElixirFastCharge.User.update_preferences(user_pid, new_preferences)

        send_json_response(conn, 200, %{
          message: "Preferences updated successfully",
          username: username,
          preferences: new_preferences
        })

      {:error, :not_found} ->
        send_json_response(conn, 404, %{error: "User not found"})
    end
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

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp parse_connector_type(nil), do: nil
  defp parse_connector_type("ccs"), do: :ccs
  defp parse_connector_type("chademo"), do: :chademo
  defp parse_connector_type("type2"), do: :type2
  defp parse_connector_type(_), do: nil

end
