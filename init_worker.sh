#!/bin/bash
#
# init_worker.sh - Inicializa un nodo worker (server que alojara VMs/
# contenedores conectados a las VLANs, sin funcion de routing/NAT).
#
# Uso:
#   ./init_worker.sh <iface1> [iface2] ...
#
# Parametros de entrada:
#   $@  Lista de interfaces fisicas a conectar al bridge OVS local 'br-int'
#
# Acciones:
#   1. Si no existiera, crea el bridge OVS local 'br-int'.
#   2. Conecta las interfaces provistas como parametros al bridge 'br-int'.

set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Uso: $0 <iface1> [iface2] ..." >&2
    exit 1
fi

BRIDGE="br-int"

# 1. Crear el bridge OVS si no existe
if ! sudo ovs-vsctl br-exists "$BRIDGE"; then
    echo "[init_worker] Creando bridge OVS '$BRIDGE'..."
    sudo ovs-vsctl add-br "$BRIDGE"
else
    echo "[init_worker] El bridge '$BRIDGE' ya existe, se omite creacion."
fi

# 2. Conectar las interfaces provistas al bridge
for iface in "$@"; do
    if ! ip link show "$iface" &>/dev/null; then
        echo "[init_worker] ADVERTENCIA: la interfaz '$iface' no existe en este host, se omite." >&2
        continue
    fi
    if sudo ovs-vsctl list-ports "$BRIDGE" | grep -qx "$iface"; then
        echo "[init_worker] La interfaz '$iface' ya esta conectada a '$BRIDGE', se omite."
    else
        echo "[init_worker] Conectando '$iface' a '$BRIDGE'..."
        sudo ovs-vsctl add-port "$BRIDGE" "$iface"
    fi
done

echo "[init_worker] Nodo worker inicializado correctamente."
