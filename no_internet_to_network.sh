#!/bin/bash
#
# no_internet_to_network.sh - Deshabilita la salida a Internet de una VLAN,
# eliminando las reglas creadas por internet_to_network.sh.
#
# Uso:
#   ./no_internet_to_network.sh <vlan_id> <cidr>
#
# Parametros de entrada:
#   $1  VLAN ID
#   $2  Direccion de red en formato CIDR (ej. 192.168.0.0/24)
#
# Acciones:
#   1. Elimina la regla de Iptables (tabla nat, cadena POSTROUTING) que
#      aplica MASQUERADE al trafico de esa VLAN.
#   2. Elimina la regla en la cadena FORWARD que autorizaba el trafico
#      saliente de esa VLAN hacia la interfaz externa.

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Uso: $0 <vlan_id> <cidr>" >&2
    exit 1
fi

VLAN_ID=$1
CIDR=$2
GW_PORT="gw_vlan${VLAN_ID}"

EXT_IFACE=$(ip route show default | awk '{print $5; exit}')
if [ -z "$EXT_IFACE" ]; then
    echo "Error: no se pudo determinar la interfaz de salida a Internet." >&2
    exit 1
fi

# 1. Eliminar la regla de FORWARD (si existe)
if sudo iptables -C FORWARD -i "$GW_PORT" -o "$EXT_IFACE" -j ACCEPT 2>/dev/null; then
    echo "[no_internet_to_network] Eliminando regla de FORWARD de '$GW_PORT' hacia '$EXT_IFACE'..."
    sudo iptables -D FORWARD -i "$GW_PORT" -o "$EXT_IFACE" -j ACCEPT
else
    echo "[no_internet_to_network] La regla de FORWARD para VLAN $VLAN_ID no existe, se omite."
fi

# 2. Eliminar la regla de NAT (si existe)
if sudo iptables -t nat -C POSTROUTING -s "$CIDR" -o "$EXT_IFACE" -j MASQUERADE 2>/dev/null; then
    echo "[no_internet_to_network] Eliminando regla de MASQUERADE para VLAN $VLAN_ID ($CIDR)..."
    sudo iptables -t nat -D POSTROUTING -s "$CIDR" -o "$EXT_IFACE" -j MASQUERADE
else
    echo "[no_internet_to_network] La regla de MASQUERADE para VLAN $VLAN_ID no existe, se omite."
fi

echo "[no_internet_to_network] Salida a Internet deshabilitada para VLAN $VLAN_ID."
