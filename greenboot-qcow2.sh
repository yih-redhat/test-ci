#!/bin/bash
set -euox pipefail

# Dumps details about the instance running the CI job.
echo -e "\033[0;36m"
cat << EOF
------------------------------------------------------------------------------
CI MACHINE SPECS
------------------------------------------------------------------------------
     Hostname: $(uname -n)
         User: $(whoami)
         CPUs: $(nproc)
          RAM: $(free -m | grep -oP '\d+' | head -n 1) MB
         DISK: $(df --output=size -h / | sed '1d;s/[^0-9]//g') GB
         ARCH: $(uname -m)
       KERNEL: $(uname -r)
------------------------------------------------------------------------------
EOF
echo -e "\033[0m"

# Get OS info
source /etc/os-release

# Setup variables
TEST_UUID=$(uuidgen)
GUEST_ADDRESS=192.168.100.50
SSH_OPTIONS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
SSH_KEY=key/ostree_key
SSH_KEY_PUB=$(cat "${SSH_KEY}".pub)
EDGE_USER=core
EDGE_USER_PASSWORD=foobar

case "${ID}-${VERSION_ID}" in
    "rhel-9.5")
        OS_VARIANT="rhel9-unknown"
        BASE_IMAGE_URL="registry.stage.redhat.io/rhel9/rhel-bootc:9.5"
        BIB_URL="registry.stage.redhat.io/rhel9/bootc-image-builder:9.5"
        ;;
    "rhel-9.6")
        OS_VARIANT="rhel9-unknown"
        BASE_IMAGE_URL="registry.stage.redhat.io/rhel9/rhel-bootc:9.6"
        BIB_URL="registry.stage.redhat.io/rhel9/bootc-image-builder:9.6"
        ;;
    "centos-9")
        OS_VARIANT="centos-stream9"
        BASE_IMAGE_URL="quay.io/centos-bootc/centos-bootc:stream9"
        BIB_URL="quay.io/centos-bootc/bootc-image-builder:latest"
        ;;
    "fedora-41")
        OS_VARIANT="fedora-unknown"
        BASE_IMAGE_URL="quay.io/fedora/fedora-bootc:41"
        BIB_URL="quay.io/centos-bootc/bootc-image-builder:latest"
        ;;
    "fedora-42")
        OS_VARIANT="fedora-rawhide"
        BASE_IMAGE_URL="quay.io/fedora/fedora-bootc:42"
        BIB_URL="quay.io/centos-bootc/bootc-image-builder:latest"
        ;;
    *)
        echo "unsupported distro: ${ID}-${VERSION_ID}"
        exit 1;;
esac

# Colorful output.
function greenprint {
    echo -e "\033[1;32m${1}\033[0m"
}

###########################################################
##
## Prepare before run test
##
###########################################################
greenprint "Installing required packages"
sudo dnf install -y podman qemu-img qemu-kvm libvirt-client libvirt-daemon-kvm libvirt-daemon virt-install rpmdevtools

# Setup libvirt
greenprint "Starting libvirt service and configure libvirt network"
sudo tee /etc/polkit-1/rules.d/50-libvirt.rules > /dev/null << EOF
polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" &&
        subject.isInGroup("adm")) {
            return polkit.Result.YES;
    }
});
EOF
sudo systemctl start libvirtd
sudo virsh list --all > /dev/null
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

