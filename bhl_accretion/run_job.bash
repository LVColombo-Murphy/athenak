#!/bin/bash
#SBATCH --job-name=bhl_relativistic
#SBATCH --output=/mnt/ceph/users/lmurphy1/relativistic_bhl/output/run_log/%x-%j.out
#SBATCH --error=/mnt/ceph/users/lmurphy1/relativistic_bhl/output/run_log/%x-%j.err
#SBATCH -p gpu
#SBATCH -C a100-80gb             # binary is built for sm_80 (Kokkos_ARCH_AMPERE80)
#SBATCH --nodes=1                # keep all ranks on one node (a100 nodes have 4 GPUs)
#SBATCH --ntasks-per-node=4      # 1 MPI rank == 1 GPU. Max useful value here is 8
#SBATCH --gpus-per-task=1
#SBATCH --cpus-per-task=16       # CUDA build has no host threading; CPUs are for MPI + I/O
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --propagate=NONE         # do NOT inherit the login shell's 8MB memlock limit
#SBATCH --mail-user l.colombo-murphy@columbia.edu
#SBATCH --mail-type all

# Without this, UCX cannot register InfiniBand memory and MPI dies at startup
# with "Failed to create UCP worker".  Hard limit is already unlimited.
ulimit -l unlimited


# Parameters
nodes_per_job=1
ranks_per_job=4
gpus_per_node=4
runtime=03:40:00       # athena -t wall limit (< SBATCH --time 1:00:00): writes a final rst then exits cleanly
jobbasename=bhl_v0.9_b0.1 # bhl_tst_1e9
problem=bhl_v0.9_b0.1     
data_dirc=/mnt/ceph/users/lmurphy1/relativistic_bhl/output   # was previously /lustre/orion/ast235/scratch/xinsheng/bh_trans/output
names=()
names+=("bhl_tst_norad")  

arguments=()
arguments+=("")

# Derived Parameters
work_path=/mnt/home/lmurphy1/athenak        # /lustre/orion/ast235/scratch/xinsheng/bh_trans
problem_path=$work_path                     # /run
execute_path=$work_path/build/src           # /run/build/src
input_path=$work_path/bhl_accretion
data_path=$data_dirc/run_data
output_path=$data_dirc/run_log              # $work_path/output
executable=$execute_path/athena

# Read names for each job
cd $input_path
inputfile_all=(*)
num_input=${#inputfile_all[@]}

# Create directories if they do not exist
mkdir -p $data_path
mkdir -p $output_path
for ((n = 0; n < ${#names[@]}; n++)); do
 name=${names[$n]}
 mkdir -p $data_path/$name
done

# Set environment
cd $problem_path

module purge
module load modules/2.1-20230203 slurm cuda/11.8.0 openmpi/cuda-4.0.7

export LD_PRELOAD=/mnt/sw/fi/cephtweaks/lib/libcephtweaks.so
export CEPHTWEAKS_LAZYIO=1

# Calculate parallel values
num_jobs=${#names[@]}
num_nodes=$((num_jobs * nodes_per_job))
if [ $num_nodes -gt $SLURM_JOB_NUM_NODES ]; then
 echo "Insufficient nodes requested."
 exit
fi
gpus_per_job=$((nodes_per_job * gpus_per_node))
if [ $ranks_per_job -gt $gpus_per_job ]; then
 echo "Insufficient GPUs requested."
 exit
fi

# Check for restart files (single_file_per_rank=true -> rst/rank_00000000/)
restart_lines=()
for ((n = 0; n < $num_jobs; n++)); do
 name=${names[$n]}
 rst_dir=$data_path/$name/rst/rank_00000000
 if compgen -G "$rst_dir/${name}.*.rst" > /dev/null; then
  restart_file=$(ls -t $rst_dir/${name}.*.rst | head -n1)   # newest checkpoint
  # also pass -i so the athinput is re-read on restart (AthenaK loads params from
  # the .rst first, then adds/overrides from -i): needed for params absent from
  # older checkpoints (e.g. new floor flags), which otherwise fail ModifyFromCmdline.
  restart_line="-r $restart_file -i $input_path/${name}.athinput"
  printf "\nrestarting $name from $restart_file\n\n"
 else
  restart_line="-i $input_path/${name}.athinput"
  printf "\nstarting $name from beginning\n\n"
 fi
 restart_lines+=("$restart_line")
done

# Run code
for ((n = 0; n < $num_jobs; n++)); do
 name=${names[$n]}
 mpi_options="--nodes $nodes_per_job --ntasks $ranks_per_job --cpus-per-task 1 --gpus-per-node $gpus_per_node --gpu-bind=closest"
 athenak_options="-d $data_path/$name -t $runtime ${restart_lines[$n]} ${arguments[$n]}"
 output_file=$output_path/$name.out
 time srun srun --cpus-per-task="$SLURM_CPUS_PER_TASK" \
     --cpu-bind=cores \
     --gpu-bind=single:2 \
     bash -c "unset CUDA_VISIBLE_DEVICES; \
     $executable -i $input_path/$name.athinput"
 sleep 10
done
wait
