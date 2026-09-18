#!/bin/bash
#SBATCH --job-name=qe-pw
#SBATCH --account=YOUR_ACCOUNT        # e.g. from `sacctmgr show assoc user=$USER`
#SBATCH --partition=ct112             # 112 cores == one full node
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=56          # 56 MPI ranks ...
#SBATCH --cpus-per-task=2             # ... x 2 OpenMP threads == 112 cores
#SBATCH --time=01:00:00
#SBATCH --output=%x.%j.out
#
# Example production job for a Quantum ESPRESSO build made by this installer.
# Adjust the account, partition and the rank/thread split for your workload.

set -o errexit -o nounset -o pipefail

module use "${HOME}/opt/modulefiles"
module load quantum-espresso/7.6-intel-2024.0

# One OpenMP thread per allocated core, pinned. On Sapphire Rapids, pure MPI
# is usually fastest for small cells; OpenMP helps when memory per rank is the
# constraint. Benchmark your own system.
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK}"
export OMP_PLACES=cores
export OMP_PROC_BIND=close

# -nk splits the k-points across pools: use a divisor of the number of ranks
# that is also <= the number of k-points.
srun pw.x -nk 4 -in scf.in > scf.out
