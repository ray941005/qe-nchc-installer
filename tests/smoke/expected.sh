#!/usr/bin/env bash
# Reference values for the bulk-silicon smoke test.
#
# The energy was measured with QE 7.6 built by this installer (oneAPI 2024.0,
# ifort, MKL) and checked to be bit-identical across 1, 2 and 4 MPI ranks and
# 1 and 4 OpenMP threads. The tolerance absorbs summation-order differences
# between compilers and MKL versions; a genuinely broken build is off by
# milli-Rydberg, not by 10 micro-Rydberg.

QE_SMOKE_ENERGY_RY="-15.84452726"
QE_SMOKE_ENERGY_TOL_RY="1.0e-5"

# sha256 of the vendored Si.pz-vbc.UPF pseudopotential, from
# https://pseudopotentials.quantum-espresso.org/upf_files/Si.pz-vbc.UPF
QE_SMOKE_PSEUDO_SHA256="e8d933754cd51c6bb4b2a809151f89e0647e53d878bab88d26e1b5a5d68d5217"
