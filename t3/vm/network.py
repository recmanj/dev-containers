#!/usr/bin/env python3
"""Check or reserve a VM address on libvirt's default NAT network."""

import argparse
import ipaddress
import subprocess
import xml.etree.ElementTree as ET


def validate_network(xml, address, mac, name):
    root = ET.fromstring(xml)
    forward = root.find("forward")
    if forward is None or forward.get("mode") != "nat":
        raise ValueError("The default network must use NAT")
    ip = ipaddress.IPv4Address(address)
    for block in root.findall("ip"):
        if block.get("family", "ipv4") != "ipv4":
            continue
        mask = block.get("prefix") or block.get("netmask")
        subnet = ipaddress.ip_network(f"{block.get('address')}/{mask}", strict=False)
        if ip not in subnet:
            continue
        if ip in (subnet.network_address, subnet.broadcast_address,
                  ipaddress.ip_address(block.get("address"))):
            raise ValueError("VM address cannot be the network, broadcast, or gateway address")
        dhcp = block.find("dhcp")
        if dhcp is None:
            raise ValueError("The selected subnet has no DHCP server")
        present = False
        for host in dhcp.findall("host"):
            if (host.get("ip") == address or host.get("mac", "").lower() == mac
                    or host.get("name") == name):
                if (host.get("ip"), host.get("mac", "").lower(), host.get("name")) != (address, mac, name):
                    raise ValueError("IP, MAC or hostname conflicts with an existing reservation")
                present = True
        return present
    raise ValueError(f"{address} is outside the default network; choose --ip from its subnet")


def validate_leases(text, address, mac):
    # virsh emits a human-readable table; examine only fields that parse as
    # IPv4 interfaces, without depending on translated headings.
    for line in text.splitlines():
        fields = line.split()
        for field in fields:
            if "/" not in field:
                continue
            try:
                leased_ip = str(ipaddress.IPv4Interface(field).ip)
            except ValueError:
                continue
            if leased_ip == address and mac not in [word.lower() for word in fields]:
                raise ValueError(f"{address} is leased to another VM")


def virsh(*arguments):
    return subprocess.check_output(["virsh", "-c", "qemu:///system", *arguments], text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["check", "reserve"])
    parser.add_argument("name")
    parser.add_argument("address")
    parser.add_argument("mac")
    args = parser.parse_args()
    try:
        # Check both persistent and running definitions before changing either.
        live = validate_network(virsh("net-dumpxml", "default"), args.address, args.mac, args.name)
        config = validate_network(virsh("net-dumpxml", "default", "--inactive"),
                                  args.address, args.mac, args.name)
        validate_leases(virsh("net-dhcp-leases", "default"), args.address, args.mac)
        if args.action == "reserve":
            host = ET.tostring(ET.Element("host", mac=args.mac, name=args.name, ip=args.address),
                               encoding="unicode")
            # Separate operations allow retry after a partial update.
            for present, flag in ((config, "--config"), (live, "--live")):
                if not present:
                    virsh("net-update", "default", "add-last", "ip-dhcp-host", host, flag)
    except (ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f"Network configuration failed: {exc}\n")


if __name__ == "__main__":
    main()
