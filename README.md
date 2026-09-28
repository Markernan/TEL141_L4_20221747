# TEL141_L4_20221747


Todos los scripts están diseñados para ejecutarse de forma remota vía
SSH, típicamente desde un nodo cliente (Server 4) hacia los nodos que
componen el slice (Server 1, 2 y 3), usando el patrón:

```bash
ssh usuario@ip_nodo 'bash -s' < script.sh "param1" "param2" ...
```


## Scripts

| Script | Rol | Parámetros |
|---|---|---|
| `init_master.sh` | Nodo con rol de router/gateway | `iface1 [iface2 ...]` |
| `init_worker.sh` | Nodo que aloja VMs/contenedores | `iface1 [iface2 ...]` |
| `create_network_vlan.sh` | Crea una VLAN + gateway (+ DHCP opcional) | `vlan_id cidr dhcp_enabled [dhcp_start dhcp_end]` |
| `internet_to_network.sh` | Habilita salida a Internet para una VLAN | `vlan_id cidr` |
| `no_internet_to_network.sh` | Deshabilita salida a Internet de una VLAN | `vlan_id cidr` |
| `routing_networks.sh` | Habilita ruteo entre dos VLANs | `vlan_id_1 vlan_id_2` |
| `no_routing_networks.sh` | Deshabilita ruteo entre dos VLANs | `vlan_id_1 vlan_id_2` |
| `create_vm.sh` | Crea una VM Cirros conectada a una VLAN | `nombre_vm nombre_ovs vlan_id puerto_vnc` |
| `delete_vm.sh` | Elimina una VM y sus recursos | `nombre_vm nombre_ovs vlan_id puerto_vnc` |


## Ejemplo de uso end-to-end

```bash
# En el nodo master (rol router, ej. Server 3)
ssh ubuntu@server3 'bash -s' ens4 < init_master.sh
ssh ubuntu@server3 'bash -s' 100 192.168.0.0/24 false < create_network_vlan.sh
ssh ubuntu@server3 'bash -s' 200 192.168.2.0/24 true 192.168.2.11 192.168.2.15 < create_network_vlan.sh
ssh ubuntu@server3 'bash -s' 100 192.168.0.0/24 < internet_to_network.sh
ssh ubuntu@server3 'bash -s' 100 200 < routing_networks.sh

# En un nodo worker (ej. Server 1)
ssh ubuntu@server1 'bash -s' ens4 < init_worker.sh
ssh ubuntu@server1 'bash -s' vm1 br-int 100 5901 < create_vm.sh
```


# TEL141_L4_20221747
# TEL141_L4_20221747
