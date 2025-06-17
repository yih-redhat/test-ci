#!/bin/bash

COMPOSE_URL_96="https://composes.stream.centos.org/production"
COMPOSE_ID_96="CentOS-Stream-9-20250701.0"
OLD_COMPOSE_ID_96="CentOS-Stream-9-20250611.0"

APPS_URL="${COMPOSE_URL_96}/${COMPOSE_ID_96}/compose/AppStream/x86_64/os/Packages/"
OLD_APPS_URL="${COMPOSE_URL_96}/${OLD_COMPOSE_ID_96}/compose/AppStream/x86_64/os/Packages/"
BASEOS_URL="${COMPOSE_URL_96}/${COMPOSE_ID_96}/compose/BaseOS/x86_64/os/Packages/"
OLD_BASEOS_URL="${COMPOSE_URL_96}/${OLD_COMPOSE_ID_96}/compose/BaseOS/x86_64/os/Packages/"

special_pkgs=()
updated_pkgs=""
count=0

packages=("acl" "alternatives" "audit-libs" "basesystem" "bash" "bubblewrap" "bzip2-libs" "ca-certificates" "centos-gpg-keys" "centos-stream-release" "centos-stream-repos" "composefs" "composefs-libs" "container-selinux" "coreutils" "coreutils-common" "cpio" "cracklib" "cracklib-dicts" "criu" "criu-libs" "crypto-policies" "cyrus-sasl-lib" "dbus" "dbus-broker" "dbus-common" "device-mapper" "device-mapper-libs" "diffutils" "dracut" "expat" "file" "file-libs" "filesystem" "findutils" "fuse" "fuse-common" "fuse-libs" "fuse-overlayfs" "fuse3" "fuse3-libs" "gawk" "gawk-all-langpacks" "gdbm-libs" "gettext" "gettext-libs" "glib2" "glibc" "glibc-common" "glibc-gconv-extra" "glibc-minimal-langpack" "gmp" "gnupg2" "gnutls" "gpgme" "grep" "grub2-common" "grub2-pc" "grub2-pc-modules" "grub2-tools" "grub2-tools-minimal" "gzip" "iptables-libs" "iptables-nft" "json-c" "json-glib" "jansson" "kbd" "kbd-legacy" "kbd-misc" "keyutils-libs" "kmod" "kmod-libs" "krb5-libs" "libacl" "libarchive" "libassuan" "libattr" "libblkid" "libbrotli" "libcap" "libcap-ng" "libcom_err" "libdb" "libeconf" "libevent" "libfdisk" "libffi" "libgcrypt" "libgcc" "libgomp" "libgpg-error" "libidn2" "libkcapi" "libkcapi-hmaccalc" "libksba" "libmnl" "libmodulemd" "libmount" "libnet" "libnetfilter_conntrack" "libnfnetlink" "libnghttp2" "libnl3" "libnftnl" "libpwquality" "libpsl" "libseccomp" "libselinux" "libselinux-utils" "libsemanage" "libsigsegv" "libslirp" "libsmartcols" "libsolv" "libssh" "libssh-config" "libtasn1" "libtool-ltdl" "libunistring" "libutempter" "libuuid" "libverto" "libxcrypt" "libxcrypt-compat" "libxml2" "libyaml" "libzstd" "lua-libs" "lz4-libs" "mpfr" "ncurses-base" "ncurses-libs" "nettle" "nftables" "npth" "openldap" "openssl" "openssl-libs" "os-prober" "ostree" "ostree-libs" "pam" "passt" "passt-selinux" "pcre" "pcre2" "pcre2-syntax" "pigz" "policycoreutils" "polkit-libs" "popt" "procps-ng" "protobuf-c" "publicsuffix-list-dafsa" "python-unversioned-command" "python3" "python3-libs" "python3-pip-wheel" "python3-setuptools-wheel" "readline" "rpm" "rpm-libs" "rpm-ostree" "rpm-ostree-libs" "rpm-plugin-selinux" "sed" "selinux-policy" "selinux-policy-targeted" "setup" "shadow-utils" "shadow-utils-subid" "skopeo" "sqlite-libs" "systemd" "systemd-libs" "systemd-pam" "systemd-rpm-macros" "systemd-udev" "tar" "tpm2-tss" "tzdata" "util-linux" "util-linux-core" "which" "xz" "xz-libs" "yajl" "zlib")
special_pkgs=("basesystem" "ca-certificates" "centos-gpg-keys" "centos-stream-release" "centos-stream-repos" "container-selinux" "crypto-policies" "dbus-common" "grub2-common" "grub2-pc-modules" "kbd-legacy" "kbd-misc" "libssh-config" "libstdc++" "ncurses-base" "passt-selinux" "pcre2-syntax" "publicsuffix-list-dafsa" "python-unversioned-command" "python3-pip-wheel" "python3-setuptools-wheel" "selinux-policy" "selinux-policy-targeted" "setup" "systemd-rpm-macros" "tzdata")

