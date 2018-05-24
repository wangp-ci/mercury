#!/bin/bash
set -eux
prefix=$1
tarball=$2
if [[ -d "$prefix" ]] ; then
    exit
fi
test -f "$tarball" || wget "http://dl.mercurylang.org/rotd/$tarball"
tar xf "$tarball"
cd "${tarball%.tar.gz}"
./configure --prefix="$prefix" --with-default-grade=hlc.gc --enable-libgrades=hlc.gc
make -j2
make -j2 install
