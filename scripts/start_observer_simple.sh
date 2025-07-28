#!/bin/bash

echo "INICIANDO OBSERVER CONECTADO A NODE1"
echo "===================================="

HOSTNAME=$(hostname)
echo "Hostname: $HOSTNAME"

echo ""
echo "Conectando Observer a node1@$HOSTNAME..."

# Crear script temporal para conectar Observer
cat > /tmp/observer_connect.exs << EOF
# Conectar a node1
node1 = :"node1@$HOSTNAME"
result = Node.connect(node1)
IO.puts("Conexión a node1: #{result}")

# Mostrar nodos conectados
connected = Node.list()
IO.puts("Nodos conectados: #{inspect(connected)}")

if result do
  IO.puts("Iniciando Observer GUI...")
  :observer.start()
  IO.puts("Observer iniciado. Mantener esta ventana abierta.")
else
  IO.puts("Error: No se pudo conectar a node1")
  IO.puts("Asegúrate de que node1 esté corriendo en puerto 4001")
end
EOF

echo "Iniciando IEx Observer..."
iex --sname observer_gui --cookie elixir_fast_charge_cookie /tmp/observer_connect.exs 