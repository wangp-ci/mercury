#!/bin/bash
set -eux
prefix=$1
tarball=$2
basename=${tarball%.tar.gz}
version=${basename#mercury-srcdist-}
if [[ -x "$prefix/bin/mmc" ]] && "$prefix/bin/mmc" --version | grep -F "version $version,"
then
    exit
fi
test -f "$tarball" || wget "http://dl.mercurylang.org/rotd/$tarball"
tar xf "$tarball"
cd "$basename"
./configure --prefix="$prefix" --with-default-grade=hlc.gc --enable-libgrades=hlc.gc
make PARALLEL=-j2 install
