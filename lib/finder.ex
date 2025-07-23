defmodule ElixirFastCharge.Finder do
  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    IO.puts("Finder supervisor started")

    children = [
      ElixirFastCharge.Preferences
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def add_preference(preference_data) do
    ElixirFastCharge.Preferences.add_preference(preference_data)
  end

  def get_all_preferences do
    ElixirFastCharge.Preferences.get_all_preferences()
  end
end
