#!/bin/bash
set -eux
prefix=$1
tarball=$2
# XXX change version
if "$prefix/bin/mmc" --version | grep rotd-2018-05-23
then
    exit
fi
test -f "$tarball" || wget "http://dl.mercurylang.org/rotd/$tarball"
tar xf "$tarball"
cd "${tarball%.tar.gz}"
./configure --prefix="$prefix" --with-default-grade=hlc.gc --enable-libgrades=hlc.gc
make -j2
make -j2 install
