defmodule ElixirFastCharge.DistributedPreferenceManager do
  @moduledoc """
  Manager para operaciones distribuidas con preferencias de usuarios.
  Interfaz principal para interactuar con preferencias distribuidas en el cluster.
  """
  require Logger

  # API PRINCIPAL

  def create_preference(preference_data) do
    # Validar que el usuario existe (opcional)
    case validate_user_exists(preference_data.username) do
      true ->
        case ElixirFastCharge.HordeSupervisor.start_child({ElixirFastCharge.DistributedPreference, preference_data}) do
          {:ok, pid} ->
            Logger.info("Preferencia para usuario #{preference_data.username} creada exitosamente en cluster")
            {:ok, pid}

          {:error, reason} ->
            Logger.error(" Error creando preferencia para #{preference_data.username}: #{inspect(reason)}")
            {:error, reason}
        end

      false ->
        {:error, :user_not_found}
    end
  end

  def get_preference(preference_id) do
    ElixirFastCharge.DistributedPreference.get_preference(preference_id)
  end

  def update_preference(preference_id, updates) do
    ElixirFastCharge.DistributedPreference.update_preference(preference_id, updates)
  end

  def update_preference_alert(preference_id, alert_status) do
    ElixirFastCharge.DistributedPreference.update_alert_status(preference_id, alert_status)
  end

  def list_all_preferences() do
    case ElixirFastCharge.HordeRegistry.list_all() do
      processes when is_list(processes) ->
        processes
        |> Enum.filter(fn {{type, _id}, _pid, _value} -> type == :preference end)
        |> Enum.map(fn {{:preference, preference_id}, pid, _value} ->
          case ElixirFastCharge.DistributedPreference.get_preference(preference_id) do
            {:ok, preference} -> preference
            {:error, _} ->
              %{preference_id: preference_id, status: :error, pid: inspect(pid)}
          end
        end)
        |> Enum.reject(fn preference -> preference.status == :error end)

      _ -> []
    end
  end

  def get_preferences_by_user(username) do
    list_all_preferences()
    |> Enum.filter(fn preference -> preference.username == username end)
  end

  def get_preferences_by_station(station_id) do
    list_all_preferences()
    |> Enum.filter(fn preference -> preference.station_id == station_id end)
  end

  def get_preferences_by_connector_type(connector_type) do
    list_all_preferences()
    |> Enum.filter(fn preference -> preference.connector_type == connector_type end)
  end

  def get_preferences_by_location(location_filter) do
    list_all_preferences()
    |> Enum.filter(fn preference ->
      case preference.location do
        nil -> false
        location -> String.contains?(String.downcase(location), String.downcase(location_filter))
      end
    end)
  end

  def get_active_preferences() do
    list_all_preferences()
    |> Enum.filter(fn preference -> preference.status == :active end)
  end

  def get_preferences_with_alerts() do
    list_all_preferences()
    |> Enum.filter(fn preference -> preference.alert == true end)
  end

  def count_preferences() do
    case ElixirFastCharge.HordeRegistry.list_all() do
      processes when is_list(processes) ->
        preference_count = processes
        |> Enum.count(fn {{type, _id}, _pid, _value} -> type == :preference end)

        %{
          total_preferences: preference_count,
          node: Node.self(),
          cluster_nodes: [Node.self() | Node.list()]
        }

      _ ->
        %{
          total_preferences: 0,
          node: Node.self(),
          cluster_nodes: [Node.self() | Node.list()]
        }
    end
  end

  def get_preference_info(preference_id) do
    ElixirFastCharge.DistributedPreference.get_preference_info(preference_id)
  end

  def list_preferences_by_node() do
    case ElixirFastCharge.HordeRegistry.list_all() do
      processes when is_list(processes) ->
        preference_processes = processes
        |> Enum.filter(fn {{type, _id}, _pid, _value} -> type == :preference end)

        preference_processes
        |> Enum.group_by(fn {{:preference, _preference_id}, pid, _value} -> node(pid) end)
        |> Enum.map(fn {node, preference_list} ->
          {Atom.to_string(node), length(preference_list)}
        end)
        |> Map.new()

      _ -> %{}
    end
  end

  def get_cluster_stats() do
    all_nodes = [Node.self() | Node.list()]
    preference_count = count_preferences()
    preference_distribution = list_preferences_by_node()

    # Estadísticas adicionales
    all_preferences = list_all_preferences()
    active_preferences = Enum.count(all_preferences, fn p -> p.status == :active end)
    alert_preferences = Enum.count(all_preferences, fn p -> p.alert == true end)

    # Distribución por usuario
    user_distribution = all_preferences
    |> Enum.group_by(fn preference -> preference.username end)
    |> Enum.map(fn {username, prefs} -> {username, length(prefs)} end)
    |> Map.new()

    %{
      node: Atom.to_string(Node.self()),
      cluster_nodes: Enum.map(all_nodes, &Atom.to_string/1),
      total_preferences: preference_count.total_preferences,
      active_preferences: active_preferences,
      preferences_with_alerts: alert_preferences,
      preference_distribution: preference_distribution,
      user_distribution: user_distribution,
      distributed: true
    }
  end

  # FUNCIONES DE UTILIDAD

  def preference_exists?(preference_id) do
    case get_preference(preference_id) do
      {:ok, _preference} -> true
      {:error, :not_found} -> false
    end
  end

  def delete_preference(preference_id) do
    case Horde.Registry.lookup(ElixirFastCharge.HordeRegistry, {:preference, preference_id}) do
      [{pid, _}] ->
        case ElixirFastCharge.HordeSupervisor.terminate_child(pid) do
          :ok ->
            Logger.info("Preferencia #{preference_id} eliminada del cluster")
            {:ok, :deleted}

          {:error, reason} ->
            Logger.error("Error eliminando preferencia #{preference_id}: #{inspect(reason)}")
            {:error, reason}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def delete_user_preferences(username) do
    user_preferences = get_preferences_by_user(username)

    results = user_preferences
    |> Enum.map(fn preference ->
      case delete_preference(preference.preference_id) do
        {:ok, :deleted} -> {:ok, preference.preference_id}
        {:error, reason} -> {:error, preference.preference_id, reason}
      end
    end)

    successful = Enum.count(results, fn {status, _} -> status == :ok end)
    failed = Enum.count(results, fn result -> elem(result, 0) == :error end)

    Logger.info("Eliminación de preferencias para #{username}: #{successful} exitosas, #{failed} fallidas")

    %{
      username: username,
      total: length(user_preferences),
      successful: successful,
      failed: failed,
      results: results
    }
  end

  # FUNCIONES DE MATCHING Y BÚSQUEDA

  def find_matching_preferences_for_shift(shift) do
    all_preferences = get_active_preferences()

    all_preferences
    |> Enum.map(fn preference ->
      score = calculate_preference_score(shift, preference)
      matches = get_preference_matches(shift, preference)

      %{
        preference: preference,
        score: score,
        matches: matches,
        match_percentage: (score / 5) * 100  # Máximo 5 criterios
      }
    end)
    |> Enum.filter(fn result -> result.score > 0 end)
    |> Enum.sort_by(fn result -> result.score end, :desc)
  end

  def find_users_to_notify(shift) do
    matching_preferences = find_matching_preferences_for_shift(shift)

    matching_preferences
    |> Enum.filter(fn result -> result.preference.alert == true end)
    |> Enum.map(fn result ->
      %{
        username: result.preference.username,
        preference_id: result.preference.preference_id,
        score: result.score,
        match_percentage: result.match_percentage
      }
    end)
  end

  # FUNCIONES DE DIAGNÓSTICO

  def cluster_health() do
    all_nodes = [Node.self() | Node.list()]
    preference_stats = get_cluster_stats()

    %{
      cluster_status: if(length(all_nodes) > 1, do: "clustered", else: "standalone"),
      total_nodes: length(all_nodes),
      connected_nodes: Enum.map(Node.list(), &Atom.to_string/1),
      current_node: Atom.to_string(Node.self()),
      preference_stats: preference_stats,
      timestamp: DateTime.utc_now()
    }
  end

  def health_check_all_preferences() do
    all_preferences = list_all_preferences()

    health_results = all_preferences
    |> Enum.map(fn preference ->
      case get_preference_info(preference.preference_id) do
        {:ok, info} -> %{preference_id: preference.preference_id, status: :healthy, info: info}
        {:error, reason} -> %{preference_id: preference.preference_id, status: :unhealthy, reason: reason}
      end
    end)

    healthy_count = Enum.count(health_results, fn result -> result.status == :healthy end)
    unhealthy_count = length(health_results) - healthy_count

    %{
      total_preferences: length(health_results),
      healthy_preferences: healthy_count,
      unhealthy_preferences: unhealthy_count,
      health_percentage: if(length(health_results) > 0, do: (healthy_count / length(health_results)) * 100, else: 0),
      results: health_results,
      timestamp: DateTime.utc_now()
    }
  end

  # FUNCIONES PRIVADAS

  defp validate_user_exists(username) do
    case ElixirFastCharge.DistributedUserManager.get_user(username) do
      {:ok, _user} -> true
      {:error, :not_found} -> false
    end
  end

  defp calculate_preference_score(shift, preference) do
    matches = get_preference_matches(shift, preference)

    matches
    |> Map.values()
    |> Enum.count(& &1)
  end

  defp get_preference_matches(shift, preference) do
    %{
      station_id: preference.station_id == shift.station_id,
      connector_type: preference.connector_type == shift.connector_type,
      power: preference.power_kw == shift.power_kw,
      location: check_location_match(shift, preference),
      date: check_date_preference(shift, preference)
    }
  end

  defp check_location_match(shift, preference) do
    case preference.location do
      nil -> false
      location ->
        shift_location = get_in(shift, [:location, :address]) || ""
        String.contains?(String.downcase(shift_location), String.downcase(location))
    end
  end

  defp check_date_preference(shift, preference) do
    case preference.fecha do
      nil -> false
      fecha_str ->
        case Date.from_iso8601(fecha_str) do
          {:ok, fecha_preferencia} ->
            shift_date = DateTime.to_date(shift.start_time)
            Date.compare(fecha_preferencia, shift_date) == :eq
          _ -> false
        end
    end
  end
end
