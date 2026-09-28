#!/bin/bash
#
# init_master.sh - Inicializa el nodo master (server con rol de router/gateway
# entre VLANs y salida a Internet) dentro del slice.
#
# Uso:
#   ./init_master.sh <iface1> [iface2] [iface3] ...
#
# Parametros de entrada:
#   $@  Lista de interfaces fisicas a conectar al bridge OVS local 'br-int'
#       (por ejemplo: ens4)
#
# Acciones:
#   1. Si no existiera, crea el bridge OVS local 'br-int'.
#   2. Conecta las interfaces provistas como parametros al bridge 'br-int'.
#   3. Activa el reenvio de paquetes IPv4 (ip_forward).
#   4. Cambia la politica por defecto de la cadena FORWARD de la tabla
#      filter, de ACCEPT a DROP (el trafico entre VLANs o hacia Internet
#      debe ser autorizado explicitamente por internet_to_network.sh /
#      routing_networks.sh).
#   5. Agrega una regla generica que acepta el trafico de retorno de
#      conexiones ya establecidas (ESTABLISHED,RELATED). Sin esta regla,
#      ninguna de las reglas que agreguen internet_to_network.sh o
#      routing_networks.sh permitiria trafico bidireccional real, ya que
#      solo autorizan el sentido de ida.

set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Uso: $0 <iface1> [iface2] ..." >&2
    exit 1
fi

BRIDGE="br-int"

# 1. Crear el bridge OVS si no existe
if ! sudo ovs-vsctl br-exists "$BRIDGE"; then
    echo "[init_master] Creando bridge OVS '$BRIDGE'..."
    sudo ovs-vsctl add-br "$BRIDGE"
else
    echo "[init_master] El bridge '$BRIDGE' ya existe, se omite creacion."
fi

# 2. Conectar las interfaces provistas al bridge
for iface in "$@"; do
    if ! ip link show "$iface" &>/dev/null; then
        echo "[init_master] ADVERTENCIA: la interfaz '$iface' no existe en este host, se omite." >&2
        continue
    fi
    if sudo ovs-vsctl list-ports "$BRIDGE" | grep -qx "$iface"; then
        echo "[init_master] La interfaz '$iface' ya esta conectada a '$BRIDGE', se omite."
    else
        echo "[init_master] Conectando '$iface' a '$BRIDGE'..."
        sudo ovs-vsctl add-port "$BRIDGE" "$iface"
    fi
done

# 3. Activar IPv4 forwarding
echo "[init_master] Activando net.ipv4.ip_forward..."
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

# 4. Politica por defecto de FORWARD: ACCEPT -> DROP
echo "[init_master] Configurando politica por defecto de FORWARD en DROP..."
sudo iptables -P FORWARD DROP

# 5. Permitir trafico de retorno de conexiones ya establecidas
if sudo iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
    echo "[init_master] La regla de retorno ESTABLISHED,RELATED ya existe."
else
    echo "[init_master] Agregando regla de retorno ESTABLISHED,RELATED en FORWARD..."
    sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
fi

echo "[init_master] Nodo master inicializado correctamente."
