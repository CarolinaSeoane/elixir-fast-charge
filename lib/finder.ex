defmodule ElixirFastCharge.Finder do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    IO.puts("Finder distribuido iniciado")
    {:ok, %{}}
  end

  # API Functions

  def add_preference(preference_data) do
    ElixirFastCharge.DistributedPreferenceManager.create_preference(preference_data)
  end

  def get_all_preferences do
    ElixirFastCharge.DistributedPreferenceManager.list_all_preferences()
  end

  def update_preference_alert(preference_id, alert_status) do
    ElixirFastCharge.DistributedPreferenceManager.update_preference_alert(preference_id, alert_status)
  end

  def list_all_stations do
    ElixirFastCharge.DistributedChargingStationManager.list_all_stations()
  end

  def find_station(station_id) do
    ElixirFastCharge.DistributedChargingStationManager.get_station(station_id)
  end

  def send_alerts(shift) do
    # Usar el sistema distribuido para encontrar usuarios a notificar
    users_to_notify = ElixirFastCharge.DistributedPreferenceManager.find_users_to_notify(shift)

    # Notificar a cada usuario
    Enum.each(users_to_notify, fn user_info ->
      notify_user(user_info, shift)
    end)

    # Retornar conteo
    length(users_to_notify)
  end

  def find_matching_preferences_for_shift(shift) do
    ElixirFastCharge.DistributedPreferenceManager.find_matching_preferences_for_shift(shift)
  end

  # Private Functions

  defp notify_user(user_info, shift) do
    username = user_info.username

    case ElixirFastCharge.DistributedUserManager.get_user(username) do
      {:ok, user} ->
        notification = build_notification_message(shift, user_info)

        # En un sistema real, aquí enviarías email, SMS, push notification, etc.
        # Por ahora solo loggeamos
        IO.puts("🔔 ALERTA enviada a #{username}: #{notification}")

        # Opcional: También podrías almacenar la notificación en el sistema
        store_notification(username, notification)

        {:ok, :sent}

      {:error, :not_found} ->
        IO.puts("Usuario #{username} no encontrado - notificación no enviada")
        {:error, :user_not_found}
    end
  end

  defp build_notification_message(shift, user_info) do
    "¡Nuevo turno disponible con #{user_info.match_percentage}% de coincidencia! " <>
    "Estación: #{shift.station_id}, " <>
    "Punto: #{shift.point_id}, " <>
    "Hora: #{format_datetime(shift.start_time)} - #{format_datetime(shift.end_time)}, " <>
    "Potencia: #{shift.power_kw}kW, " <>
    "Conector: #{shift.connector_type}"
  end

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
    |> String.slice(0, 16)  # YYYY-MM-DD HH:MM
  end

  defp store_notification(username, message) do
    # En un sistema real, aquí almacenarías la notificación en una base de datos
    # Por ahora solo loggeamos que se almacenó
    IO.puts("Notificación almacenada para #{username}")
  end
end