###########################################################
##
## Build greenboot rpm packages
##
###########################################################
greenprint "Building greenboot packages"
shopt -s extglob
version=$(cat greenboot.spec |grep Version|awk '{print $2}')
rm -rf greenboot-${version}/ rpmbuild/
mkdir -p rpmbuild/BUILD rpmbuild/RPMS rpmbuild/SOURCES rpmbuild/SPECS rpmbuild/SRPMS
mkdir greenboot-${version}
cp -r !(rpmbuild|greenboot-${version}|build.sh) greenboot-${version}/
tar -cvf v${version}.tar.gz  greenboot-${version}/
mv v${version}.tar.gz rpmbuild/SOURCES/
rpmbuild -bb --define="_topdir ${PWD}/rpmbuild" greenboot.spec
chmod +x rpmbuild/RPMS/x86_64/*.rpm

###########################################################
##
## Build bootc container with greenboot installed
##
###########################################################
greenprint "Building rhel-edge-bootc container"
podman login quay.io -u ${QUAY_IO_USER} -p ${QUAY_IO_TOKEN}
podman login registry.redhat.io -u ${REDHAT_IO_USER} -p ${REDHAT_IO_TOKEN}
podman login registry.stage.redhat.io -u ${STAGE_REDHAT_IO_USER} -p ${STAGE_REDHAT_IO_TOKEN}
tee Containerfile > /dev/null << EOF
FROM ${BASE_IMAGE_URL}
COPY rpmbuild/RPMS/x86_64/greenboot*.rpm /tmp/
RUN dnf install -y \
    /tmp/greenboot*.rpm && \
    systemctl enable greenboot-grub2-set-counter \
    greenboot-grub2-set-success.service greenboot-healthcheck.service \
    greenboot-loading-message.service greenboot-rpm-ostree-grub2-check-fallback.service \
    redboot-auto-reboot.service redboot-task-runner.service redboot.target
EOF
podman build  --retry=5 --retry-delay=10 -t quay.io/${QUAY_IO_USER}/greenboot-bootc:latest -f Containerfile .
greenprint "Pushing greenboot-bootc container to quay.io"
podman push quay.io/${QUAY_IO_USER}/greenboot-bootc:latest

###########################################################
##
## BIB to convert bootc container to qcow2/iso images
##
###########################################################
greenprint "Using BIB to convert container to qcow2"
tee config.json > /dev/null << EOF
{
  "blueprint": {
    "customizations": {
      "user": [
        {
          "name": "${EDGE_USER}",
          "password": "${EDGE_USER_PASSWORD}",
          "key": "${SSH_KEY_PUB}",
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
    ${BIB_URL} \
    --type qcow2 \
    --config /config.json \
    --rootfs xfs \
    quay.io/${QUAY_IO_USER}/greenboot-bootc:latest

###########################################################
##
## Provision vm with qcow2/iso artifacts
##
###########################################################
greenprint "Installing uefi edge vm"
cp $(pwd)/output/qcow2/disk.qcow2 /var/lib/libvirt/images/
LIBVIRT_IMAGE_PATH_UEFI=/var/lib/libvirt/images/disk.qcow2
sudo restorecon -Rv /var/lib/libvirt/images/
sudo virt-install  --name="${TEST_UUID}-uefi"\
                   --disk path="${LIBVIRT_IMAGE_PATH_UEFI}",format=qcow2 \
                   --ram 3072 \
                   --vcpus 2 \
                   --network network=integration,mac=34:49:22:B0:83:30 \
                   --os-type linux \
                   --os-variant ${OS_VARIANT} \
                   --boot uefi \
                   --nographics \
                   --noautoconsole \
                   --wait=-1 \
                   --import \
                   --noreboot
greenprint "Starting UEFI VM"
sudo virsh start "${TEST_UUID}-uefi"
sleep 60

###########################################################
##
## Build upgrade container with failing-unit installed
##
###########################################################
greenprint "Building upgrade container"
tee Containerfile > /dev/null << EOF
FROM quay.io/${QUAY_IO_USER}/greenboot-bootc:latest
RUN dnf install -y https://kite-webhook-prod.s3.amazonaws.com/greenboot-failing-unit-1.0-1.el8.noarch.rpm
EOF
podman build  --retry=5 --retry-delay=10 -t quay.io/${QUAY_IO_USER}/greenboot-bootc:latest -f Containerfile .
greenprint "Pushing upgrade container to quay.io"
podman push quay.io/${QUAY_IO_USER}/greenboot-bootc:latest

###########################################################
##
## Bootc upgrade and check greenboot status
##
###########################################################
greenprint "Bootc upgrade and reboot"
sudo ssh "${SSH_OPTIONS[@]}" -i "${SSH_KEY}" ${EDGE_USER}@${GUEST_ADDRESS} "echo ${EDGE_USER_PASSWORD} |sudo -S bootc upgrade"
sudo ssh "${SSH_OPTIONS[@]}" -i "${SSH_KEY}" ${EDGE_USER}@${GUEST_ADDRESS} "echo ${EDGE_USER_PASSWORD} |nohup sudo -S systemctl reboot &>/dev/null & exit"
# check greenboot status