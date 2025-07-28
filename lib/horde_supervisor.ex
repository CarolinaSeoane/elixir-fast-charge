defmodule ElixirFastCharge.HordeSupervisor do
  @moduledoc """
  Supervisor dinámico distribuido usando Horde.
  Maneja el ciclo de vida de procesos distribuidos en el cluster.
  """
  use Horde.DynamicSupervisor

  def start_link(_) do
    Horde.DynamicSupervisor.start_link(__MODULE__, [strategy: :one_for_one], name: __MODULE__)
  end

  def init(init_arg) do
    [members: members()]
    |> Keyword.merge(init_arg)
    |> Horde.DynamicSupervisor.init()
  end

  # Iniciar un proceso hijo distribuido
  def start_child(child_spec) do
    Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  # Terminar un proceso hijo
  def terminate_child(child_pid) when is_pid(child_pid) do
    Horde.DynamicSupervisor.terminate_child(__MODULE__, child_pid)
  end

  def terminate_child(child_id) do
    case ElixirFastCharge.HordeRegistry.lookup(child_id) do
      {:ok, pid} -> terminate_child(pid)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  # Listar todos los procesos hijos
  def which_children do
    Horde.DynamicSupervisor.which_children(__MODULE__)
  end

  # Contar procesos hijos
  def count_children do
    Horde.DynamicSupervisor.count_children(__MODULE__)
  end

  # Obtener información del cluster
  def get_cluster_info do
    children_info = count_children()
    members_info = members()

    %{
      node: Node.self(),
      cluster_members: members_info,
      children_count: children_info,
      total_nodes: length(members_info),
      connected_nodes: Node.list()
    }
  end

  # Función helper para iniciar shifts distribuidos
  def start_shift(shift_data) do
    child_spec = {ElixirFastCharge.DistributedShift, shift_data}
    start_child(child_spec)
  end

  # Función helper para iniciar pre-reservas distribuidas
  def start_pre_reservation(pre_reservation_data) do
    child_spec = {ElixirFastCharge.DistributedPreReservation, pre_reservation_data}
    start_child(child_spec)
  end

  # Función helper para iniciar usuarios distribuidos
  def start_user(user_data) do
    child_spec = {ElixirFastCharge.DistributedUser, user_data}
    start_child(child_spec)
  end

  # Obtener miembros del cluster para este supervisor
  defp members() do
    [Node.self() | Node.list()]
    |> Enum.map(fn node -> {__MODULE__, node} end)
  end
end
