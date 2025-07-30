defmodule ElixirFastCharge.MainRouter do
  use Plug.Router

  plug CORSPlug, origin: ["http://localhost:3000"]

  plug :match
  plug :telemetry_wrapper
  plug Plug.Parsers, parsers: [:json],
                     pass: ["application/json"],
                     json_decoder: Jason
  plug :dispatch

  forward "/users", to: ElixirFastCharge.UserRouter

  forward "/stations", to: ElixirFastCharge.StationRouter

  forward "/shifts", to: ElixirFastCharge.ShiftRouter

  match "/metrics" do
    metrics = TelemetryMetricsPrometheus.Core.scrape()

    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> send_resp(200, metrics)
  end

  match _ do
    send_json_response(conn, 404, %{
      error: "Route not found"
    })
  end

  defp telemetry_wrapper(conn, _opts) do
    start_time = System.monotonic_time()

    Plug.Conn.register_before_send(conn, fn conn ->
      duration = System.monotonic_time() - start_time

      :telemetry.execute([:plug, :router, :call], %{duration: duration}, %{
        method: conn.method,
        path_info: Enum.join(conn.path_info, "/"),
        status: conn.status
      })

      conn
    end)
  end

  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
