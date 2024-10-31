#!/bin/bash
set -euox pipefail

# Dumps details about the instance running the CI job.
CPUS=$(nproc)
MEM=$(free -m | grep -oP '\d+' | head -n 1)
DISK=$(df --output=size -h / | sed '1d;s/[^0-9]//g')
HOSTNAME=$(uname -n)
USER=$(whoami)
ARCH=$(uname -m)
KERNEL=$(uname -r)

echo -e "\033[0;36m"
cat << EOF
------------------------------------------------------------------------------
CI MACHINE SPECS
------------------------------------------------------------------------------
     Hostname: ${HOSTNAME}
         User: ${USER}
         CPUs: ${CPUS}
          RAM: ${MEM} MB
         DISK: ${DISK} GB
         ARCH: ${ARCH}
       KERNEL: ${KERNEL}
------------------------------------------------------------------------------
EOF
echo "CPU info"
lscpu
echo -e "\033[0m"

# Get OS data.
source /etc/os-release

# Colorful output.
function greenprint {
    echo -e "\033[1;32m${1}\033[0m"
}

# Setup variables
TEST_UUID=$(uuidgen)
OS_VARIANT="rhel9-unknown"
BOOT_ARGS="uefi"
LIBVIRT_IMAGE_PATH_UEFI=/var/lib/libvirt/images/disk.qcow2
SSH_OPTIONS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
EDGE_USER=core
EDGE_USER_PASSWORD=foobar
# Prepare for test
greenprint "Installing required packages"
sudo dnf install -y podman git httpd wget firewalld jq expect qemu-img qemu-kvm libvirt-client libvirt-daemon-kvm libvirt-daemon virt-install rpmdevtools
greenprint "Start httpd service"
sudo systemctl enable --now httpd.service
greenprint "Start firewalld"
sudo systemctl enable --now firewalld

# Allow anyone in the wheel group to talk to libvirt.
greenprint "Allowing users in wheel group to talk to libvirt"
sudo tee /etc/polkit-1/rules.d/50-libvirt.rules > /dev/null << EOF
polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" &&
        subject.isInGroup("adm")) {
            return polkit.Result.YES;
    }
});
EOF

# Start libvirtd and test it.
greenprint "🚀 Starting libvirt daemon"
sudo systemctl start libvirtd
sudo virsh list --all > /dev/null

# Setup libvirt network
greenprint "Setup libvirt network"
sudo tee /tmp/integration.xml > /dev/null << EOF
<network xmlns:dnsmasq='http://libvirt.org/schemas/network/dnsmasq/1.0'>
  <name>integration</name>
  <uuid>1c8fe98c-b53a-4ca4-bbdb-deb0f26b3579</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='integration' zone='trusted' stp='on' delay='0'/>
  <mac address='52:54:00:36:46:ef'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.2' end='192.168.100.254'/>
      <host mac='34:49:22:B0:83:30' name='vm-1' ip='192.168.100.50'/>
      <host mac='34:49:22:B0:83:31' name='vm-2' ip='192.168.100.51'/>
      <host mac='34:49:22:B0:83:32' name='vm-3' ip='192.168.100.52'/>
    </dhcp>
  </ip>
  <dnsmasq:options>
    <dnsmasq:option value='dhcp-vendorclass=set:efi-http,HTTPClient:Arch:00016'/>
    <dnsmasq:option value='dhcp-option-force=tag:efi-http,60,HTTPClient'/>
    <dnsmasq:option value='dhcp-boot=tag:efi-http,&quot;http://192.168.100.1/httpboot/EFI/BOOT/BOOTX64.EFI&quot;'/>
  </dnsmasq:options>
</network>
EOF
if ! sudo virsh net-info integration > /dev/null 2>&1; then
    sudo virsh net-define /tmp/integration.xml
fi
if [[ $(sudo virsh net-info integration | grep 'Active' | awk '{print $2}') == 'no' ]]; then
    sudo virsh net-start integration
