defmodule ElixirFastCharge.MainRouter do
  use Plug.Router

  plug CORSPlug, origin: ["http://localhost:4003"]

  plug :match
  plug Plug.Parsers, parsers: [:json],
                     pass: ["application/json"],
                     json_decoder: Jason
  plug :dispatch

  forward "/users", to: ElixirFastCharge.UserRouter

  forward "/stations", to: ElixirFastCharge.StationRouter

  forward "/shifts", to: ElixirFastCharge.ShiftRouter

  match _ do
    send_json_response(conn, 404, %{
      error: "Route not found"
    })
  end

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
