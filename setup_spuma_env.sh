#!/bin/bash
# Source this to get a working SPUMA build env on PACE without modules.
export NVHPC=/usr/local/pace-apps/manual/packages/nvhpc/24.5/Linux_x86_64/24.5
export PATH=$HOME/bin_noxalt:$NVHPC/compilers/bin:$NVHPC/comm_libs/12.4/openmpi4/openmpi-4.1.5/bin:$PATH
export LD_LIBRARY_PATH=$NVHPC/compilers/lib:$NVHPC/cuda/12.4/lib64:$NVHPC/math_libs/12.4/targets/x86_64-linux/lib:$NVHPC/comm_libs/12.4/openmpi4/openmpi-4.1.5/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export MPI_ROOT=$NVHPC/comm_libs/12.4/openmpi4/openmpi-4.1.5
export have_cuda=true
source /storage/scratch1/6/sbryngelson3/spuma/etc/bashrc
