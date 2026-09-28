#!/bin/bash
#
# create_vm.sh - Crea una VM (Cirros) conectada a una VLAN especifica de un
# bridge OVS ya existente, siguiendo el mismo esquema usado manualmente en
# el laboratorio anterior (imagen diferencial QCOW2, interfaz TAP, VNC).
#
# Uso:
#   ./create_vm.sh <nombre_vm> <nombre_ovs> <vlan_id> <puerto_vnc>
#
# Parametros de entrada:
#   $1  Nombre de la VM (se usa como base para el nombre de la imagen,
#       la interfaz TAP y el proceso QEMU)
#   $2  Nombre del bridge OVS al cual conectar la VM (ej. br-int)
#   $3  VLAN ID a la cual pertenecera la VM
#   $4  Puerto VNC a exponer (ej. 5901 -> display :1)
#
# Acciones:
#   1. Detecta si existe la imagen base (cirros-0.5.1-x86_64-disk.img). De
#      no existir, la descarga.
#   2. Crea una imagen QCOW2 diferencial para la VM, usando la imagen base
#      como backing file.
#   3. Crea la interfaz TAP correspondiente y la activa.
#   4. Levanta la VM con QEMU/KVM, con salida VNC en el puerto indicado,
#      conectada a la TAP creada.
#   5. Conecta la TAP al bridge OVS indicado, etiquetada con el VLAN ID
#      indicado.

set -euo pipefail

if [ "$#" -lt 4 ]; then
    echo "Uso: $0 <nombre_vm> <nombre_ovs> <vlan_id> <puerto_vnc>" >&2
    exit 1
fi

VM_NAME=$1
OVS_NAME=$2
VLAN_ID=$3
VNC_PORT=$4

BASE_IMG_NAME="cirros-0.5.1-x86_64-disk.img"
BASE_IMG_URL="http://download.cirros-cloud.net/0.5.1/${BASE_IMG_NAME}"
VM_IMG="${VM_NAME}.qcow2"
TAP_NAME="tap_${VM_NAME}"

if [ "$VNC_PORT" -lt 5900 ]; then
    echo "Error: el puerto VNC debe ser >= 5900." >&2
    exit 1
fi
VNC_DISPLAY=$((VNC_PORT - 5900))

# 1. Imagen base: descargar si no existe
if [ -f "$BASE_IMG_NAME" ]; then
    echo "[create_vm] La imagen base '$BASE_IMG_NAME' ya existe, no se descarga."
else
    echo "[create_vm] Descargando imagen base '$BASE_IMG_NAME'..."
    wget -q "$BASE_IMG_URL" -O "$BASE_IMG_NAME"
fi

# 2. Imagen diferencial de la VM
if [ -f "$VM_IMG" ]; then
    echo "[create_vm] La imagen '$VM_IMG' ya existe, se omite creacion (¿la VM ya existia?)."
else
    echo "[create_vm] Creando imagen diferencial '$VM_IMG'..."
    qemu-img create -f qcow2 -b "$BASE_IMG_NAME" -F qcow2 "$VM_IMG"
fi

# 3. Interfaz TAP
if ip link show "$TAP_NAME" &>/dev/null; then
    echo "[create_vm] La interfaz TAP '$TAP_NAME' ya existe, se omite creacion."
else
    echo "[create_vm] Creando interfaz TAP '$TAP_NAME'..."
    sudo ip tuntap add mode tap name "$TAP_NAME"
fi
sudo ip link set dev "$TAP_NAME" up

# MAC determinista a partir del nombre de la VM (evita colisiones entre VMs
# con distinto nombre, y es reproducible entre corridas del mismo script)
MAC_SUFFIX=$(echo -n "$VM_NAME" | md5sum | cut -c1-6 | sed 's/\(..\)\(..\)\(..\)/\1:\2:\3/')
MAC="52:54:00:${MAC_SUFFIX}"

# 4. Levantar la VM
if pgrep -f "qemu-system-x86_64.*${VM_IMG}" &>/dev/null; then
    echo "[create_vm] Ya existe un proceso QEMU corriendo para '${VM_IMG}', se omite arranque."
else
    echo "[create_vm] Levantando VM '$VM_NAME' (VNC :${VNC_DISPLAY}, MAC ${MAC})..."
    sudo qemu-system-x86_64 \
        -enable-kvm \
        -vnc "0.0.0.0:${VNC_DISPLAY}" \
        -netdev tap,id=net0,ifname="$TAP_NAME",script=no,downscript=no \
        -device e1000,netdev=net0,mac="$MAC" \
        -daemonize \
        "$VM_IMG"
fi

# 5. Conectar la TAP al bridge OVS en la VLAN indicada
if sudo ovs-vsctl list-ports "$OVS_NAME" | grep -qx "$TAP_NAME"; then
    echo "[create_vm] La TAP '$TAP_NAME' ya esta conectada a '$OVS_NAME'."
else
    echo "[create_vm] Conectando '$TAP_NAME' a '$OVS_NAME' (VLAN $VLAN_ID)..."
    sudo ovs-vsctl add-port "$OVS_NAME" "$TAP_NAME" tag="$VLAN_ID"
fi

echo "[create_vm] VM '$VM_NAME' creada: imagen=$VM_IMG, tap=$TAP_NAME, vnc=$VNC_PORT, mac=$MAC"
