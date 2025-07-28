#!/bin/bash

# ========================================
# SCRIPT DE ESCALADO HACIA ARRIBA
# ElixirFastCharge - Automatic Scaling
# ========================================

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/elixir-fast-charge-scaling.log"

# Función de logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SCALE_UP: $1" | tee -a "$LOG_FILE"
}

log "🚀 Iniciando escalado hacia arriba..."

# ========================================
# CONFIGURACIÓN
# ========================================

# Valores por defecto
CURRENT_REPLICAS=${CURRENT_REPLICAS:-1}
TARGET_REPLICAS=${TARGET_REPLICAS:-$((CURRENT_REPLICAS + 2))}
MAX_REPLICAS=${MAX_REPLICAS:-10}

# Asegurar que no excedamos el límite
if [ "$TARGET_REPLICAS" -gt "$MAX_REPLICAS" ]; then
    TARGET_REPLICAS=$MAX_REPLICAS
    log "⚠️ Limitando escalado a máximo de $MAX_REPLICAS réplicas"
fi

log "📊 Escalando de $CURRENT_REPLICAS a $TARGET_REPLICAS réplicas"

# ========================================
# KUBERNETES SCALING
# ========================================

scale_kubernetes() {
    if command -v kubectl &> /dev/null; then
        log "🔧 Escalando via Kubernetes..."
        
        DEPLOYMENT_NAME=${K8S_DEPLOYMENT_NAME:-"elixir-fast-charge"}
        NAMESPACE=${K8S_NAMESPACE:-"default"}
        
        if kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" &> /dev/null; then
            kubectl scale deployment "$DEPLOYMENT_NAME" --replicas="$TARGET_REPLICAS" -n "$NAMESPACE"
            
            if [ $? -eq 0 ]; then
                log "✅ Kubernetes scaling exitoso: $TARGET_REPLICAS réplicas"
                
                # Esperar a que los pods estén listos
                log "⏳ Esperando que los pods estén listos..."
                kubectl wait --for=condition=available --timeout=300s deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE"
                
                if [ $? -eq 0 ]; then
                    log "✅ Todos los pods están listos"
                else
                    log "⚠️ Timeout esperando que los pods estén listos"
                fi
                
                return 0
            else
                log "❌ Error en scaling de Kubernetes"
                return 1
            fi
        else
            log "⚠️ Deployment $DEPLOYMENT_NAME no encontrado en namespace $NAMESPACE"
            return 1
        fi
    else
        log "⚠️ kubectl no está disponible"
        return 1
    fi
}

# ========================================
# DOCKER SWARM SCALING
# ========================================

scale_docker_swarm() {
    if command -v docker &> /dev/null; then
        log "🐳 Escalando via Docker Swarm..."
        
        SERVICE_NAME=${DOCKER_SERVICE_NAME:-"elixir-fast-charge"}
        
        if docker service ls --filter name="$SERVICE_NAME" --format "{{.Name}}" | grep -q "$SERVICE_NAME"; then
            docker service scale "$SERVICE_NAME=$TARGET_REPLICAS"
            
            if [ $? -eq 0 ]; then
                log "✅ Docker Swarm scaling exitoso: $TARGET_REPLICAS réplicas"
                return 0
            else
                log "❌ Error en scaling de Docker Swarm"
                return 1
            fi
        else
            log "⚠️ Service $SERVICE_NAME no encontrado"
            return 1
        fi
    else
        log "⚠️ docker no está disponible"
        return 1
    fi
}

# ========================================
# AWS AUTO SCALING
# ========================================

scale_aws() {
    if command -v aws &> /dev/null; then
        log "☁️ Escalando via AWS Auto Scaling..."
        
        ASG_NAME=${AWS_ASG_NAME:-"elixir-fast-charge-asg"}
        REGION=${AWS_REGION:-"us-east-1"}
        
        # Actualizar capacidad deseada del Auto Scaling Group
        aws autoscaling set-desired-capacity \
            --auto-scaling-group-name "$ASG_NAME" \
            --desired-capacity "$TARGET_REPLICAS" \
            --region "$REGION"
            
        if [ $? -eq 0 ]; then
            log "✅ AWS Auto Scaling actualizado: $TARGET_REPLICAS instancias"
            
            # Esperar a que las instancias estén en servicio
            log "⏳ Esperando que las instancias estén en servicio..."
            aws autoscaling wait instance-in-service \
                --auto-scaling-group-name "$ASG_NAME" \
                --region "$REGION"
                
            if [ $? -eq 0 ]; then
                log "✅ Todas las instancias están en servicio"
            else
                log "⚠️ Timeout esperando instancias en servicio"
            fi
            
            return 0
        else
            log "❌ Error en scaling de AWS"
            return 1
        fi
    else
        log "⚠️ AWS CLI no está disponible"
        return 1
    fi
}

