#!/bin/bash
#
# deploy_activity4.sh - Actividad 4 del Reporte Final: enrutamiento entre
# redes aisladas. VLAN 100 sin DHCP (estatica) y VLAN 200 con DHCP, ambas
# SIN salida a Internet, pero CON enrutamiento habilitado entre ellas.
# Se ejecuta desde Server 4.

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVER1=10.0.10.1
SERVER2=10.0.10.2
SERVER3=10.0.10.3
IFACE=ens4

VLAN1_ID=100
VLAN1_CIDR=192.168.0.0/24
VLAN1_GW=192.168.0.1
VLAN1_STATIC_CONT=192.168.0.10
VLAN1_STATIC_VM=192.168.0.20

VLAN2_ID=200
VLAN2_CIDR=192.168.2.0/24
DHCP_START=11
DHCP_END=15

run() {
    local host=$1; shift
    local script=$1; shift
    ssh -o StrictHostKeyChecking=no "ubuntu@${host}" 'bash -s' "$@" < "${SCRIPTS_DIR}/${script}"
}

echo "== [1/6] Inicializando master (Server 3) y workers (Server 1, Server 2) =="
run "$SERVER3" init_master.sh "$IFACE"
run "$SERVER1" init_worker.sh "$IFACE"
run "$SERVER2" init_worker.sh "$IFACE"

echo "== [2/6] Creando VLAN 100 (sin DHCP) y VLAN 200 (con DHCP) en Server 3 =="
run "$SERVER3" create_network_vlan.sh "$VLAN1_ID" "$VLAN1_CIDR" false
run "$SERVER3" create_network_vlan.sh "$VLAN2_ID" "$VLAN2_CIDR" true "192.168.2.${DHCP_START}" "192.168.2.${DHCP_END}"

echo "== [3/6] (Intencional) NO se llama internet_to_network.sh - sin salida a Internet =="

echo "== [4/6] Habilitando enrutamiento entre VLAN 100 y VLAN 200 =="
run "$SERVER3" routing_networks.sh "$VLAN1_ID" "$VLAN2_ID"

echo "== [5/6] Desplegando contenedores en Server 1 (VLAN100 estatica, VLAN200 DHCP) =="
ssh -o StrictHostKeyChecking=no "ubuntu@${SERVER1}" bash -s <<EOSSH
set -euo pipefail
# --- Contenedor VLAN 100: IP estatica ---
if ! sudo docker ps -a --format '{{.Names}}' | grep -qx container_vlan100; then
    sudo docker run --rm --network none --name container_vlan100 --cap-add=NET_ADMIN -d alpine sleep infinity
fi
if ! sudo ovs-vsctl list-ports br-int | grep -qx veth_ovs_100; then
    sudo ip link add veth_ovs_100 type veth peer name veth_cont_100
    sudo ovs-vsctl add-port br-int veth_ovs_100 tag=${VLAN1_ID}
    sudo ip link set dev veth_ovs_100 up
    PID=\$(sudo docker inspect -f '{{.State.Pid}}' container_vlan100)
    sudo ip link set veth_cont_100 netns \$PID
fi
sudo docker exec container_vlan100 ip addr add ${VLAN1_STATIC_CONT}/24 dev veth_cont_100 2>/dev/null || true
sudo docker exec container_vlan100 ip link set dev veth_cont_100 up
sudo docker exec container_vlan100 ip route replace default via ${VLAN1_GW} 2>/dev/null || true

# --- Contenedor VLAN 200: DHCP ---
if ! sudo docker ps -a --format '{{.Names}}' | grep -qx container_vlan200; then
    sudo docker run --rm --network none --name container_vlan200 --cap-add=NET_ADMIN -d alpine sleep infinity
fi
if ! sudo ovs-vsctl list-ports br-int | grep -qx veth_ovs_200; then
    sudo ip link add veth_ovs_200 type veth peer name veth_cont_200
    sudo ovs-vsctl add-port br-int veth_ovs_200 tag=${VLAN2_ID}
    sudo ip link set dev veth_ovs_200 up
    PID=\$(sudo docker inspect -f '{{.State.Pid}}' container_vlan200)
    sudo ip link set veth_cont_200 netns \$PID
    sudo docker exec container_vlan200 ip link set dev veth_cont_200 up
    sudo docker exec container_vlan200 udhcpc -i veth_cont_200 || true
fi
echo "Contenedores listos."
EOSSH

echo "== [6/6] Desplegando VMs en Server 2 (VLAN100 estatica manual, VLAN200 DHCP) =="
run "$SERVER2" create_vm.sh vm_vlan100 br-int "$VLAN1_ID" 5901
run "$SERVER2" create_vm.sh vm_vlan200 br-int "$VLAN2_ID" 5902
echo "Recordatorio: dentro de la VM VLAN 100 (VNC 5901) configurar manualmente:"
echo "  sudo ip addr add ${VLAN1_STATIC_VM}/24 dev eth0 ; sudo ip route add default via ${VLAN1_GW}"
echo "La VM VLAN 200 (VNC 5902) obtiene su IP sola via 'sudo udhcpc -i eth0'."

echo "== Actividad 4 desplegada correctamente (ruteo entre VLANs, sin Internet) =="