for pkg in "${packages[@]}"; do
    if [[ " ${special_pkgs[*]} " == *" ${pkg} "* ]]; then
        if curl -s "${APPS_URL}" | grep -ioE ">${pkg}-[0-9].*<"; then
            new=$(curl -s "${APPS_URL}" | grep -ioE ">${pkg}-[0-9].*<" | tr -d "><")
            old=$(curl -s "${OLD_APPS_URL}" | grep -ioE ">${pkg}-[0-9].*<" | tr -d "><")
            if [[ "$new" == "$old" ]]; then
                echo "======= Package ${pkg} NOT updated ========="
            else
                echo "======= Package ${pkg} updated ========="
                updated_pkgs+=$'\n'"    ${new}"
                count=$((count + 1))
            fi
        elif curl -s "${BASEOS_URL}" | grep -ioE ">${pkg}-[0-9].*<"; then
            new=$(curl -s "${BASEOS_URL}" | grep -ioE ">${pkg}-[0-9].*<" | tr -d "><")
            old=$(curl -s "${OLD_BASEOS_URL}" | grep -ioE ">${pkg}-[0-9].*<" | tr -d "><")
            if [[ "$new" == "$old" ]]; then
                echo "======= Package ${pkg} NOT updated ========="
            else
                echo "======= Package ${pkg} updated ========="
                updated_pkgs+=$'\n'"    ${new}"
                count=$((count + 1))
            fi
        else
            echo "NOT FOUND: $pkg" >&2
        fi
    else
        if curl -s "${APPS_URL}" | grep -ioE ">${pkg}-[0-9].*x86_64.*<"; then
            new=$(curl -s "${APPS_URL}" | grep -ioE ">${pkg}-[0-9].*x86_64.*<" | tr -d "><")
            old=$(curl -s "${OLD_APPS_URL}" | grep -ioE ">${pkg}-[0-9].*x86_64.*<" | tr -d "><")
            if [[ "$new" == "$old" ]]; then
                echo "======= Package ${pkg} NOT updated ========="
            else
                echo "======= Package ${pkg} updated ========="
                updated_pkgs+=$'\n'"    ${new}"
                count=$((count + 1))
            fi
        elif curl -s "${BASEOS_URL}" | grep -ioE ">${pkg}-[0-9].*x86_64.*<"; then
            new=$(curl -s "${BASEOS_URL}" | grep -ioE ">${pkg}-[0-9].*x86_64.*<" | tr -d "><")
            old=$(curl -s "${OLD_BASEOS_URL}" | grep -ioE ">${pkg}-[0-9].*x86_64.*<" | tr -d "><")
            if [[ "$new" == "$old" ]]; then
                echo "======= Package ${pkg} NOT updated ========="
            else
                echo "======= Package ${pkg} updated ========="
                updated_pkgs+=$'\n'"    ${new}"
                count=$((count + 1))
            fi
        else
            echo "NOT FOUND: $pkg" >&2
        fi
    fi
done