#!/bin/bash
set -euo pipefail

# System service that keeps the guest's cache of share inodes bounded.
# Run inside the VM as root: sudo bash install-share-guard.sh
if [ "$(id -u)" -ne 0 ]; then
    echo 'Run as root, with sudo.' >&2
    exit 1
fi
if ! systemd-detect-virt --vm --quiet; then
    echo 'Run this inside the T3 VM, not on the host.' >&2
    exit 1
fi

cat > /usr/local/sbin/t3-share-guard <<'EOF'
#!/bin/bash
set -u

# Every share inode the guest has cached holds one file descriptor open in the
# host's virtiofsd, which stops at 524288 per share. The guest only evicts them
# under memory pressure, so one walk of a large tree makes the share fail with
# "Too many open files in system". Drop the cache well before that.
limit=250000
cached() { awk '$1 == "fuse_inode" { print $2 }' /proc/slabinfo; }

while sleep 2; do
    before=$(cached)
    [ "${before:-0}" -gt "$limit" ] || continue
    echo 2 > /proc/sys/vm/drop_caches
    sleep 1
    after=$(cached)
    echo "Dropped the inode cache: $before share inodes cached, ${after:-0} left"
    if [ "${after:-0}" -gt "$limit" ]; then
        echo 'Share inodes are still in use, so dropping cannot free them; retrying in a minute' >&2
        sleep 60
    fi
done
EOF
chmod 0755 /usr/local/sbin/t3-share-guard

cat > /etc/systemd/system/t3-share-guard.service <<'EOF'
[Unit]
Description=Keep cached share inodes below the host virtiofsd file limit

[Service]
ExecStart=/usr/local/sbin/t3-share-guard
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable t3-share-guard.service
systemctl restart t3-share-guard.service
