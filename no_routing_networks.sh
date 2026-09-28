#!/bin/bash
#
# no_routing_networks.sh - Deshabilita el enrutamiento de trafico entre dos
# VLANs, eliminando las reglas creadas por routing_networks.sh.
#
# Uso:
#   ./no_routing_networks.sh <vlan_id_1> <vlan_id_2>
#
# Parametros de entrada:
#   $1  VLAN ID 1
#   $2  VLAN ID 2
#
# Acciones:
#   1. Elimina de la cadena FORWARD las dos reglas que autorizaban el
#      trafico en ambos sentidos entre los gateways de las dos VLANs
#      indicadas.

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Uso: $0 <vlan_id_1> <vlan_id_2>" >&2
    exit 1
fi

VLAN1=$1
VLAN2=$2
GW1="gw_vlan${VLAN1}"
GW2="gw_vlan${VLAN2}"

del_rule() {
    local in_iface=$1
    local out_iface=$2
    if sudo iptables -C FORWARD -i "$in_iface" -o "$out_iface" -j ACCEPT 2>/dev/null; then
        echo "[no_routing_networks] Eliminando regla FORWARD $in_iface -> $out_iface..."
        sudo iptables -D FORWARD -i "$in_iface" -o "$out_iface" -j ACCEPT
    else
        echo "[no_routing_networks] La regla FORWARD $in_iface -> $out_iface no existe, se omite."
    fi
}

del_rule "$GW1" "$GW2"
del_rule "$GW2" "$GW1"

echo "[no_routing_networks] Enrutamiento deshabilitado entre VLAN $VLAN1 y VLAN $VLAN2."
