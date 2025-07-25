defmodule ElixirFastCharge.Finder do
  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    IO.puts("Finder supervisor started")

    children = [
      {ElixirFastCharge.Preferences, %{}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def add_preference(preference_data) do
    ElixirFastCharge.Preferences.add_preference(preference_data)
  end

  def get_all_preferences do
    ElixirFastCharge.Preferences.get_all_preferences()
  end

  def update_preference_alert(username, preference_id, alert_status) do
    ElixirFastCharge.Preferences.update_preference_alert(username, preference_id, alert_status)
  end

  def list_all_stations do
    ElixirFastCharge.ChargingStations.StationRegistry.list_stations()
    |> Enum.to_list()
  end

  def find_station(station_id) do
    case ElixirFastCharge.ChargingStations.StationRegistry.get_station(station_id) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end
end
