#!/bin/bash

sudo dnf install -y podman git rpm-build

git clone https://github.com/fedora-iot/greenboot.git
cd greenboot
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
cd ..

tee Containerfile > /dev/null << EOF
FROM registry.redhat.io/rhel9/rhel-bootc
COPY greenboot/rpmbuild/RPMS/x86_64/greenboot-*.rpm /tmp/
# Install required packages 
RUN dnf install -y \
    /tmp/greenboot-*.rpm && \
    systemctl enable greenboot-grub2-set-counter \
    greenboot-grub2-set-success.service greenboot-healthcheck.service \
    greenboot-loading-message.service greenboot-rpm-ostree-grub2-check-fallback.service \
    redboot-auto-reboot.service redboot-task-runner.service redboot.target
# Clean up by removing the local RPMs if desired
RUN rm -f /tmp/greenboot-*.rpm
EOF


podman login quay.io -u ${QUAY_IO_USER} -p ${QUAY_IO_TOKEN}
podman login registry.redhat.io -u ${REDHAT_IO_USER} -p ${REDHAT_IO_TOKEN}
podman login registry.stage.redhat.io -u "${STAGE_REDHAT_IO_USER} -p ${STAGE_REDHAT_IO_TOKEN}

podman build  --retry=5 --retry-delay=10 -t latest -f Containerfile .
