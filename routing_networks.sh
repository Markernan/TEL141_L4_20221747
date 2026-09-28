#!/bin/bash
#
# routing_networks.sh - Habilita el enrutamiento de trafico entre dos VLANs
# ya creadas con create_network_vlan.sh.
#
# Uso:
#   ./routing_networks.sh <vlan_id_1> <vlan_id_2>
#
# Parametros de entrada:
#   $1  VLAN ID 1
#   $2  VLAN ID 2
#
# Acciones:
#   1. Agrega en la cadena FORWARD (tabla filter) las dos reglas
#      necesarias para permitir el trafico en ambos sentidos entre los
#      gateways de las dos VLANs indicadas.

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Uso: $0 <vlan_id_1> <vlan_id_2>" >&2
    exit 1
fi

VLAN1=$1
VLAN2=$2
GW1="gw_vlan${VLAN1}"
GW2="gw_vlan${VLAN2}"

add_rule() {
    local in_iface=$1
    local out_iface=$2
    if sudo iptables -C FORWARD -i "$in_iface" -o "$out_iface" -j ACCEPT 2>/dev/null; then
        echo "[routing_networks] La regla FORWARD $in_iface -> $out_iface ya existe."
    else
        echo "[routing_networks] Autorizando FORWARD $in_iface -> $out_iface..."
        sudo iptables -A FORWARD -i "$in_iface" -o "$out_iface" -j ACCEPT
    fi
}

add_rule "$GW1" "$GW2"
add_rule "$GW2" "$GW1"

echo "[routing_networks] Enrutamiento habilitado entre VLAN $VLAN1 y VLAN $VLAN2."
