# Usar imagen oficial de Elixir
FROM elixir:1.18-alpine

# Instalar dependencias del sistema
RUN apk add --no-cache build-base git

# Crear directorio de trabajo
WORKDIR /app

# Copiar archivos de dependencias
COPY mix.exs mix.lock ./

# Instalar dependencias
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get

# Copiar código fuente
COPY . .

# Compilar aplicación
RUN mix compile

# Exponer puerto por defecto
EXPOSE 4002

# Script de inicio
CMD ["sh", "-c", "iex --name $NODE_NAME --cookie elixir_fast_charge_cluster -S mix"] 