#!/usr/bin/env bash
set -euo pipefail

export ARCH="${ARCH-x86-64}"
SCRIPTFOLDER="$(dirname "$(readlink -f "$0")")"

if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Usage: $0 VERSION SYSEXTNAME"
  echo "The script will use portage to compile firewalld and its dependancies, and create a sysext squashfs image with the name SYSEXTNAME.raw in the current folder."
  echo "A temporary directory named SYSEXTNAME in the current folder will be created and deleted again."
  echo "All files in the sysext image will be owned by root."
  echo "The build process requires docker"
  "${SCRIPTFOLDER}"/bake.sh --help
  exit 1
fi

VERSION="$1"
SYSEXTNAME="$2"

mkdir -p ${SYSEXTNAME}

(docker stop gentoo-firewalld-builder && sleep 10) || true;

docker run --rm -d \
    --name=gentoo-firewalld-builder \
    -v ${SCRIPTFOLDER}:/data \
    gentoo/stage3:latest \
    sleep infinity

docker exec \
    gentoo-firewalld-builder \
    emerge-webrsync

# Install required python version
# NOTE: This must match the version in the official python sysext image
docker exec \
    gentoo-firewalld-builder \
    emerge -v dev-lang/python:3.11
docker exec \
    gentoo-firewalld-builder \
    sh -c \
    'echo PYTHON_SINGLE_TARGET=\"python3_11\" \
        >> /etc/portage/make.conf'
docker exec \
    gentoo-firewalld-builder \
    sh -c \
    'echo PYTHON_TARGETS=\"python3_11 python3_12\" \
        >> /etc/portage/make.conf'
docker exec \
    gentoo-firewalld-builder \
    cat /etc/portage/make.conf

docker exec \
    -e USE="nftables json python xtables python3_11 -python3_12" \
    gentoo-firewalld-builder \
    emerge --verbose =net-firewall/firewalld-${VERSION}

docker exec \
    gentoo-firewalld-builder \
    rm -rf /data/${SYSEXTNAME}

# Create destination sysext directories
for P in usr/bin \
    usr/lib \
    usr/lib/python3.11/site-packages \
    usr/lib/systemd/system/ \
    usr/lib64 \
    usr/share/dbus-1/system.d \
    usr/share/polkit-1/actions; do
    docker exec \
    gentoo-firewalld-builder \
        mkdir -p /data/${SYSEXTNAME}/${P}
done

# Populate sysext
for P in usr/bin/firewall-cmd \
    usr/bin/firewall-offline-cmd \
    usr/lib/firewalld \
    usr/lib/python3.11/site-packages/dbus \
    usr/lib/python3.11/site-packages/firewall \
    usr/lib/python3.11/site-packages/gi \
    usr/lib/python3.11/site-packages/nftables \
    usr/lib/python3.11/site-packages/_dbus_bindings.so \
    usr/lib/python3.11/site-packages/_dbus_glib_bindings.so \
    usr/lib64/girepository-1.0 \
    usr/lib64/libgirepository-1.0.so \
    usr/lib64/libgirepository-1.0.so.1 \
    usr/lib64/libgirepository-1.0.so.1.0.0 \
    usr/lib64/libnftables.so \
    usr/lib64/libnftables.so.1 \
    usr/lib64/libnftables.so.1.1.0 \
    usr/share/dbus-1/system.d/FirewallD.conf \
    usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.desktop.policy.choice \
    usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.policy \
    usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.server.policy.choice; do

    docker exec \
    gentoo-firewalld-builder \
        cp -R /${P} /data/${SYSEXTNAME}/${P}
done

# We can't use default sbin location as in flatcar /usr/sbin is a symlink to /usr/bin
docker exec \
    gentoo-firewalld-builder \
        cp -R /usr/sbin/firewalld /data/${SYSEXTNAME}/usr/bin/firewalld

# Copy service file
docker exec \
    gentoo-firewalld-builder \
    cp \
        /lib/systemd/system/firewalld.service \
        /data/${SYSEXTNAME}/usr/lib/systemd/system/firewalld.service

docker exec \
    gentoo-firewalld-builder \
    mkdir -p -m 777 /data/${SYSEXTNAME}/usr/lib/extension-release.d

docker exec \
    gentoo-firewalld-builder \
    ls -lhR /data/${SYSEXTNAME}

docker exec \
    gentoo-firewalld-builder \
    du -h /data/${SYSEXTNAME}

RELOAD=1 "${SCRIPTFOLDER}"/bake.sh "${SYSEXTNAME}"

docker exec \
    gentoo-firewalld-builder \
    rm -rf /data/${SYSEXTNAME}

docker stop gentoo-firewalld-builder
