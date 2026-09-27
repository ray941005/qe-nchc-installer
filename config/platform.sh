#!/usr/bin/env bash
# config/platform.sh — the one place that encodes site-specific knowledge.
#
# Target site: NCHC 創進一號 (Forerunner 1), 2x Intel Xeon Platinum 8480+
#              (Sapphire Rapids, 112 cores/node), RHEL 8.7, Lmod 8.7, Slurm.
#
# Porting to another cluster should mean editing this file and nothing else.

QE_PLATFORM_ID="nchc-forerunner-1"
QE_PLATFORM_DESC="NCHC Forerunner 1 (創進一號) — Intel Sapphire Rapids, Lmod + Slurm"

# How to bootstrap Lmod in a non-interactive shell.
QE_LMOD_INIT_CANDIDATES=(
  "/usr/share/lmod/lmod/init/bash"
  "${LMOD_PKG:-/nonexistent}/init/bash"
)

# Fingerprint used by preflight to confirm the platform. A path, not a
# hostname: login nodes get renamed, install trees do not.
QE_PLATFORM_FINGERPRINT="/pkg/compiler/intel/2024"

# The toolchain, pinned to an exact module version. oneAPI 2024.0 ships the
# compilers, Intel MPI 2021.11 and MKL 2024.0 (BLAS, LAPACK, ScaLAPACK, BLACS
# and the FFTW3 interface) in one module, so this is the whole dependency set.
QE_TOOLCHAIN_MODULES=("intel/2024_01_46")
QE_TOOLCHAIN_ID="intel-2024.0"

# Sapphire Rapids is the only x86 CPU in this cluster, so AVX-512 is always
# available. Override with --arch-flags if that changes.
QE_ARCH_FLAGS_DEFAULT="-xCORE-AVX512"

# C compiler wrapper. oneAPI 2024.0 dropped the classic `icc`, so `icx` (via
# mpiicx) is the only option, and is used with either Fortran compiler.
QE_MPICC_WRAPPER="mpiicx"

# Fortran compiler wrappers, selected by --compiler.
qe_fortran_wrapper() {
  case $1 in
    ifort) printf 'mpiifort' ;;  # Intel Fortran Classic
    ifx)   printf 'mpiifx'   ;;  # Intel Fortran (LLVM)
    *)     return 1 ;;
  esac
}

# Defaults for the optional --slurm build path.
QE_SLURM_PARTITION_DEFAULT="development"
QE_SLURM_TIME_DEFAULT="02:00:00"
QE_SLURM_CPUS_DEFAULT="32"
