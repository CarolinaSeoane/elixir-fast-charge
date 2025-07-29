defmodule ElixirFastCharge.DistributedDataLoader do
  @moduledoc """
  GenServer para cargar datos iniciales en el sistema distribuido.
  Se ejecuta automáticamente al iniciar la aplicación.
  """
  use GenServer
  require Logger

  # API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def load_initial_data() do
    GenServer.cast(__MODULE__, :load_initial_data)
  end

  def get_loading_status() do
    GenServer.call(__MODULE__, :get_status)
  end

  # GenServer Callbacks

  @impl true
  def init(state) do
    # Cargar datos iniciales después de 10 segundos (para dar tiempo a que se inicialice Horde)
    Process.send_after(self(), :auto_load_data, 10_000)

    Logger.info("DistributedDataLoader iniciado - cargará datos en 10 segundos")

    initial_state = %{
      loaded: false,
      loading: false,
      load_attempts: 0,
      last_load_time: nil,
      errors: []
    }

    {:ok, Map.merge(state, initial_state)}
  end

  @impl true
  def handle_info(:auto_load_data, state) do
    Logger.info("Iniciando carga automática de datos iniciales...")
    new_state = perform_data_loading(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:load_initial_data, state) do
    Logger.info(" Carga manual de datos iniciales solicitada...")
    new_state = perform_data_loading(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      loaded: state.loaded,
      loading: state.loading,
      load_attempts: state.load_attempts,
      last_load_time: state.last_load_time,
      errors: state.errors
    }
    {:reply, status, state}
  end

  # Private Functions

  defp perform_data_loading(state) do
    if state.loaded do
      Logger.info("Datos ya cargados previamente, omitiendo...")
      state
    else
      Logger.info(" Iniciando carga de datos distribuidos...")

      updated_state = %{state | loading: true, load_attempts: state.load_attempts + 1}

      try do
        # Cargar estaciones por defecto
        stations_result = load_default_stations()

        # Cargar turnos de ejemplo
        shifts_result = load_sample_shifts()

        # Cargar usuarios de prueba
        users_result = load_sample_users()

        # Cargar preferencias de ejemplo
        preferences_result = load_sample_preferences()

        Logger.info(" Carga de datos completada exitosamente")
        Logger.info("Resultados: Estaciones: #{stations_result}, Turnos: #{shifts_result}, Usuarios: #{users_result}, Preferencias: #{preferences_result}")

        %{updated_state |
          loaded: true,
          loading: false,
          last_load_time: DateTime.utc_now()
        }

      rescue
        error ->
          Logger.error("Error durante la carga de datos: #{inspect(error)}")

          %{updated_state |
            loading: false,
            errors: [error | state.errors]
          }
      end
    end
  end

  defp load_default_stations() do
    stations_data = [
      %{
        station_id: "station_centro_001",
        name: "Centro Comercial Norte",
        location: %{
          address: "Av. Principal 1234, Ciudad",
          city: "Buenos Aires",
          coordinates: %{lat: -34.6037, lng: -58.3816}
        },
        status: :active,
        charging_points: [
          %{point_id: "punto_a1", connector_type: :ccs, power_kw: 150, status: :available},
          %{point_id: "punto_a2", connector_type: :type2, power_kw: 22, status: :available}
        ]
      },
      %{
        station_id: "station_oeste_002",
        name: "Estación Oeste Rápida",
        location: %{
          address: "Ruta 8 Km 45, Zona Oeste",
          city: "La Plata",
          coordinates: %{lat: -34.9214, lng: -57.9544}
        },
        status: :active,
        charging_points: [
          %{point_id: "punto_b1", connector_type: :ccs, power_kw: 200, status: :available},
          %{point_id: "punto_b2", connector_type: :chademo, power_kw: 50, status: :available}
        ]
      },
      %{
        station_id: "station_aeropuerto_003",
        name: "Terminal Aeroportuaria",
        location: %{
          address: "Aeropuerto Internacional",
          city: "Ezeiza",
          coordinates: %{lat: -34.8222, lng: -58.5358}
        },
        status: :active,
        charging_points: [
          %{point_id: "punto_c1", connector_type: :ccs, power_kw: 350, status: :available},
          %{point_id: "punto_c2", connector_type: :type2, power_kw: 43, status: :available}
        ]
      }
    ]

    results = stations_data
    |> Enum.map(fn station_data ->
      case ElixirFastCharge.DistributedChargingStationManager.create_station(station_data) do
        {:ok, _pid} -> :ok
        {:error, :station_already_exists} -> :ok  # Ya existe, no es error
        {:error, _reason} -> :error
      end
    end)

    successful = Enum.count(results, fn result -> result == :ok end)
    Logger.info("Estaciones cargadas: #{successful}/#{length(stations_data)}")
    successful
  end

  defp load_sample_shifts() do
    now = DateTime.utc_now()

    shifts_data = [
      %{
        station_id: "station_centro_001",
        point_id: "punto_a1",
        connector_type: :ccs,
        power_kw: 150,
        location: %{address: "Av. Principal 1234, Ciudad"},
        start_time: DateTime.add(now, 2 * 3600, :second),  # En 2 horas
        end_time: DateTime.add(now, 4 * 3600, :second),    # En 4 horas
        expires_at: DateTime.add(now, 30 * 60, :second)    # Expira en 30 min
      },
      %{
        station_id: "station_oeste_002",
        point_id: "punto_b1",
        connector_type: :ccs,
        power_kw: 200,
        location: %{address: "Ruta 8 Km 45, Zona Oeste"},
        start_time: DateTime.add(now, 3 * 3600, :second),  # En 3 horas
        end_time: DateTime.add(now, 5 * 3600, :second),    # En 5 horas
        expires_at: DateTime.add(now, 45 * 60, :second)    # Expira en 45 min
      },
      %{
        station_id: "station_aeropuerto_003",
        point_id: "punto_c1",
        connector_type: :ccs,
        power_kw: 350,
        location: %{address: "Aeropuerto Internacional"},
        start_time: DateTime.add(now, 1 * 3600, :second),  # En 1 hora
        end_time: DateTime.add(now, 3 * 3600, :second),    # En 3 horas
        expires_at: DateTime.add(now, 60 * 60, :second)    # Expira en 1 hora
      },
      %{
        station_id: "station_centro_001",
        point_id: "punto_a2",
        connector_type: :type2,
        power_kw: 22,
        location: %{address: "Av. Principal 1234, Ciudad"},
        start_time: DateTime.add(now, 6 * 3600, :second),  # En 6 horas
        end_time: DateTime.add(now, 10 * 3600, :second),   # En 10 horas
        expires_at: DateTime.add(now, 2 * 3600, :second)   # Expira en 2 horas
      }
    ]

    results = shifts_data
    |> Enum.map(fn shift_data ->
      case ElixirFastCharge.DistributedShiftManager.create_shift(shift_data) do
        {:ok, _shift} -> :ok
        {:error, _reason} -> :error
      end
    end)

    successful = Enum.count(results, fn result -> result == :ok end)
    Logger.info(" Turnos cargados: #{successful}/#{length(shifts_data)}")
    successful
  end

  defp load_sample_users() do
    users_data = [
      %{username: "admin", password: "admin123", metadata: %{role: "admin", mail: "admin@elixirfastcharge.com"}},
      %{username: "user_demo", password: "demo123", metadata: %{role: "user", mail: "demo@elixirfastcharge.com"}},
      %{username: "test_user", password: "test123", metadata: %{role: "test", mail: "test@elixirfastcharge.com"}}
    ]

    results = users_data
    |> Enum.map(fn user_data ->
      case ElixirFastCharge.DistributedUserManager.create_user(user_data.username, user_data.password, user_data.metadata) do
        {:ok, _pid} -> :ok
        {:error, :username_taken} -> :ok  # Ya existe, no es error
        {:error, _reason} -> :error
      end
    end)

    successful = Enum.count(results, fn result -> result == :ok end)
    Logger.info(" Usuarios cargados: #{successful}/#{length(users_data)}")
    successful
  end

  defp load_sample_preferences() do
    preferences_data = [
      %{
        username: "user_demo",
        station_id: "station_centro_001",
        connector_type: :ccs,
        power_kw: 150,
        location: "Centro",
        fecha: Date.add(Date.utc_today(), 1) |> Date.to_iso8601(),
        hora_inicio: "09:00",
        hora_fin: "18:00",
        alert: true,
        priority: :high
      },
      %{
        username: "test_user",
        station_id: "station_aeropuerto_003",
        connector_type: :ccs,
        power_kw: 350,
        location: "Aeropuerto",
        fecha: Date.add(Date.utc_today(), 2) |> Date.to_iso8601(),
        hora_inicio: "06:00",
        hora_fin: "22:00",
        alert: true,
        priority: :normal
      }
    ]

    results = preferences_data
    |> Enum.map(fn preference_data ->
      case ElixirFastCharge.DistributedPreferenceManager.create_preference(preference_data) do
        {:ok, _pid} -> :ok
        {:error, :user_not_found} -> :ok  # Usuario no existe, omitir
        {:error, _reason} -> :error
      end
    end)

    successful = Enum.count(results, fn result -> result == :ok end)
    Logger.info(" Preferencias cargadas: #{successful}/#{length(preferences_data)}")
    successful
  end
end
