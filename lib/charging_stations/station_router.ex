defmodule ElixirFastCharge.StationRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/" do
    stations = ElixirFastCharge.ChargingStationSupervisor.list_charging_stations()

    send_json_response(conn, 200, %{
      stations: stations,
      count: length(stations)
    })
  end

  match _ do
    send_json_response(conn, 404, %{error: "Station route not found"})
  end

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
