# 🚀 ElixirFastCharge con Load Balancer

## ⚡ Inicio Rápido

```bash
# 1. Levantar toda la infraestructura
docker-compose up -d

# 2. Esperar unos segundos a que inicien todos los servicios
sleep 30

# 3. Probar que funciona
chmod +x test-load-balancer.sh
./test-load-balancer.sh
```

## 🏗️ Arquitectura

```
Frontend → :8080 (Nginx) → Round Robin
                           ├── Node1 :4002
                           ├── Node2 :4003
                           └── Node3 :4004
```

## 🎯 URLs

- **Frontend conecta aquí:** `http://localhost:8080`
- **Health del Load Balancer:** `http://localhost:8080/lb-health`
- **API completa:** `http://localhost:8080/users`, `/cluster`, `/health`

## 📝 Ejemplo Frontend

```javascript
// ¡Solo un endpoint!
const API_URL = 'http://localhost:8080';

// Crear usuario
fetch(`${API_URL}/users/sign-up`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    username: 'nuevo_usuario',
    password: 'mi_password',
    mail: 'usuario@ejemplo.com'
  })
});

// Obtener usuarios
fetch(`${API_URL}/users`)
  .then(r => r.json())
  .then(data => console.log(data.users));
```

## 🔧 Comandos Útiles

```bash
# Ver logs de todos los servicios
docker-compose logs -f

# Ver solo logs del load balancer
docker-compose logs -f nginx

# Ver logs de un nodo específico
docker-compose logs -f elixir-node1

# Reiniciar todo
docker-compose restart

# Parar todo
docker-compose down
```

## ✅ Beneficios

- **Un solo endpoint** para el frontend
- **Distribución automática** de carga
- **Tolerancia a fallos** (si un nodo falla, siguen funcionando los otros)
- **Fácil escalado** (agregar más nodos en docker-compose.yml)

## 🎉 ¡Ya funciona!

Tu frontend solo necesita conectarse a `http://localhost:8080` y el load balancer se encarga del resto. 