#!/bin/bash
#SBATCH -N 1
#SBATCH -C gpu&hbm80g
#SBATCH -G 4
#SBATCH -q regular
#SBATCH -t 04:30:00
#SBATCH -A m4999
#SBATCH -J afd-sweep
#SBATCH -o results/sweep_%x_%j.out
bash scripts/sweep/sweep.sh "${PART:?set PART=A or B}"
