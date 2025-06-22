defmodule ElixirFastCharge.UserRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  post "/sign-up" do
    send_resp(conn, 200, "Welcome to /sign-up")
  end

  match _ do
    send_resp(conn, 404, "Oops!")
  end

end
