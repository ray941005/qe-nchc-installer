#!/usr/bin/env bash
# Reference values for the bulk-silicon smoke test.
#
# Provenance of QE_SMOKE_ENERGY_RY: measured on NCHC Forerunner 1 with
# Quantum ESPRESSO 7.6 built by this installer (Intel oneAPI 2024.0, ifort,
# MPI + OpenMP, MKL). Before being recorded here it was checked to be
# bit-identical across 1, 2 and 4 MPI ranks and 1 and 4 OpenMP threads, so it
# reflects the physics of the input rather than one particular decomposition.
#
# The tolerance is loose enough to absorb legitimate differences in summation
# order between compilers, rank counts and MKL versions, and tight enough that
# a genuinely broken build (wrong pseudopotential, broken FFT or BLAS,
# mis-applied optimisation flags) cannot pass: such failures move the total
# energy by milli-Rydberg or more, not by 10 micro-Rydberg.

QE_SMOKE_ENERGY_RY="-15.84452726"
QE_SMOKE_ENERGY_TOL_RY="1.0e-5"

# sha256 of the vendored Si.pz-vbc.UPF pseudopotential, from
# https://pseudopotentials.quantum-espresso.org/upf_files/Si.pz-vbc.UPF
QE_SMOKE_PSEUDO_SHA256="e8d933754cd51c6bb4b2a809151f89e0647e53d878bab88d26e1b5a5d68d5217"
