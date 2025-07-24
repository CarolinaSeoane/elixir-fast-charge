defmodule ElixirFastCharge.Preferences do
  use Agent

  def start_link(initial_state \\ %{}) do
    Agent.start_link(fn -> initial_state end, name: __MODULE__)
  end

  defp generate_preference_id do
    System.unique_integer([:positive])
  end

  def add_preference(preference_data) when is_map(preference_data) do
    preference_id = generate_preference_id()
    preference =
      preference_data
      |> Map.put_new(:timestamp, DateTime.utc_now())
      |> Map.put(:preference_id, preference_id)

    Agent.update(__MODULE__, fn preferences ->
      Map.put(preferences, preference_id, preference)
    end)
    preference
  end

  def get_all_preferences do
    Agent.get(__MODULE__, fn preferences ->
      Map.values(preferences)
    end)
  end

  def get_preferences_by_user(usuario) do
    Agent.get(__MODULE__, fn preferences ->
      preferences
      |> Map.values()
      |> Enum.filter(fn pref -> Map.get(pref, :username) == usuario end)
    end)
  end
  def delete_preferences_by_user(usuario) do
    Agent.update(__MODULE__, fn preferences ->
      Enum.reject(preferences, fn {_id, pref} -> Map.get(pref, :username) == usuario end)
      |> Enum.into(%{})
    end)
  end

  def find_preferences(criteria) do
    Agent.get(__MODULE__, fn preferences ->
      preferences
      |> Map.values()
      |> Enum.filter(fn pref ->
        Enum.all?(criteria, fn {key, value} ->
          Map.get(pref, key) == value
        end)
      end)
    end)
  end

    def update_preference_alert(username, preference_id, alert_status) do
    Agent.get_and_update(__MODULE__, fn preferences ->
      case Map.get(preferences, preference_id) do
        nil ->
          {{:error, :preference_not_found}, preferences}

        preference ->
          # Verify preference belongs to the user
          if Map.get(preference, :username) == username do
            updated_pref = Map.put(preference, :alert, alert_status)
            {{:ok, updated_pref}, Map.put(preferences, preference_id, updated_pref)}
          else
            {{:error, :preference_not_found}, preferences}
          end
      end
    end)
  end

end
