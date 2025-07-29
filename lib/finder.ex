defmodule ElixirFastCharge.Finder do
  use Horde.DynamicSupervisor

  def start_link(_opts) do
    Horde.DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__, members: :auto)
  end

  @impl true
  def init(_opts) do
    # Iniciar los agents
    Task.start(fn ->
      Process.sleep(1000)
      start_storage_agents()
    end)

    Horde.DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_storage_agents do
    children = [
      {ElixirFastCharge.Storage.PreReservationAgent, []},
      {ElixirFastCharge.Storage.ShiftAgent, []},
      {ElixirFastCharge.Preferences, %{}}
    ]

    Enum.each(children, fn child_spec ->
      Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
    end)
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

    result = Enum.all?(preference, fn {key, value} ->
      if key in filter_fields do
        # Skip system fields
        true
      else
        shift_value = Map.get(shift, key)

        # Normalize both values for comparison (convert atoms to strings)
        normalized_shift_value = if is_atom(shift_value), do: Atom.to_string(shift_value), else: shift_value
        normalized_pref_value = if is_atom(value), do: Atom.to_string(value), else: value

        match_result = normalized_shift_value == normalized_pref_value

        # Criteria field must match the shift
        match_result
      end
    end)

    result
  end

  defp notify_user(preference, shift) do
    username = Map.get(preference, :username)

    case Horde.Registry.lookup(ElixirFastCharge.UserRegistry, username) do
      [{user_pid, _}] ->
        notification = "New shift available! Station: #{shift.station_id}, Point: #{shift.point_id}, Time: #{shift.start_time} - #{shift.end_time}"
        ElixirFastCharge.User.send_notification(user_pid, notification)
        IO.puts("ALERT sent to #{username} (node: #{node(user_pid)})")

      [] ->
        IO.puts("User #{username} not found in cluster - notification not sent")
    end
  end

end
