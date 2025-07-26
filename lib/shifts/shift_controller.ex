defmodule ElixirFastCharge.Shifts.ShiftController do
  @moduledoc """
  Controller que maneja la lógica de negocio para turnos,
  incluyendo ordenamiento por preferencias del usuario.
  """

  def list_active_shifts_ordered(user_preferences \\ %{}) do
    shifts = ElixirFastCharge.Storage.ShiftAgent.list_active_shifts()
    order_shifts_by_preferences(shifts, user_preferences)
  end

    def list_active_shifts_for_user(user_id) do
    case get_user_preferences(user_id) do
      {:ok, preferences} ->
        shifts = ElixirFastCharge.Storage.ShiftAgent.list_active_shifts()
        ordered_shifts = order_shifts_by_preferences(shifts, preferences)
        {:ok, ordered_shifts, preferences}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_inactive_shifts do
    ElixirFastCharge.Storage.ShiftAgent.list_inactive_shifts()
  end

  def get_shift_counts do
    total_count = ElixirFastCharge.Storage.ShiftAgent.count_shifts()
    active_count = ElixirFastCharge.Storage.ShiftAgent.count_active_shifts()

    %{
      total_shifts: total_count,
      active_shifts: active_count,
      inactive_shifts: total_count - active_count
    }
  end

  def parse_user_preferences(query_params) do
    %{
      connector_type: parse_connector_type(query_params["connector_type"]),
      station_id: parse_station_id(query_params["station_id"]),
      min_power: parse_integer(query_params["min_power"]),
      max_power: parse_integer(query_params["max_power"]),
      preferred_start_hour: parse_integer(query_params["preferred_start_hour"])
    }
  end

  # === PRIVATE FUNCTIONS ===

  defp get_user_preferences(user_id) do
    case ElixirFastCharge.UserDynamicSupervisor.get_user(user_id) do
      {:ok, user_pid} ->
        preferences = ElixirFastCharge.User.get_preferences(user_pid)
        {:ok, preferences}

      {:error, :not_found} ->
        {:error, :user_not_found}
    end
  end

  defp order_shifts_by_preferences(shifts, preferences) do
    # Dividir turnos en dos grupos: que matchean preferencias y que no
    {matching_shifts, non_matching_shifts} =
      Enum.split_with(shifts, fn shift ->
        matches_preferences?(shift, preferences)
      end)

    # Ordenar cada grupo internamente por prioridad
    sorted_matching = Enum.sort_by(matching_shifts, &shift_priority(&1, preferences), :desc)
    sorted_non_matching = Enum.sort_by(non_matching_shifts, &shift_priority(&1, preferences), :desc)

    # Concatenar: preferidos primero
    sorted_matching ++ sorted_non_matching
  end

    defp matches_preferences?(shift, preferences) do
    connector_match = is_nil(preferences.connector_type) or shift.connector_type == preferences.connector_type
    station_match = Enum.empty?(preferences.preferred_stations) or shift.station_id in preferences.preferred_stations
    power_min_match = is_nil(preferences.min_power) or shift.power_kw >= preferences.min_power
    power_max_match = is_nil(preferences.max_power) or shift.power_kw <= preferences.max_power

    connector_match and station_match and power_min_match and power_max_match
  end

  defp shift_priority(shift, preferences) do
    priority = 0

    # Bonificar por coincidencia exacta de conector
    priority = if shift.connector_type == preferences.connector_type, do: priority + 100, else: priority

    # Bonificar por estación preferida (usar preferred_stations lista)
    priority = if shift.station_id in preferences.preferred_stations, do: priority + 50, else: priority

    # Bonificar por potencia más alta
    priority = priority + shift.power_kw

    # Por ahora omitimos el cálculo de tiempo para evitar problemas
    # TODO: Agregar bonificación por tiempo de manera más segura

    priority
  end

  defp parse_connector_type(nil), do: nil
  defp parse_connector_type("ccs"), do: :ccs
  defp parse_connector_type("chademo"), do: :chademo
  defp parse_connector_type("type2"), do: :type2
  defp parse_connector_type(_), do: nil

  defp parse_station_id(nil), do: nil
  defp parse_station_id(station_str) when is_binary(station_str) do
    try do
      String.to_atom(station_str)
    rescue
      _ -> nil
    end
  end
  defp parse_station_id(_), do: nil

  defp parse_integer(nil), do: nil
  defp parse_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end
  defp parse_integer(_), do: nil
end
