#!/usr/bin/env bash

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash
source $base_dir/lib/prelude_bosh.bash

if [ "${stemcell_operating_system_version}" != "7" ]; then
  echo "Not installing netcat from source; assuming it works already"
  exit 0
fi

nc_basename=netcat-0.7.1
nc_archive=${nc_basename}.tar.gz

mkdir -p ${chroot}/${bosh_dir}/src
cp -r ${dir}/assets/${nc_archive} ${chroot}/${bosh_dir}/src

run_in_bosh_chroot $chroot "
  cd src
  tar zxvf ${nc_archive}
  cd ${nc_basename}
  ./configure
  make && make install
"

# Ensure nc command can be found in the usual packaged location
run_in_bosh_chroot $chroot "ln -sf /usr/local/bin/nc /bin/nc"