fi

# Build and push rhel-edge-bootc container
greenprint "Building rhel-edge-bootc container"
podman login quay.io -u ${QUAY_IO_USER} -p ${QUAY_IO_TOKEN}
podman login registry.redhat.io -u ${REDHAT_IO_USER} -p ${REDHAT_IO_TOKEN}
podman login registry.stage.redhat.io -u ${STAGE_REDHAT_IO_USER} -p ${STAGE_REDHAT_IO_TOKEN}
tee Containerfile > /dev/null << EOF
FROM registry.redhat.io/rhel9/rhel-bootc
COPY files/nightly.repo /etc/yum.repos.d/
RUN dnf install -y \
    greenboot greenboot-default-health-checks && \
    systemctl enable greenboot-grub2-set-counter \
    greenboot-grub2-set-success.service greenboot-healthcheck.service \
    greenboot-loading-message.service greenboot-rpm-ostree-grub2-check-fallback.service \
    redboot-auto-reboot.service redboot-task-runner.service redboot.target
EOF
podman build  --retry=5 --retry-delay=10 -t quay.io/${QUAY_IO_USER}/rhel-edge-bootc:latest -f Containerfile .
greenprint "Pushing rhel-edge-bootc container to quay.io"
podman push quay.io/${QUAY_IO_USER}/rhel-edge-bootc:latest

# BIB to convert container to qcow2
greenprint "Using BIB to convert container to qcow2"
tee config.json > /dev/null << EOF
{
  "blueprint": {
    "customizations": {
      "user": [
        {
          "name": "${EDGE_USER}",
          "password": "${EDGE_USER_PASSWORD}",
          "groups": [
            "wheel"
          ]
        }
      ]
    }
  }
}
EOF
mkdir -p output
podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v $(pwd)/config.json:/config.json \
    -v $(pwd)/output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 \
    --config /config.json \
    --rootfs xfs \
    quay.io/${QUAY_IO_USER}/rhel-edge-bootc:latest

# Install edge vm with qcow2 file
greenprint "Installing uefi edge vm"
cp $(pwd)/output/qcow2/disk.qcow2 /var/lib/libvirt/images/
sudo restorecon -Rv /var/lib/libvirt/images/
sudo virt-install  --name="${TEST_UUID}-uefi"\
                   --disk path="${LIBVIRT_IMAGE_PATH_UEFI}",format=qcow2 \
                   --ram 3072 \
                   --vcpus 2 \
                   --network network=integration,mac=34:49:22:B0:83:31 \
                   --os-type linux \
                   --os-variant ${OS_VARIANT} \
                   --boot ${BOOT_ARGS} \
                   --nographics \
                   --noautoconsole \
                   --wait=-1 \
                   --import \
                   --noreboot
greenprint "Starting UEFI VM"
sudo virsh start "${TEST_UUID}-uefi"

# Build upgrade container image
greenprint "Building upgrade container"
tee Containerfile > /dev/null << EOF
FROM quay.io/${QUAY_IO_USER}/rhel-edge-bootc:latest
RUN dnf install -y wget
EOF
podman build  --retry=5 --retry-delay=10 -t quay.io/${QUAY_IO_USER}/rhel-edge-bootc:latest -f Containerfile .
greenprint "Pushing upgrade container to quay.io"
podman push quay.io/${QUAY_IO_USER}/rhel-edge-bootc:latest

greenprint "Bootc upgrade and reboot"
sudo ssh "${SSH_OPTIONS[@]}" ${EDGE_USER}@192.168.100.51 "echo ${EDGE_USER_PASSWORD} |sudo -S bootc upgrade"
sudo ssh "${SSH_OPTIONS[@]}" ${EDGE_USER}@192.168.100.51 "echo ${EDGE_USER_PASSWORD} |nohup sudo -S systemctl reboot &>/dev/null & exit"