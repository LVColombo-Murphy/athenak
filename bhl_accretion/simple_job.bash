#!/bin/bash
#SBATCH --job-name=bhl_%x
#SBATCH --output=/mnt/ceph/users/lmurphy1/relativistic_bhl/output/run_log/%x-%j.out
#SBATCH --error=/mnt/ceph/users/lmurphy1/relativistic_bhl/output/run_log/%x-%j.err
#SBATCH -p gpu
#SBATCH -C a100-80gb                        # binary is built for sm_80 (Kokkos_ARCH_AMPERE80)
#SBATCH --nodes=1                           # keep all ranks on one node (a100 nodes have 4 GPUs)
#SBATCH --ntasks-per-node=4                 # 1 MPI rank == 1 GPU. Max useful value here is 8
#SBATCH --gpus-per-task=1
#SBATCH --cpus-per-task=16                  # CUDA build has no host threading; CPUs are for MPI + I/O
#SBATCH --mem=0                             # 0 is set to max, look at documentation
#SBATCH --time=04:00:00
#SBATCH --propagate=NONE                    # do NOT inherit the login shell's 8MB memlock limit
#SBATCH --mail-user l.colombo-murphy@columbia.edu
#SBATCH --mail-type all

# Usage: sbatch --job-name=s50g3 simple_job.bash s50g3
# Or:    sbatch --job-name=s50g3 simple_job.bash  (RUN_NAME defaults to job name)
RUN_NAME=${1:-$SLURM_JOB_NAME}

# Without this, UCX cannot register InfiniBand memory and MPI dies at startup
# with "Failed to create UCP worker".  Hard limit is already unlimited.
ulimit -l unlimited

module purge
module load cuda/12.8.0 openmpi/cuda-4.1.8

export LD_PRELOAD=/mnt/sw/fi/cephtweaks/lib/libcephtweaks.so
export CEPHTWEAKS_LAZYIO=1

ATHENAK=/mnt/home/lmurphy1/athenak
OUTDIR=/mnt/ceph/users/lmurphy1/relativistic_bhl/output/run_data/$RUN_NAME

mkdir -p "$OUTDIR"

srun --cpu-bind=cores \
    "$ATHENAK/build/src/athena" \
    -i "$ATHENAK/bhl_accretion/bhl_tst_norad.athinput" \
    -d "$OUTDIR"