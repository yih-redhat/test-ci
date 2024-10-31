#!/bin/bash
# Build greenboot rpm packages
greenprint "Building greenboot packages"
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