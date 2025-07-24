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
          ElixirFastCharge.Finder.add_preference(preference_data)

          send_json_response(conn, 201, %{
            message: "Preference created successfully",
            preference: preference_data
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

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

end
