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

  def send_alerts(shift) do
    preferences_with_alerts = get_preferences_with_alerts()

    # Find preferences that match this shift
    matching_preferences = find_matching_preferences(preferences_with_alerts, shift)

    Enum.each(matching_preferences, fn preference ->
      notify_user(preference, shift)
    end)

    # Return count
    length(matching_preferences)
  end

  defp get_preferences_with_alerts do
    get_all_preferences()
    |> Enum.filter(fn pref -> Map.get(pref, :alert) == true end)
  end

  defp find_matching_preferences(preferences, shift) do
    Enum.filter(preferences, fn preference ->
      preference_matches_shift?(preference, shift)
    end)
  end

  defp preference_matches_shift?(preference, shift) do
    # system fields, not criteria. Must be ignored
    filter_fields = [:alert, :preference_id, :timestamp, :username]

    Enum.all?(preference, fn {key, value} ->
      if key in filter_fields do
        # Skip system fields
        true
      else
        # Criteria field must match the shift
        Map.get(shift, key) == value
      end
    end)
  end

  defp notify_user(preference, shift) do
    username = Map.get(preference, :username)
    case Registry.lookup(ElixirFastCharge.UserRegistry, username) do
      [{user_pid, _}] ->
        notification = "New shift available! Station: #{shift.station_id}, Point: #{shift.point_id}, Time: #{shift.start_time} - #{shift.end_time}"
        ElixirFastCharge.User.send_notification(user_pid, notification)
        IO.puts("ALERT sent to #{username}")

      [] ->
        IO.puts("User #{username} not found - notification not sent")
    end
  end

end
