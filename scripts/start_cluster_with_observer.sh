#!/bin/bash

echo "🚀 INICIANDO CLUSTER CON OBSERVER"
echo "================================="

# Obtener hostname
HOSTNAME=$(hostname)
echo "📡 Hostname detectado: $HOSTNAME"

echo ""
echo "🔧 Limpiando procesos previos..."
pkill -9 beam.smp 2>/dev/null || true
sleep 2

echo ""
echo "🎯 Iniciando nodos del cluster..."

# Terminal backgrounds para cada nodo
echo "  📍 Iniciando node1..."
PORT=4001 iex --sname node1 --cookie elixir_fast_charge_cookie -S mix run --no-halt &
NODE1_PID=$!

sleep 3

echo "  📍 Iniciando node2..."
PORT=4002 iex --sname node2 --cookie elixir_fast_charge_cookie -S mix run --no-halt &
NODE2_PID=$!

sleep 3

echo "  📍 Iniciando node3..."
PORT=4003 iex --sname node3 --cookie elixir_fast_charge_cookie -S mix run --no-halt &
NODE3_PID=$!

sleep 5

echo ""
echo "✅ CLUSTER INICIADO EXITOSAMENTE!"
echo "================================="
echo ""
echo "📊 Nodos activos:"
echo "  🔗 node1@$HOSTNAME:4001"
echo "  🔗 node2@$HOSTNAME:4002" 
echo "  🔗 node3@$HOSTNAME:4003"
echo ""
echo "🔍 PARA USAR OBSERVER:"
echo "======================"
echo ""
echo "En una nueva terminal, ejecuta:"
echo ""
echo "  iex --sname observer --cookie elixir_fast_charge_cookie"
echo ""
echo "Luego dentro de IEx:"
echo ""
echo "  # Conectar a los nodos"
echo "  Node.connect(:\"node1@$HOSTNAME\")"
echo "  Node.connect(:\"node2@$HOSTNAME\")"
echo "  Node.connect(:\"node3@$HOSTNAME\")"
echo ""
echo "  # Verificar conexiones"
echo "  Node.list()"
echo ""
echo "  # Iniciar Observer GUI"
echo "  :observer.start()"
echo ""
echo "📋 ENDPOINTS DISPONIBLES:"
echo "  http://localhost:4001/cluster/info"
echo "  http://localhost:4002/cluster/info"
echo "  http://localhost:4003/cluster/info"
echo ""
echo "⚠️  PARA DETENER EL CLUSTER:"
echo "  kill $NODE1_PID $NODE2_PID $NODE3_PID"
echo ""
echo "🎉 Observer te permitirá ver:"
echo "  - Procesos en tiempo real"
echo "  - Uso de memoria por nodo"
echo "  - Carga de CPU"
echo "  - Mensajes entre procesos"
echo "  - Topología del cluster"
echo ""
echo "✨ ¡Cluster listo para observar!" 