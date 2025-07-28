#!/bin/bash

echo "INICIANDO CLUSTER..."

# Matar procesos previos
pkill -9 beam.smp 2>/dev/null || true
sleep 2

# Compilar
mix compile > /dev/null 2>&1

# Iniciar nodos en background
echo "Iniciando node1..."
PORT=4001 iex --sname node1 --cookie elixir_fast_charge_cookie -S mix run --no-halt > /dev/null 2>&1 &
sleep 3

echo "Iniciando node2..."
PORT=4002 iex --sname node2 --cookie elixir_fast_charge_cookie -S mix run --no-halt > /dev/null 2>&1 &
sleep 3

echo "Iniciando node3..."
PORT=4003 iex --sname node3 --cookie elixir_fast_charge_cookie -S mix run --no-halt > /dev/null 2>&1 &
sleep 5

# Iniciar Observer
echo "Iniciando Observer..."
./scripts/start_observer_simple.sh > /dev/null 2>&1 &
sleep 2

echo "CLUSTER INICIADO!"
echo "Endpoints: http://localhost:4001, http://localhost:4002, http://localhost:4003"
echo ""
echo "Para detener: pkill -9 beam.smp" 