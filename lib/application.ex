defmodule ElixirFastCharge.Application do

  use Application

  # @impl true
  def start(_type, _args) do
    children = [
      {ElixirFastCharge.Finder, []},
      {ElixirFastCharge.UserDynamicSupervisor, []},
      {DynamicSupervisor, strategy: :one_for_one, name: ElixirFastCharge.ChargingStationSupervisor},
      # HTTP server
      {Plug.Cowboy, scheme: :http, plug: ElixirFastCharge.UserRouter, options: [port: 4000]}
    ]

    opts = [strategy: :one_for_one, name: ElixirFastCharge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
