defmodule ElixirFastCharge.Application do

  use Application

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT") || "5014")

    children = [
      # 1. libcluster para descubrimiento de nodos (PRIMERO)
      {Cluster.Supervisor, [topologies(), [name: ElixirFastCharge.ClusterSupervisor]]},

      {Horde.Registry, [
        name: ElixirFastCharge.UserRegistry,
        keys: :unique,
        members: :auto
      ]},
      {Horde.Registry, [
        name: ElixirFastCharge.ChargingStations.StationRegistry,
        keys: :unique,
        members: :auto
      ]},
      {Horde.Registry, [
        name: ElixirFastCharge.DistributedStorageRegistry,
        keys: :unique,
        members: :auto
      ]},

      {Horde.DynamicSupervisor, [
        name: ElixirFastCharge.UserDynamicSupervisor,
        strategy: :one_for_one,
        members: :auto
      ]},
      {Horde.DynamicSupervisor, [
        name: ElixirFastCharge.ChargingStationSupervisor,
        strategy: :one_for_one,
        members: :auto
      ]},

      # otros
      {ElixirFastCharge.Finder, []},
      {ElixirFastCharge.ChargingStations.StationLoader, []},
      {Plug.Cowboy, scheme: :http, plug: ElixirFastCharge.MainRouter, options: [port: port, ref: :http_server]}
    ]

    opts = [strategy: :one_for_one, name: ElixirFastCharge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp topologies do
    [
      local: [
        strategy: Cluster.Strategy.Epmd,
        config: [
          hosts: [
            :"node1@127.0.0.1",
            :"node2@127.0.0.1",
            :"node3@127.0.0.1"
          ]
        ]
      ]
    ]
  end

  @impl true
  def stop(_state) do
    :cowboy.stop_listener(:http_server)
    :ok
  end
end
