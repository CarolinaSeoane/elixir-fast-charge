#!/bin/bash

echo "POBLANDO DATOS INICIALES EN SISTEMA DISTRIBUIDO"
echo "=================================================="

BASE_URL="http://localhost:4001"

echo ""
echo "Estado inicial:"
curl -s $BASE_URL/shifts/all | grep -o '"count":[0-9]*' || echo "Sistema no disponible"

echo ""
echo ""
echo "Creando turnos de ejemplo..."

# Crear 5 turnos de diferentes tipos
for i in {1..5}; do
    echo "Creando turno $i..."
    curl -s -X POST $BASE_URL/cluster/test/create-shift > /dev/null
    sleep 0.5
done

echo ""
echo "Creando estaciones de ejemplo..."

# Crear 2 estaciones de ejemplo  
for i in {1..2}; do
    echo "Creando estación $i..."
    curl -s -X POST $BASE_URL/cluster/test/create-station > /dev/null
    sleep 0.5
done

echo ""
echo "Creando usuarios de ejemplo..."

# Crear usuarios
curl -s -X POST $BASE_URL/users/sign-up \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "admin123"}' > /dev/null

curl -s -X POST $BASE_URL/users/sign-up \
  -H "Content-Type: application/json" \
  -d '{"username": "demo_user", "password": "demo123"}' > /dev/null

curl -s -X POST $BASE_URL/users/sign-up \
  -H "Content-Type: application/json" \
  -d '{"username": "test_user", "password": "test123"}' > /dev/null

echo ""
echo "Creando preferencias de ejemplo..."

# Crear 2 preferencias
for i in {1..2}; do
    echo "Creando preferencia $i..."
    curl -s -X POST $BASE_URL/cluster/test/create-preference > /dev/null
    sleep 0.5
done

echo ""
echo ""
echo "DATOS INICIALES CREADOS EXITOSAMENTE!"
echo "========================================"

echo ""
echo "Estado final:"
echo "Turnos:"
curl -s $BASE_URL/shifts/all | grep -o '"count":[0-9]*'

echo "Usuarios:"
curl -s $BASE_URL/users/ | grep -o '"count":[0-9]*'

echo ""
echo "Sistema listo para usar con datos de ejemplo!"

echo ""
echo "Endpoints disponibles:"
echo "  - Turnos: $BASE_URL/shifts/all"
echo "  - Turnos activos: $BASE_URL/shifts/active"  
echo "  - Usuarios: $BASE_URL/users/"
echo "  - Cluster info: $BASE_URL/cluster/info"
echo "  - Monitoreo: $BASE_URL/monitoring/" 