# ========================================
# GOOGLE CLOUD SCALING
# ========================================

scale_gcp() {
    if command -v gcloud &> /dev/null; then
        log "☁️ Escalando via Google Cloud..."
        
        INSTANCE_GROUP=${GCP_INSTANCE_GROUP:-"elixir-fast-charge-ig"}
        ZONE=${GCP_ZONE:-"us-central1-a"}
        
        gcloud compute instance-groups managed resize "$INSTANCE_GROUP" \
            --size="$TARGET_REPLICAS" \
            --zone="$ZONE"
            
        if [ $? -eq 0 ]; then
            log "✅ GCP Instance Group escalado: $TARGET_REPLICAS instancias"
            return 0
        else
            log "❌ Error en scaling de GCP"
            return 1
        fi
    else
        log "⚠️ gcloud CLI no está disponible"
        return 1
    fi
}

# ========================================
# CUSTOM SCALING (Ejemplo)
# ========================================

scale_custom() {
    log "🔧 Ejecutando scaling custom..."
    
    # Ejemplo: Iniciar nuevas instancias EC2
    if [ -n "$CUSTOM_SCALE_UP_COMMAND" ]; then
        log "🔧 Ejecutando comando custom: $CUSTOM_SCALE_UP_COMMAND"
        eval "$CUSTOM_SCALE_UP_COMMAND"
        
        if [ $? -eq 0 ]; then
            log "✅ Comando custom ejecutado exitosamente"
            return 0
        else
            log "❌ Error ejecutando comando custom"
            return 1
        fi
    fi
    
    # Aquí puedes agregar tu lógica específica
    # Por ejemplo:
    # - Iniciar instancias en tu provider de cloud
    # - Notificar a un sistema de orquestación
    # - Actualizar un load balancer
    
    log "ℹ️ Scaling custom no configurado"
    return 1
}

# ========================================
# EJECUCIÓN PRINCIPAL
# ========================================

main() {
    local success=false
    
    # Intentar escalado en orden de preferencia
    if [ "${KUBERNETES_ENABLED:-false}" = "true" ]; then
        if scale_kubernetes; then
            success=true
        fi
    fi
    
    if [ "$success" = false ] && [ "${DOCKER_SWARM_ENABLED:-false}" = "true" ]; then
        if scale_docker_swarm; then
            success=true
        fi
    fi
    
    if [ "$success" = false ] && [ "${AWS_SCALING_ENABLED:-false}" = "true" ]; then
        if scale_aws; then
            success=true
        fi
    fi
    
    if [ "$success" = false ] && [ "${GCP_SCALING_ENABLED:-false}" = "true" ]; then
        if scale_gcp; then
            success=true
        fi
    fi
    
    if [ "$success" = false ]; then
        if scale_custom; then
            success=true
        fi
    fi
    
    if [ "$success" = true ]; then
        log "🎉 Escalado completado exitosamente"
        
        # Notificaciones
        send_notification "✅ SCALE UP SUCCESS" "Escalado a $TARGET_REPLICAS réplicas completado"
        
        exit 0
    else
        log "❌ Falló el escalado en todas las estrategias"
        
        # Notificaciones de error
        send_notification "❌ SCALE UP FAILED" "Error escalando a $TARGET_REPLICAS réplicas"
        
        exit 1
    fi
}

# ========================================
# NOTIFICACIONES
# ========================================

send_notification() {
    local title="$1"
    local message="$2"
    
    # Slack
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$title: $message\"}" \
            "$SLACK_WEBHOOK_URL" || true
    fi
    
    # Email (ejemplo usando sendmail)
    if [ -n "$ALERT_EMAIL" ] && command -v sendmail &> /dev/null; then
        echo "Subject: ElixirFastCharge - $title
        
$message

Timestamp: $(date)
Node: $(hostname)
" | sendmail "$ALERT_EMAIL" || true
    fi
    
    # Discord
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"content\":\"$title: $message\"}" \
            "$DISCORD_WEBHOOK_URL" || true
    fi
}

# ========================================
# VERIFICACIONES PREVIAS
# ========================================

# Verificar que el script se ejecute como root o con permisos adecuados
if [ "$EUID" -ne 0 ] && [ -z "$ALLOW_NON_ROOT" ]; then
    log "⚠️ Warning: Script no ejecutándose como root. Algunas operaciones pueden fallar."
fi

# Crear directorio de logs si no existe
mkdir -p "$(dirname "$LOG_FILE")" || true

# Ejecutar función principal
main "$@" 