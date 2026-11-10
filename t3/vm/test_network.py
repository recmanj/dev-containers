import unittest
from unittest.mock import patch

from network import main, validate_leases, validate_network


MAC = "52:54:00:12:34:56"
ADDRESS = "192.168.122.50"
HOST = f'<host mac="{MAC}" name="t3-dev" ip="{ADDRESS}"/>'


def network(hosts=""):
    return f'''<network><forward mode="nat"/>
    <ip address="192.168.122.1" netmask="255.255.255.0">
      <dhcp><range start="192.168.122.2" end="192.168.122.254"/>{hosts}</dhcp>
    </ip></network>'''


class NetworkTests(unittest.TestCase):
    def test_existing_reservation_is_idempotent(self):
        self.assertFalse(validate_network(network(), ADDRESS, MAC, "t3-dev"))
        self.assertTrue(validate_network(network(HOST), ADDRESS, MAC, "t3-dev"))

    def test_conflicts_and_unusable_addresses_are_rejected(self):
        for address in ("192.168.122.0", "192.168.122.255", "192.168.122.1", "10.0.0.2"):
            with self.subTest(address=address), self.assertRaises(ValueError):
                validate_network(network(), address, MAC, "t3-dev")
        for host in (HOST.replace(MAC, "52:54:00:99:99:99"),
                     HOST.replace(ADDRESS, "192.168.122.51"),
                     HOST.replace("t3-dev", "another")):
            with self.subTest(host=host), self.assertRaises(ValueError):
                validate_network(network(host), ADDRESS, MAC, "t3-dev")

    def test_bridge_network_rejected(self):
        with self.assertRaises(ValueError):
            validate_network(network().replace('mode="nat"', 'mode="bridge"'), ADDRESS, MAC, "t3-dev")

    def test_other_guests_lease_cannot_be_stolen(self):
        lease = f"2026-11-10 12:00:00 {MAC} ipv4 {ADDRESS}/24 t3-dev -"
        validate_leases(lease, ADDRESS, MAC)
        with self.assertRaises(ValueError):
            validate_leases(lease.replace(MAC, "52:54:00:99:99:99"), ADDRESS, MAC)

    def test_partial_update_retries_only_missing_side(self):
        with patch("sys.argv", ["network.py", "reserve", "t3-dev", ADDRESS, MAC]), \
                patch("network.virsh", side_effect=[network(), network(HOST), "", ""]) as run:
            main()
        updates = [call.args for call in run.call_args_list if call.args[0] == "net-update"]
        self.assertEqual(len(updates), 1)
        self.assertEqual(updates[0][-1], "--live")


if __name__ == "__main__":
    unittest.main()
