#! /bin/bash

#SBATCH --job-name bhl
#SBATCH --account AST235
#SBATCH --partition batch
##SBATCH -q debug
#SBATCH --nodes 163
#SBATCH --time 4:00:00
##SBATCH --time 6:00:00
#SBATCH --output %x-%j.out
#SBATCH --mail-user xs2525@columbia.edu
#SBATCH --mail-type all
#######(8_7_* 6 hours -> 8000M)
#######(8_8 * 12 hrs -> 750)

# Parameters
#nodes_per_job=408
#ranks_per_job=3264
nodes_per_job=163
ranks_per_job=1304
gpus_per_node=8
runtime=03:40:00       # athena -t wall limit (< SBATCH --time 1:00:00): writes a final rst then exits cleanly
jobbasename=bhl_tst_1e9
problem=bhl_tst_1e9
data_dirc=/lustre/orion/ast235/scratch/xinsheng/bh_trans/output
names=()
names+=("bhl_tst_1e9")

arguments=()
arguments+=("")

# Derived Parameters
work_path=/lustre/orion/ast235/scratch/xinsheng/bh_trans
problem_path=$work_path/run
execute_path=$work_path/run/build/src
input_path=$work_path/input
data_path=$data_dirc
output_path=$work_path/output
executable=$execute_path/athena

# Read names for each job
cd $input_path
inputfile_all=(*)
num_input=${#inputfile_all[@]}

# Create directories if not exist
mkdir -p $data_path
mkdir -p $output_path
for ((n = 0; n < ${#names[@]}; n++)); do
 name=${names[$n]}
 mkdir -p $data_path/$name
done

# Set environment
cd $problem_path
#module restore
#module load PrgEnv-cray craype-accel-amd-gfx90a cray-python
#module load amd-mixed/5.3.0 cray-mpich/8.1.23 cce/15.0.1
#export MPICH_GPU_SUPPORT_ENABLED=1
#export MPICH_MPIIO_HINTS="*:romio_cb_write=disable"

module restore
module load cpe/24.07 PrgEnv-amd cray-mpich/8.1.30 craype-accel-amd-gfx90a amd/6.2.0 rocm/6.2.0
module load cmake cray-python emacs
module unload darshan-runtime
export LD_LIBRARY_PATH=${CRAY_LD_LIBRARY_PATH}:${LD_LIBRARY_PATH}
export MPICH_GPU_SUPPORT_ENABLED=1
export MPICH_MPIIO_HINTS="*:romio_cb_write=disable"

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
 time srun $mpi_options $executable $athenak_options &> $output_file && echo $name &
 sleep 10
done
wait
