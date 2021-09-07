#! /bin/bash
#SBATCH -A p31288
#SBATCH --job-name="scheduler"
#SBATCH -t 10:00:00
#SBATCH -n 10
#SBATCH -p normal
#SBATCH --mem-per-cpu=3gb
#SBATCH --mail-type=ALL
#SBATCH --mail-user=jacksumner2026@u.northwestern.edu
module load anaconda3
source activate snakemake
snakemake --version
# Must be in microbiome-snakemake/workflow/ directory to execute
cd $SLURM_SUBMIT_DIR

#--max-jobs-per-second 5 --max-status-checks-per-second 5 
mkdir -p logs_slurm
snakemake --verbose --use-conda --cluster-config cluster.yaml --max-jobs-per-second 5 --max-status-checks-per-second 5 -j 10 --cluster "sbatch -A {cluster.allocation} -p {cluster.partition} -t {cluster.time} --mem={cluster.mem} -N {cluster.nodes} -n {cluster.cpus} -o {cluster.output} -e {cluster.error} --mail-type={cluster.email_type} --mail-user={cluster.email} --job-name={cluster.jobname}"
