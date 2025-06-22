defmodule ElixirFastCharge.User do
  use GenServer

  def start_link(default) do
    GenServer.start_link(__MODULE__, default, name: __MODULE__)
  end

  # @impl true
  def init(initial_state) do
    IO.puts("User started")
    {:ok, initial_state}
  end

  def healthcheck do
    GenServer.call(__MODULE__, {:healthcheck})
  end

  # @impl true
  def handle_call({:healthcheck}, _from, state) do
    {:reply, "User running", state}
  end

end
