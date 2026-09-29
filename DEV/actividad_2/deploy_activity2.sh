#!/bin/bash
#
# deploy_activity2.sh - Actividad 2 del Reporte Final: redes aisladas
# VLAN 100 y VLAN 200, SIN DHCP (direccionamiento estatico) y con salida
# a Internet, ruteadas entre si. Se ejecuta desde Server 4.

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
VLAN2_GW=192.168.2.1
VLAN2_STATIC_CONT=192.168.2.10
VLAN2_STATIC_VM=192.168.2.20

run() {
    local host=$1; shift
    local script=$1; shift
    ssh -o StrictHostKeyChecking=no "ubuntu@${host}" 'bash -s' "$@" < "${SCRIPTS_DIR}/${script}"
}

echo "== [1/6] Inicializando master (Server 3) y workers (Server 1, Server 2) =="
run "$SERVER3" init_master.sh "$IFACE"
run "$SERVER1" init_worker.sh "$IFACE"
run "$SERVER2" init_worker.sh "$IFACE"

echo "== [2/6] Creando VLAN 100 y VLAN 200 SIN DHCP en Server 3 =="
run "$SERVER3" create_network_vlan.sh "$VLAN1_ID" "$VLAN1_CIDR" false
run "$SERVER3" create_network_vlan.sh "$VLAN2_ID" "$VLAN2_CIDR" false

echo "== [3/6] Habilitando salida a Internet para ambas VLANs =="
run "$SERVER3" internet_to_network.sh "$VLAN1_ID" "$VLAN1_CIDR"
run "$SERVER3" internet_to_network.sh "$VLAN2_ID" "$VLAN2_CIDR"

echo "== [4/6] Habilitando enrutamiento entre VLAN 100 y VLAN 200 =="
run "$SERVER3" routing_networks.sh "$VLAN1_ID" "$VLAN2_ID"

echo "== [5/6] Desplegando contenedores en Server 1 con IP estatica =="
ssh -o StrictHostKeyChecking=no "ubuntu@${SERVER1}" bash -s <<EOSSH
set -euo pipefail
for vlan in 100:container_vlan100:veth_ovs_100:veth_cont_100:${VLAN1_STATIC_CONT}:${VLAN1_GW} 200:container_vlan200:veth_ovs_200:veth_cont_200:${VLAN2_STATIC_CONT}:${VLAN2_GW}; do
    IFS=':' read -r VLAN NAME OVSIDE CONTSIDE IP GW <<< "\$vlan"
    if ! sudo docker ps -a --format '{{.Names}}' | grep -qx "\$NAME"; then
        sudo docker run --rm --network none --name "\$NAME" --cap-add=NET_ADMIN -d alpine sleep infinity
    fi
    if ! sudo ovs-vsctl list-ports br-int | grep -qx "\$OVSIDE"; then
        sudo ip link add "\$OVSIDE" type veth peer name "\$CONTSIDE"
        sudo ovs-vsctl add-port br-int "\$OVSIDE" tag="\$VLAN"
        sudo ip link set dev "\$OVSIDE" up
        PID=\$(sudo docker inspect -f '{{.State.Pid}}' "\$NAME")
        sudo ip link set "\$CONTSIDE" netns "\$PID"
    fi
    sudo docker exec "\$NAME" ip addr add "\${IP}/24" dev "\$CONTSIDE" 2>/dev/null || true
    sudo docker exec "\$NAME" ip link set dev "\$CONTSIDE" up
    sudo docker exec "\$NAME" ip route replace default via "\$GW" 2>/dev/null || true
done
echo "Contenedores listos (IP estatica)."
EOSSH

echo "== [6/6] Desplegando VMs en Server 2 (IP estatica se configura manualmente dentro de cada VM via VNC) =="
run "$SERVER2" create_vm.sh vm_vlan100 br-int "$VLAN1_ID" 5901
run "$SERVER2" create_vm.sh vm_vlan200 br-int "$VLAN2_ID" 5902
echo "Recordatorio: dentro de cada VM (VNC 5901 / 5902) configurar manualmente:"
echo "  sudo ip addr add ${VLAN1_STATIC_VM}/24 dev eth0 ; sudo ip route add default via ${VLAN1_GW}   (VM VLAN 100)"
echo "  sudo ip addr add ${VLAN2_STATIC_VM}/24 dev eth0 ; sudo ip route add default via ${VLAN2_GW}   (VM VLAN 200)"

echo "== Actividad 2 desplegada correctamente =="
