#!/bin/bash
#
# delete_vm.sh - Elimina una VM creada con create_vm.sh y todos sus recursos
# asociados (proceso QEMU, puerto OVS, interfaz TAP, imagen de disco), y
# limpia la imagen base si ya ningun otro VM depende de ella.
#
# Uso:
#   ./delete_vm.sh <nombre_vm> <nombre_ovs> <vlan_id> <puerto_vnc>
#
# Parametros de entrada:
#   $1  Nombre de la VM (usado para reconstruir el nombre de imagen/TAP)
#   $2  Nombre del bridge OVS del cual desconectar la VM
#   $3  VLAN ID a la cual pertenecia la VM (informativo)
#   $4  Puerto VNC que tenia expuesto la VM
#
# Acciones:
#   1. Detiene el proceso QEMU de la VM (si esta corriendo).
#   2. Desconecta y elimina la interfaz TAP asociada.
#   3. Elimina la imagen QCOW2 diferencial de la VM.
#   4. Si la imagen base (cirros-0.5.1-x86_64-disk.img) ya no tiene
#      ninguna otra imagen diferencial ("delta") que la use como backing
#      file, tambien la elimina.

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
VM_IMG="${VM_NAME}.qcow2"
TAP_NAME="tap_${VM_NAME}"

# 1. Detener el proceso QEMU de esta VM
PID=$(pgrep -f "qemu-system-x86_64.*${VM_IMG}" || true)
if [ -n "$PID" ]; then
    echo "[delete_vm] Deteniendo proceso QEMU de '$VM_NAME' (PID $PID)..."
    sudo kill -9 $PID
    sleep 1
else
    echo "[delete_vm] No se encontro un proceso QEMU corriendo para '$VM_NAME', se omite."
fi

# 2. Desconectar y eliminar la TAP
if sudo ovs-vsctl list-ports "$OVS_NAME" 2>/dev/null | grep -qx "$TAP_NAME"; then
    echo "[delete_vm] Desconectando '$TAP_NAME' de '$OVS_NAME'..."
    sudo ovs-vsctl del-port "$OVS_NAME" "$TAP_NAME"
fi
if ip link show "$TAP_NAME" &>/dev/null; then
    echo "[delete_vm] Eliminando interfaz TAP '$TAP_NAME'..."
    sudo ip link del "$TAP_NAME"
fi

# 3. Eliminar la imagen diferencial de la VM
if [ -f "$VM_IMG" ]; then
    echo "[delete_vm] Eliminando imagen '$VM_IMG'..."
    rm -f "$VM_IMG"
else
    echo "[delete_vm] La imagen '$VM_IMG' ya no existe, se omite."
fi

# 4. Verificar si la imagen base sigue teniendo deltas (otras VMs que la
#    usen como backing file). De no tener ninguna, eliminarla tambien.
if [ -f "$BASE_IMG_NAME" ]; then
    HAS_DELTAS="false"
    for img in *.qcow2; do
        [ -e "$img" ] || continue
        if qemu-img info "$img" 2>/dev/null | grep -q "backing file: ${BASE_IMG_NAME}"; then
            HAS_DELTAS="true"
            break
        fi
    done

    if [ "$HAS_DELTAS" = "false" ]; then
        echo "[delete_vm] Ninguna imagen depende ya de '$BASE_IMG_NAME', se elimina la imagen base."
        rm -f "$BASE_IMG_NAME"
    else
        echo "[delete_vm] La imagen base '$BASE_IMG_NAME' sigue en uso por otra(s) VM(s), se conserva."
    fi
fi

echo "[delete_vm] VM '$VM_NAME' (VLAN $VLAN_ID, VNC $VNC_PORT) eliminada correctamente."
