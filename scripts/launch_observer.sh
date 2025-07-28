#!/bin/bash

echo "LANZANDO OBSERVER PARA CLUSTER"
echo "=================================="

HOSTNAME=$(hostname)

echo "Hostname: $HOSTNAME"
echo ""

echo "Iniciando Observer node..."
echo ""
echo "Ejecutando los siguientes comandos automáticamente:"
echo "   Node.connect(:\"node1@$HOSTNAME\")"
echo "   Node.connect(:\"node2@$HOSTNAME\")"
echo "   Node.connect(:\"node3@$HOSTNAME\")"
echo "   :observer.start()"
echo ""

# Crear script temporal para IEx
cat > /tmp/observer_startup.exs << EOF
# Conectar a nodos del cluster
IO.puts("Conectando a nodos del cluster...")

node1 = :"node1@$HOSTNAME"
node2 = :"node2@$HOSTNAME"  
node3 = :"node3@$HOSTNAME"

# Intentar conectar a cada nodo
connect_result1 = Node.connect(node1)
connect_result2 = Node.connect(node2)
connect_result3 = Node.connect(node3)

IO.puts("Resultados de conexión:")
IO.puts("  node1: #{connect_result1}")
IO.puts("  node2: #{connect_result2}")
IO.puts("  node3: #{connect_result3}")

connected_nodes = Node.list()
IO.puts(" Nodos conectados: #{inspect(connected_nodes)}")

if Enum.empty?(connected_nodes) do
  IO.puts("  No se pudo conectar a ningún nodo.")
  IO.puts("   Asegúrate de que el cluster esté ejecutándose.")
  IO.puts("   Ejecuta: ./scripts/start_cluster_with_observer.sh")
else
  IO.puts("Cluster conectado exitosamente!")
  IO.puts("")
  IO.puts("Iniciando Observer GUI...")
  :observer.start()
end
EOF

echo "Iniciando IEx con Observer..."
iex --sname observer --cookie elixir_fast_charge_cookie /tmp/observer_startup.exs 