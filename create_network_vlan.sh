#!/bin/bash
#
# create_network_vlan.sh - Crea una red VLAN aislada sobre el bridge OVS
# local 'br-int', con su gateway y, opcionalmente, un servidor DHCP en un
# network namespace dedicado.
#
# Uso:
#   ./create_network_vlan.sh <vlan_id> <cidr> <dhcp_enabled> [dhcp_range_start] [dhcp_range_end]
#
# Parametros de entrada:
#   $1  VLAN ID (ej. 100)
#   $2  Direccion de red en formato CIDR (ej. 192.168.0.0/24)
#   $3  DHCP habilitado: "true" o "false"
#   $4  (solo si $3=true) primera IP del rango DHCP (ej. 192.168.0.11)
#   $5  (solo si $3=true) ultima IP del rango DHCP (ej. 192.168.0.15)
#
# Acciones:
#   1. Crea una interfaz interna en el OVS 'br-int' etiquetada con el
#      VLAN ID indicado, y le asigna la PRIMERA direccion util de la red
#      (ej. 192.168.0.1), que funcionara como gateway de esa VLAN.
#   2. Si DHCP esta habilitado:
#      - Crea un Linux Network Namespace dedicado a esa VLAN.
#      - Dentro del namespace, crea una interfaz interna en OVS con el
#        mismo VLAN ID, usando la SEGUNDA direccion util de la red
#        (ej. 192.168.0.2).
#      - Levanta un servidor DHCP (dnsmasq) dentro del namespace, con el
#        rango de direcciones indicado, enviando como gateway por defecto
#        la interfaz creada en el paso 1.

set -euo pipefail

if [ "$#" -lt 3 ]; then
    echo "Uso: $0 <vlan_id> <cidr> <dhcp_enabled:true|false> [dhcp_range_start] [dhcp_range_end]" >&2
    exit 1
fi

VLAN_ID=$1
CIDR=$2
DHCP_ENABLED=$3
BRIDGE="br-int"

# --- Descomponer el CIDR en red y prefijo ---
NET_ADDR="${CIDR%/*}"
PREFIX="${CIDR#*/}"
IFS='.' read -r O1 O2 O3 O4 <<< "$NET_ADDR"

GW_IP="${O1}.${O2}.${O3}.1"
DHCP_IP="${O1}.${O2}.${O3}.2"

# --- Convertir prefijo CIDR a mascara decimal (ej. 24 -> 255.255.255.0) ---
cidr_to_netmask() {
    local prefix=$1
    local mask=""
    local full_octets=$((prefix / 8))
    local partial=$((prefix % 8))
    for ((i = 0; i < 4; i++)); do
        if [ "$i" -lt "$full_octets" ]; then
            mask+="255"
        elif [ "$i" -eq "$full_octets" ] && [ "$partial" -gt 0 ]; then
            mask+=$((256 - 2 ** (8 - partial)))
        else
            mask+="0"
        fi
        [ "$i" -lt 3 ] && mask+="."
    done
    echo "$mask"
}
NETMASK=$(cidr_to_netmask "$PREFIX")

GW_PORT="gw_vlan${VLAN_ID}"

# 1. Interfaz gateway de la VLAN
if sudo ovs-vsctl list-ports "$BRIDGE" | grep -qx "$GW_PORT"; then
    echo "[create_network_vlan] El puerto '$GW_PORT' ya existe, se omite creacion."
else
    echo "[create_network_vlan] Creando gateway '$GW_PORT' (VLAN $VLAN_ID, IP ${GW_IP}/${PREFIX})..."
    sudo ovs-vsctl add-port "$BRIDGE" "$GW_PORT" tag="$VLAN_ID" -- set interface "$GW_PORT" type=internal
    sudo ip addr add "${GW_IP}/${PREFIX}" dev "$GW_PORT"
    sudo ip link set dev "$GW_PORT" up
fi

# 2. Servidor DHCP (opcional)
if [ "$DHCP_ENABLED" = "true" ]; then
    if [ "$#" -lt 5 ]; then
        echo "Error: con DHCP habilitado se requieren <dhcp_range_start> y <dhcp_range_end>." >&2
        exit 1
    fi
    DHCP_RANGE_START=$4
    DHCP_RANGE_END=$5
    NS="ns-dhcp-vlan${VLAN_ID}"
    DHCP_PORT="dhcp_v${VLAN_ID}"

    if sudo ip netns list | grep -qx "$NS"; then
        echo "[create_network_vlan] El namespace '$NS' ya existe, se omite creacion de DHCP."
    else
        echo "[create_network_vlan] Creando namespace DHCP '$NS' (IP ${DHCP_IP}/${PREFIX})..."
        sudo ovs-vsctl add-port "$BRIDGE" "$DHCP_PORT" tag="$VLAN_ID" -- set interface "$DHCP_PORT" type=internal
        sudo ip netns add "$NS"
        sudo ip link set "$DHCP_PORT" netns "$NS"
        sudo ip netns exec "$NS" ip addr add "${DHCP_IP}/${PREFIX}" dev "$DHCP_PORT"
        sudo ip netns exec "$NS" ip link set dev "$DHCP_PORT" up
        sudo ip netns exec "$NS" ip link set dev lo up

        # Archivo de leases dedicado por VLAN: dnsmasq usa por defecto
        # /var/lib/misc/dnsmasq.leases, que vive en el filesystem compartido
        # (los network namespaces no aislan el disco), asi que si no se
        # dedica un archivo por VLAN, leases de corridas anteriores se
        # acumulan ahi y pueden agotar el rango de direcciones disponibles.
        LEASE_FILE="/tmp/dnsmasq-vlan${VLAN_ID}.leases"
        sudo rm -f "$LEASE_FILE"

        echo "[create_network_vlan] Levantando dnsmasq en '$NS' (rango ${DHCP_RANGE_START}-${DHCP_RANGE_END})..."
        sudo ip netns exec "$NS" dnsmasq \
            --interface="$DHCP_PORT" \
            --bind-interfaces \
            --except-interface=lo \
            --dhcp-range="${DHCP_RANGE_START},${DHCP_RANGE_END},${NETMASK},12h" \
            --dhcp-option=3,"$GW_IP" \
            --dhcp-leasefile="$LEASE_FILE" \
            --no-resolv --no-hosts
    fi
else
    echo "[create_network_vlan] DHCP deshabilitado para esta VLAN, no se crea namespace."
fi

echo "[create_network_vlan] Red VLAN $VLAN_ID ($CIDR) creada correctamente."
