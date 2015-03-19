#!/usr/bin/env bash

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)

source $base_dir/lib/prelude_apply.bash
source $base_dir/etc/settings.bash

mkdir -p $chroot/var/lib/rpm
rpm --root $chroot --initdb

# Setting locale
case "${stemcell_operating_system_version}" in
  (6|6.*) 
    locale_file=/etc/sysconfig/i18n 
    releaseVersion=6 
    ;;
  (7|7.*) 
    locale_file=/etc/locale.conf 
    releaseVersion=7 
    ;;
  (*)
    echo "Unknown or unset CentOS release version: '${stemcell_operating_system_version}'"
    exit 1
    ;;
esac
releaseURL="http://mirror.centos.org/centos/${releaseVersion}/os/x86_64/Packages/"
epelURL="https://dl.fedoraproject.org/pub/epel/${releaseVersion}/x86_64/e/"

# Determine the centos version release rpm url:
releaseRPM=$(curl -s ${releaseURL} | grep centos-release- | sed -e 's/^.*href=\"//' -e 's/".*$//')
if [[ -z ${releaseRPM} ]]
then
  echo "ERROR: releaseRPM not found at ${releaseURL}"
  exit 1
fi
# Determine the epel version release rpm url:
epelRPM=$(curl -s ${epelURL} | grep epel-release- | sed -e 's/^.*href=\"//' -e 's/".*$//')
if [[ -z ${releaseRPM} ]]
then echo "ERROR: epelRPM not found at ${epelURL}" >&2 && exit 1
fi

rpm --root $chroot --force --nodeps --install "${releaseURL}${releaseRPM}"

cp /etc/resolv.conf $chroot/etc/resolv.conf

dd if=/dev/urandom of=$chroot/var/lib/random-seed bs=512 count=1

unshare -m $SHELL <<INSTALL_YUM
  set -x
  mkdir -p /etc/pki
  mount --no-mtab --bind $chroot/etc/pki /etc/pki
  yum --installroot=$chroot -c /bosh/stemcell_builder/etc/custom_yum.conf --assumeyes install yum
INSTALL_YUM

run_in_chroot $chroot "
rpm --force --nodeps --install ${releaseURL}${releaseRPM}
rpm --force --nodeps --install ${epelURL}${epelRPM}
rpm --rebuilddb
"

pkg_mgr groupinstall Base
pkg_mgr groupinstall 'Development Tools'

touch ${chroot}/etc/sysconfig/network # must be present for network to be configured

# readahead-collector was pegging CPU on startup
echo 'READAHEAD_COLLECT="no"' >> ${chroot}/etc/sysconfig/readahead
echo 'READAHEAD_COLLECT_ON_RPM="no"' >> ${chroot}/etc/sysconfig/readahead

cp ${chroot}/usr/share/zoneinfo/UTC ${chroot}/etc/localtime # Timezone
echo "LANG=\"en_US.UTF-8\"" >> ${chroot}/${locale_file}     # Locale

