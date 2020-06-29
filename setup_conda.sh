#!/bin/bash

usage() { echo "Usage: $0 -s human/mouse/rat/all -p threads
" 1>&2; }

threads=1 # Default CPU number unless overwritten by parameters provided

while getopts ":hs:p:" o; do
    case "${o}" in
		h)
			usage
			exit
			;;
		s)
			s_option="$OPTARG"
			if [ $s_option = "human" ]; then
				species="human"
			elif [ $s_option = "mouse" ]; then
				species="mouse"
			elif [ $s_option = "rat" ]; then
				species="rat"
			elif [ $s_option = "all" ]; then
				species="all"
			else
				usage
				echo "Error: the acceptable arguments for the -s parameter are 'human', 'mouse', 'rat', 'all'"
				exit
			fi
			;;
		p)
			threads="$OPTARG"
			;;
		*)
            echo "Error in input parameters!"
			usage
			exit 1
            ;;
    esac
done

### If no command line arguments provided, quit
if [ -z "$*" ] ; then
	usage
	echo "Error: no command line parameters provided!"
	exit 1
fi

### Define functions
function human_setup () {
	mkdir -p DBs/species_index/human-ncRNAs
	STAR --runThreadN $threads --runMode genomeGenerate --genomeDir DBs/species_index/human-ncRNAs/ --genomeFastaFiles DBs/human_tRNAs-and-ncRNAs_relative_cdhit.fa --genomeSAindexNbases 8
}
function mouse_setup () {
	mkdir -p DBs/species_index/mouse-ncRNAs
	STAR --runThreadN $threads --runMode genomeGenerate --genomeDir DBs/species_index/mouse-ncRNAs/ --genomeFastaFiles DBs/mouse_tRNAs-and-ncRNAs_relative_cdhit.fa
}
function rat_setup () {
	mkdir -p DBs/species_index/rat-ncRNAs
	STAR --runThreadN $threads --runMode genomeGenerate --genomeDir DBs/species_index/rat-ncRNAs/ --genomeFastaFiles DBs/rat_tRNAs-and-ncRNAs_relative_cdhit.fa
}

### Set up conda environment
# Check if conda installed:
if [[ $(conda info | wc -l) -ge 1 ]];
then
	echo "Conda is installed"
else
	echo "Conda is not installed. Please install conda (Miniconda2 Linux 64 bit Python2.7) using the following guide: https://docs.conda.io/en/latest/miniconda.html#linux-installer"
	exit 1
fi

### Downgrade conda (problems with package conflicts using 4.8)
conda install conda=4.6.14
### Create conda environment and activate it
conda create -y --name tsrnasearch_env python=2.7 # Create new environment with python 2.7
#source activate tsrnasearch_env # Activate new environment
source ~/miniconda2/etc/profile.d/conda.sh
conda activate tsrnasearch_env

### install all required tools and packages
conda install -y -c bioconda star=2.7
conda install -y -c bioconda trim-galore=0.6.5
conda install -y numpy
conda install -y -c r r=3.6.1 # Install R
conda install -y -c r r-essentials=3.5
conda install -y -c conda-forge r-metap=1
conda install -y -c bioconda bioconductor-deseq2=1.28
conda install -y -c conda-forge r-ggrepel=0.8.2
conda install -y -c conda-forge r-gplots=3
conda install -y -c conda-forge r-venndiagram=1.6
conda install -y -c bioconda bioconductor-genomeinfodb
conda install -y -c bioconda bioconductor-enhancedvolcano=1.6
conda install -y -c bioconda samtools=1.7

### Download species data
mkdir -p DBs/species_index
if [ $species = "human" ]; then
	echo "Setting up human database..."
	human_setup &
elif [ $species = "mouse" ]; then
	echo "Setting up mouse database..."
	mouse_setup &
elif [ $species = "rat" ]; then
	echo "Setting up rat database..."
	rat_setup &
elif [ $species = "all" ]; then
	echo "Setting up all available databases..."
	human_setup &
	mouse_setup &
	rat_setup &
elif [ -z $species ]; then
	### The species variable is unset
	echo "Please use the -s option with 'human', 'mouse', 'rat', or 'all' depending on the type of analyses you intend to run"
	exit 1
fi

# Setup for tsRNAsearch
echo "

Beginning tsRNAsearch setup...

"

source conda deactivate

echo "Run 'source activate '"
