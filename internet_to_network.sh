#!/bin/bash
#
# internet_to_network.sh - Habilita la salida a Internet para una VLAN,
# mediante NAT (masquerading) hacia la interfaz de salida por defecto.
#
# Uso:
#   ./internet_to_network.sh <vlan_id> <cidr>
#
# Parametros de entrada:
#   $1  VLAN ID (solo informativo/identificacion de la regla)
#   $2  Direccion de red en formato CIDR (ej. 192.168.0.0/24)
#
# Acciones:
#   1. Agrega una regla de Iptables (tabla nat, cadena POSTROUTING) que
#      aplica MASQUERADE al trafico originado en la red indicada, de
#      manera que pueda salir hacia Internet a traves de la interfaz de
#      salida por defecto del host.
#   2. Agrega una regla en la cadena FORWARD (tabla filter) que autoriza
#      el trafico saliente desde el gateway de esa VLAN hacia la interfaz
#      externa (necesaria porque init_master.sh deja la politica de
#      FORWARD en DROP por defecto).

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Uso: $0 <vlan_id> <cidr>" >&2
    exit 1
fi

VLAN_ID=$1
CIDR=$2

# Interfaz de salida a Internet: la de la ruta por defecto del host
EXT_IFACE=$(ip route show default | awk '{print $5; exit}')
if [ -z "$EXT_IFACE" ]; then
    echo "Error: no se pudo determinar la interfaz de salida a Internet (sin ruta por defecto)." >&2
    exit 1
fi

GW_PORT="gw_vlan${VLAN_ID}"

# 1. Evitar duplicar la regla de NAT si ya existe
if sudo iptables -t nat -C POSTROUTING -s "$CIDR" -o "$EXT_IFACE" -j MASQUERADE 2>/dev/null; then
    echo "[internet_to_network] La regla de MASQUERADE para VLAN $VLAN_ID ($CIDR) ya existe."
else
    echo "[internet_to_network] Habilitando NAT para VLAN $VLAN_ID ($CIDR) por '$EXT_IFACE'..."
    sudo iptables -t nat -A POSTROUTING -s "$CIDR" -o "$EXT_IFACE" -j MASQUERADE
fi

# 2. Autorizar el trafico saliente de esa VLAN hacia la interfaz externa
if sudo iptables -C FORWARD -i "$GW_PORT" -o "$EXT_IFACE" -j ACCEPT 2>/dev/null; then
    echo "[internet_to_network] La regla de FORWARD para VLAN $VLAN_ID ya existe."
else
    echo "[internet_to_network] Autorizando FORWARD de '$GW_PORT' hacia '$EXT_IFACE'..."
    sudo iptables -A FORWARD -i "$GW_PORT" -o "$EXT_IFACE" -j ACCEPT
fi

echo "[internet_to_network] Listo."
