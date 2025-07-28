defmodule ElixirFastCharge.HordeRegistry do
  @moduledoc """
  Registro distribuido usando Horde.
  Permite que procesos se registren con nombres únicos a través del cluster.
  """
  use Horde.Registry

  def start_link(_) do
    Horde.Registry.start_link(__MODULE__, [keys: :unique], name: __MODULE__)
  end

  def init(init_arg) do
    # Obtener lista de otros nodos en el cluster
    [members: members()]
    |> Keyword.merge(init_arg)
    |> Horde.Registry.init()
  end

  # Función helper para registrar un proceso
  def register(name, pid \\ self(), value \\ nil) do
    Horde.Registry.register(__MODULE__, name, value)
  end

  # Función helper para buscar un proceso
  def lookup(name) do
    case Horde.Registry.lookup(__MODULE__, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  # Función helper para obtener todos los procesos registrados
  def list_all do
    Horde.Registry.select(__MODULE__, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
  end

  # Obtener miembros del cluster para este registro
  defp members() do
    [Node.self() | Node.list()]
    |> Enum.map(fn node -> {__MODULE__, node} end)
  end

  # Callback para manejar cambios en la membresía del cluster
  def handle_continue({:continue_startup, init_arg}, state) do
    # Cuando se agregan nuevos nodos, Horde automáticamente
    # sincroniza el registro
    {:noreply, state}
  end
end
