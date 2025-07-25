"
preference = {
  username:
  station_id:
  connector_type:
  power:
  location:
}
"

defmodule ElixirFastCharge.Preferences do
  use Agent

  def start_link(initial_state \\ []) do
    Agent.start_link(fn -> initial_state end, name: __MODULE__)
  end

  def add_preference(preference_data) when is_map(preference_data) do
    preference = Map.put_new(preference_data, :timestamp, DateTime.utc_now())
    Agent.update(__MODULE__, fn preferences -> [preference | preferences] end)
  end

  def get_all_preferences do
    Agent.get(__MODULE__, & &1)
  end

  def get_preferences_by_user(usuario) do
    Agent.get(__MODULE__, fn preferences ->
      Enum.filter(preferences, fn pref -> Map.get(pref, :username) == usuario end)
    end)
  end
  def delete_preferences_by_user(usuario) do
    Agent.update(__MODULE__, fn preferences ->
      Enum.reject(preferences, fn pref -> Map.get(pref, :username) == usuario end)
    end)
  end

  def find_preferences(criteria) do
    Agent.get(__MODULE__, fn preferences ->
      Enum.filter(preferences, fn pref ->
        Enum.all?(criteria, fn {key, value} ->
          Map.get(pref, key) == value
        end)
      end)
    end)
  end
end
