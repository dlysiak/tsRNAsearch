#!/bin/bash

# Usage: ./tiRNA-pipeline.sh -h
# Author: Paul Donovan
# Email: pauldonovan@rcsi.com
# 19-Oct-2018

asciiArt() { echo "

                    88888888ba   888b      88         db                                                                    88           
  ,d                88      *8b  8888b     88        d88b                                                                   88           
  88                88      ,8P  88 *8b    88       d8**8b                                                                  88           
MM88MMM  ,adPPYba,  88aaaaaa8P*  88  *8b   88      d8*  *8b      ,adPPYba,   ,adPPYba,  ,adPPYYba,  8b,dPPYba,   ,adPPYba,  88,dPPYba,   
  88     I8[    **  88****88*    88   *8b  88     d8YaaaaY8b     I8[    **  a8P_____88  **     *Y8  88P*   *Y8  a8*     **  88P*    *8a  
  88      **Y8ba,   88    *8b    88    *8b 88    d8********8b     **Y8ba,   8PP*******  ,adPPPPP88  88          8b          88       88  
  88,    aa    ]8I  88     *8b   88     *8888   d8*        *8b   aa    ]8I  *8b,   ,aa  88,    ,88  88          *8a,   ,aa  88       88  
  *Y888  **YbbdP**  88      *8b  88      *888  d8*          *8b  **YbbdP**   **Ybbd8**  **8bbdP*Y8  88           **Ybbd8**  88       88                                                                                                                                          

	" 1>&1; }
usage() { echo "Usage (single-end): $0 -o OutputDirectory/ -s /path/to/SeqFile.fastq.gz
" 1>&2; }
info() { echo "
Options:

	-h	Print the usage and options information
	-s	Single-end file for analysis
	-o	Output directory for the results and log files
	-A	Plot all features? yes/no {default: yes}
	-p	Number of CPUs to use {default is to calculate the number of processors and use 75%}
	

	Input file format should be FASTQ (.fq/.fastq) or gzipped FASTQ (.gz)
	" 1>&2; }

if [ $# -eq 0 ]; then
    echo "No arguments provided"
    asciiArt
	usage
	info
	exit 1
fi

while getopts ":hp:s:o:A:" o; do
    case "${o}" in
		h)
			asciiArt
			usage
			info
			exit
			;;
		s)
			singleFile="$OPTARG"
			;;
		o)
			outDir="$OPTARG"
			;;
		p)
			CPUs="$OPTARG"
			;;
		A)
			Plots="$OPTARG"
			;;
		*)
            echo "Error in input parameters!"
			usage
			info
			exit 1
            ;;
    esac
done

######### Make sure that the absolute paths of files and directories have been specified
### If the pathname specified by $outDir does not begin with a slash, quit (we need full path name)
#if [[ ! $outDir = /* ]]; then
#    echo "Error: File paths must absolute. Please specify the full path for the output directory."
#    exit 1
#fi
### If the pathname specified by $expFile does not begin with a slash, quit (we need full path name)
if [ "$singleFile" ]; then
    if [[ ! $singleFile = /* ]]; then
        echo "Error: File paths must absolute. Please specify the full path for the FASTQ input file."
        exit 1
    fi
fi
### If the pathname specified by $expFile does not begin with a slash, quit (we need full path name)
if [ "$file1" ]; then
    if [[ ! $file1 = /* ]]; then
        echo "Error: File paths must absolute. Please specify the full path for the FASTQ input files."
        exit 1
    fi
fi
### If the pathname specified by $expFile does not begin with a slash, quit (we need full path name)
if [ "$file2" ]; then
    if [[ ! $file2 = /* ]]; then
        echo "Error: File paths must absolute. Please specify the full path for the FASTQ input files."
        exit 1
    fi
fi
#########

echo "Started analysing "$singleFile" on $(date)" # Print pipeline start-time

# Function to pad text with characters to make sentences stand out more
function string_padder () {
	string=$1
	count=${#string}
	v=$(printf "%-${count}s" "=")
	padding="${v// /=}"
	echo "

	$padding
	$string
	$padding

	"
}

function bam_to_plots () {  ### Steps for plotting regions with high variation in coverage
	
	### Output coverage of all features we are interested in (e.g. tRNAs)
	samtools depth -aa $1/accepted_hits.bam > $1/accepted_hits.depth   # A lot faster than bedtools genomecov
	cp $1/accepted_hits.depth $1/accepted_hits_raw.depth
	### Normalise by reads per million (RPM)
	python scripts/Depth-to-Depth_RPM.py $1/accepted_hits_raw.depth $mapped $1/accepted_hits.depth 
	### If we are working with tRNAs, collapse all tRNAs based on same isoacceptor
	if [[ $3 = "tiRNA" ]]; then
		### Remove introns from tRNA counts (as these will interfere with the read counts of collapsed tRNAs)
		Rscript scripts/Remove-introns.R $1/accepted_hits.depth additional-files/tRNA-introns-for-removal_hg19.tsv $1/accepted_hits_intron-removed.depth 
		### Flip the read coverage of tRNAs that are in the minus orientation
		Rscript scripts/Coverage-flipper.R $1/accepted_hits_intron-removed.depth DBs/hg19-wholetRNA-CCA_cdhit.gtf $1/accepted_hits_flipped.depth	
		### Collapse tRNAs from the same tRNA species
		python scripts/Bedgraph_collapse-tRNAs.py $1/accepted_hits_flipped.depth $1/accepted_hits_collapsed.depth
		### Rename input depth file
		mv $1/accepted_hits.depth $1/accepted_hits_original.depth 
		### Copy the collapsed depth file and name it so that the remaining steps below do not have errors
		cp $1/accepted_hits_collapsed.depth $1/accepted_hits.depth	
	fi
	### Sort by feature name and nucleotide position
	sort -k1,1 -k2,2n $1/accepted_hits.depth > $1/accepted_hits_sorted.depth
	### If -A parameter was provided, plot everything
	if [[ $Plots == "yes" ]]; then # Plot everything
		### Plot the coverage of all features (arg 3 is mean coverage in RPM)
		if [[ $3 = "snomiRNA" ]]; then
			Rscript scripts/Bedgraph_plotter-v5.R $1/accepted_hits_sorted.depth $1/$2_$3_Coverage-plots.pdf 1 DBs/hg19-snomiRNA_cdhit.gtf
		elif [[ $3 == "tiRNA" ]]; then
			Rscript scripts/Bedgraph_plotter-v5.R $1/accepted_hits_sorted.depth $1/$2_$3_Coverage-plots.pdf 0
		else
			Rscript scripts/Bedgraph_plotter-v5.R $1/accepted_hits_sorted.depth $1/$2_$3_Coverage-plots.pdf 1000 DBs/Homo_sapiens.GRCh37.87.gtf
		fi
		cp $1/$2_$3_Coverage-plots.pdf $outDir/Data_and_Plots/$2_$3_Coverage-plots.pdf
	fi
	### Create plot and txt file describing relationship between 5' and 3' regions of feature
	Rscript scripts/Five-vs-Threeprime-v3.R $1/accepted_hits_sorted.depth $1/$2_$3_Results &
	### Output the mean, standard deviation and coefficient of variance of each ncRNA/gene
	python scripts/Bedgraph-analyser.py $1/accepted_hits_sorted.depth $1/accepted_hits_sorted.tsv
	### Gather all ncRNAs/genes with at least a mean coverage of 10
	awk '$2>10' $1/accepted_hits_sorted.tsv > $1/accepted_hits_sorted_mean-std.tsv
	### Sort the remaining ncRNAs/genes by coef. of variance
	sort -k4,4nr $1/accepted_hits_sorted_mean-std.tsv > $1/$2_$3_accepted_hits_sorted_mean-std_sorted.tsv
	### Move finalised data for further analysis
	cp $1/accepted_hits_sorted.depth $outDir/Data_and_Plots/$2_$3.depth &
	cp $1/$2_$3_accepted_hits_sorted_mean-std_sorted.tsv $outDir/Data_and_Plots/$2_$3_depth.inf
	echo -e "Feature\tMean\tStandard Deviation\tCoefficient of Variation\n" > $outDir/Data_and_Plots/Header.txt
	cat $outDir/Data_and_Plots/Header.txt $outDir/Data_and_Plots/$2_$3_depth.inf > $outDir/Data_and_Plots/$2_$3_depth.stats
	rm $outDir/Data_and_Plots/$2_$3_depth.stats $outDir/Data_and_Plots/Header.txt
}

# If -A parameter was not provided, default is to plot everything
if [ ! "$Plots" ]; then
    Plots="yes"
fi

# Estimate CPUs to use if a number has no been provided
if [ -z "$CPUs" ]; then 
	# Determine max number of CPUs available
	maxCPUs=$(grep -c ^processor /proc/cpuinfo)
	# If the variable "CPUs" is not an integer, default to use a value of 1
	re='^[0-9]+$'
	if ! [[ $maxCPUs =~ $re ]] ; then
		echo "Error: Variable 'maxCPUs' is not an integer" >&2
		maxCPUs=1
	fi
	CPUs=$(echo "$maxCPUs * 0.75" | bc | awk '{print int($1+0.5)}') # Use 75% of max CPU number
fi

# The documentation for featureCounts says to use 4 threads max.
# This if statement ensures this.
if (( $CPUs > 4 )); then 
	featureCountCPUs=4
else
	featureCountCPUs=1
fi

# Determine if paired-end or single-end files were provided as input
if [ -z "$singleFile" ]; then # If the singleEnd variable is empty
	pairedEnd="True"
else
	pairedEnd="False"
fi

# Check if the output directory exists. If not, create it
string_padder "Creating directory structure"
mkdir -p $outDir
mkdir -p $outDir/checkpoints
mkdir -p $outDir/trim_galore_output
mkdir -p $outDir/FastQC
mkdir -p $outDir/tRNA-alignment
mkdir -p $outDir/snomiRNA-alignment
mkdir -p $outDir/mRNA-ncRNA-alignment
mkdir -p $outDir/FCount-count-output
mkdir -p $outDir/FCount-to-RPM
mkdir -p $outDir/Data_and_Plots

if [ ! -f $outDir/checkpoints/checkpoint-4.flag ]; then
	# Run Trim_Galore (paired-end or single-end)
	string_padder "Trimming reads using Trim Galore"
	if [[ $pairedEnd = "True" ]]; then
		
		#echo "
		#Input: paired-end read files
		#"
		
		string_padder "This version of the pipeline is under construction. Please treat your paired-end files as single-end for now."
		#exit 1

		#file1_base=${file1##*/}    # Remove pathname
		#basename1="$( cut -d '.' -f 1 <<< "$file1_base" )" # Get filename before first occurence of .
		#suffix1="$( cut -d '.' -f 2- <<< "$file1_base" )" # Get full file suffix/entension
		#file2_base=${file2##*/}    # Remove pathname
		#basename2="$( cut -d '.' -f 1 <<< "$file2_base" )" # Get filename before first occurence of .
		#suffix2="$( cut -d '.' -f 2- <<< "$file2_base" )" # Get full file suffix/entension
		#suffix=$suffix1

		# Run Trim_Galore on paired-end read files
		#trim_galore --stringency 10 --length 15 -o $outDir/trim_galore_output/ --paired $file1 $file2
		#printf -v trimmedFile1 "%s_val_1.%s" "$basename1" "$suffix1"
		#printf -v trimmedFile2 "%s_val_2.%s" "$basename2" "$suffix2"
		#string_padder "Trimming complete. Moving on to FastQC analysis"

		# Run FastQC on newly trimmed files
		#fastqc -o $outDir/FastQC/ -f fastq $outDir/trim_galore_output/$trimmedFile1 $outDir/trim_galore_output/$trimmedFile2
		#string_padder "Finished running FastQC. Moving onto alignment to tRNA database"

		# Align trimmed reads to tRNA database using HISAT2/Tophat2
		#if [[ $oldAligner = "yes" ]]; then
		#	tophat2 -p $CPUs -x 1 -o $outDir/tRNA-alignment/ DBs/bowtie2_index/hg19-wholetRNA-CCA_cdhit $outDir/trim_galore_output/$trimmedFile1 $outDir/trim_galore_output/$trimmedFile2
			# Tophat2 using HG38 genome below:
			#tophat2 -p $CPUs -x 1 -o $outDir/tRNA-alignment/ DBs/bowtie2_index/hg38-tRNAs_CCA $outDir/trim_galore_output/$trimmedFile1 $outDir/trim_galore_output/$trimmedFile2
		#	bedtools bamtofastq -i $outDir/tRNA-alignment/unmapped.bam -fq $outDir/tRNA-alignment/unmapped_1.fastq -fq2 $outDir/tRNA-alignment/unmapped_2.fastq
		#else
		#	echo $trimmedFile1
			#hisat2 -p $CPUs -x DBs/hisat2_index/hg19-wholetRNA-CCA_cdhit -1 $outDir/trim_galore_output/$trimmedFile1 -2 $outDir/trim_galore_output/$trimmedFile2 -S $outDir/tRNA-alignment/aligned_tRNAdb.sam
		#fi

	elif [[ $pairedEnd = "False" ]]; then

		echo "
		Input: single-end read file
		"
			
		singleFile_base=${singleFile##*/}    # Remove pathname
		singleFile_basename="$( cut -d '.' -f 1 <<< "$singleFile_base" )" # Get filename before first occurence of .
		if [[ $singleFile == *".gz"* ]]; then
			suffix="fq.gz"
		else
			suffix="fq"
		fi
		printf -v trimmedFile "%s_trimmed.%s" "$singleFile_basename" "$suffix"
		printf -v fastqcFile "%s_trimmed_fastqc.html" "$singleFile_basename"
		
		# Run Trim_Galore on single read file
		if [ ! -f $outDir/trim_galore_output/$trimmedFile ]; then
			trim_galore --stringency 10 --length 15 -o $outDir/trim_galore_output/ $singleFile
			string_padder "Trimming complete. Moving on to FastQC analysis"
		else
			string_padder "Found trimmed file. Skipping this step"
		fi
		
		# Run FastQC on newly trimmed file
		if [ ! -f $outDir/FastQC/$fastqcFile ]; then
			# Put fastqcFile definition here?
			fastqc -o $outDir/FastQC/ -f fastq $outDir/trim_galore_output/$trimmedFile
			string_padder "Finished running FastQC. Moving onto alignment to tRNA database"
		else
			string_padder "Found FastQC file. Skipping this step."
		fi

		# Align trimmed reads to tRNA database using HISAT2/Tophat2
		
		if [ ! -f $outDir/tRNA-alignment/align_summary.txt ]; then
			string_padder "Running tRNA/snomiRNA alignment step..."
			hisat2 -p $CPUs -x DBs/hisat2_index/hg19-combined_tiRNAs_snomiRNAs -U $outDir/trim_galore_output/$trimmedFile -S $outDir/tRNA-alignment/aligned_tRNAdb.sam --summary-file $outDir/tRNA-alignment/align_summary.txt --un $outDir/tRNA-alignment/unmapped.fastq
			grep "reads" $outDir/tRNA-alignment/align_summary.txt > $outDir/Stats.log	
			if [ -f $outDir/tRNA-alignment/aligned_tRNAdb.sam ]; then  #If hisat2 successfully mapped reads, convert to bam and index
				### Split the resulting SAM file into reads aligned to tRNAs and snomiRNAs
				grep ^@ $outDir/tRNA-alignment/aligned_tRNAdb.sam > $outDir/tRNA-alignment/SamHeader.sam &
				grep ENSG $outDir/tRNA-alignment/aligned_tRNAdb.sam > $outDir/tRNA-alignment/snomiRNAs.sam &
				grep -v ENSG $outDir/tRNA-alignment/aligned_tRNAdb.sam > $outDir/tRNA-alignment/tiRNAs_aligned.sam &
				wait
				cat $outDir/tRNA-alignment/SamHeader.sam $outDir/tRNA-alignment/snomiRNAs.sam > $outDir/tRNA-alignment/snomiRNAs_aligned.sam
				wait
				samtools view -bS $outDir/tRNA-alignment/tiRNAs_aligned.sam > $outDir/tRNA-alignment/accepted_hits_unsorted.bam
				samtools sort $outDir/tRNA-alignment/accepted_hits_unsorted.bam > $outDir/tRNA-alignment/accepted_hits.bam 
				samtools index $outDir/tRNA-alignment/accepted_hits.bam &
				cp $outDir/tRNA-alignment/unmapped.fastq $outDir/tRNA-alignment/$trimmedFile
				### Move snomiRNA BAM to directory
				samtools view -bS $outDir/tRNA-alignment/snomiRNAs.sam > $outDir/snomiRNA-alignment/accepted_hits_unsorted.bam
				samtools sort $outDir/snomiRNA-alignment/accepted_hits_unsorted.bam > $outDir/snomiRNA-alignment/accepted_hits.bam 
				samtools index $outDir/snomiRNA-alignment/accepted_hits.bam &
				rm $outDir/tRNA-alignment/SamHeader.sam $outDir/tRNA-alignment/snomiRNAs.sam $outDir/tRNA-alignment/aligned_tRNAdb.sam &	
			else
				echo "
				Alignment output not found. Reads likely did not map to tRNA/sno/miRNA reference. 
				Using trimmed reads from Trim_Galore output.
				"
				cp $outDir/trim_galore_output/$trimmedFile $outDir/tRNA-alignment/$trimmedFile
			fi
		else
			string_padder "Found tRNA/sno/miRNA alignment file. Skipping this step."
		fi

		if [ ! -f $outDir/mRNA-ncRNA-alignment/align_summary.txt ]; then # If this file was not generated, try and align the unmapped reads from the tRNA alignment	
			string_padder "Running mRNA/ncRNA alignment step..."
			hisat2 -p $CPUs -x DBs/hisat2_index/Homo_sapiens.GRCh37.dna.primary_assembly $outDir/tRNA-alignment/$trimmedFile -S $outDir/mRNA-ncRNA-alignment/aligned.sam --summary-file $outDir/mRNA-ncRNA-alignment/align_summary.txt --un $outDir/mRNA-ncRNA-alignment/unmapped.fastq
			if [ -f $outDir/mRNA-ncRNA-alignment/aligned.sam ]; then  #If hisat2 successfully mapped reads, convert the unmapped to FASTQ
				samtools view -bS $outDir/mRNA-ncRNA-alignment/aligned.sam > $outDir/mRNA-ncRNA-alignment/accepted_hits_unsorted.bam
				rm $outDir/mRNA-ncRNA-alignment/aligned.sam &
				samtools sort $outDir/mRNA-ncRNA-alignment/accepted_hits_unsorted.bam > $outDir/mRNA-ncRNA-alignment/accepted_hits.bam
				samtools index $outDir/mRNA-ncRNA-alignment/accepted_hits.bam &
				cp $outDir/mRNA-ncRNA-alignment/unmapped.fastq $outDir/mRNA-ncRNA-alignment/UnmappedReads.fq &
			else
				echo "
				mRNA/ncRNA alignment output not found. Reads likely did not map to mRNA/ncRNA reference. 
				"
				cp $outDir/tRNA-alignment/$trimmedFile $outDir/mRNA-ncRNA-alignment/$trimmedFile
				string_padder "$unmappedReadCount"
			fi
		else
			string_padder "Found mRNA/ncRNA alignment file. Skipping this step"
		fi
	fi
	touch $outDir/checkpoints/checkpoint-4.flag
fi

# Produce read counts for the three alignment steps. If one of the alignment steps failed, use an empty htseq-count output file.
string_padder "Alignment steps complete. Moving on to read-counting using FCount-count"

if [ ! -f $outDir/checkpoints/checkpoint-5.flag ]; then
	
	# Count for alignment step 3
	if [ ! -f $outDir/mRNA-ncRNA-alignment/accepted_hits.bam ]; then
		echo "
	No alignment file found for mRNA/ncRNA alignment. Using blank count file instead
	"
		cp additional-files/empty_mRNA-ncRNA.count $outDir/FCount-count-output/mRNA-ncRNA-alignment.count &
	else
		echo "
	Counting mRNA/ncRNA alignment reads
	"
		featureCounts -T $featureCountCPUs -a DBs/Homo_sapiens.GRCh37.87.gtf -o $outDir/FCount-count-output/mRNA-ncRNA-alignment.fcount $outDir/mRNA-ncRNA-alignment/accepted_hits.bam
		grep -v featureCounts $outDir/FCount-count-output/mRNA-ncRNA-alignment.fcount | grep -v ^Geneid | awk -v OFS='\t' '{print $1, $7}' > $outDir/FCount-count-output/mRNA-ncRNA-alignment.count
	fi
	
	# Count for alignment step 2
	if [ ! -f $outDir/snomiRNA-alignment/accepted_hits.bam ]; then
		echo "
	No alignment file found for sno/miRNA alignment. Using blank count file instead
	"
		cp additional-files/empty_snomiRNA.count $outDir/FCount-count-output/snomiRNA-alignment.count &
	else
		echo "
	Counting sno/miRNA alignment reads
	"
		featureCounts -T $featureCountCPUs -a DBs/hg19-snomiRNA_cdhit.gtf -o $outDir/FCount-count-output/snomiRNA-alignment.fcount $outDir/snomiRNA-alignment/accepted_hits.bam
		grep -v featureCounts $outDir/FCount-count-output/snomiRNA-alignment.fcount | grep -v ^Geneid | awk -v OFS='\t' '{print $1, $7}' > $outDir/FCount-count-output/snomiRNA-alignment.count
	fi
	
	# Count for alignment step 1
	if [ ! -f $outDir/tRNA-alignment/accepted_hits.bam ]; then
		echo "
	No alignment file found for tRNA alignment. Using blank count file instead
	"
		cp additional-files/empty_tRNA.count $outDir/FCount-count-output/tRNA-alignment.count &
	else
		echo "
	Counting tRNA alignment reads
	"
		featureCounts -T $featureCountCPUs -a DBs/hg19-wholetRNA-CCA_cdhit.gtf -o $outDir/FCount-count-output/tRNA-alignment.fcount $outDir/tRNA-alignment/accepted_hits.bam
		grep -v featureCounts $outDir/FCount-count-output/tRNA-alignment.fcount | grep -v ^Geneid | awk -v OFS='\t' '{print $1, $7}' > $outDir/FCount-count-output/tRNA-alignment.count	
	fi

	touch $outDir/checkpoints/checkpoint-5.flag
	wait
else
	echo "
	Checkpoint 5 exists, skipping this step
	"
fi

### Get total reads mapped
string_padder "Get total number of reads mapped"
cat $outDir/FCount-count-output/*.count | grep -v ^__ | sort -k1,1 > $outDir/FCount-count-output/$singleFile_basename.all-features.count 
sed -i '1s/^/Features\t'"$singleFile_basename"'\n/' $outDir/FCount-count-output/$singleFile_basename.all-features.count # Add column headers
mapped=$(awk '{sum+=$2} END{print sum;}' $outDir/FCount-count-output/$singleFile_basename.all-features.count)
echo "Reads mapped: $mapped" >> $outDir/Stats.log
echo "Reads mapped: $mapped"
wait

### Plot everything
string_padder "Generate depth files and plot features"
bam_to_plots $outDir/tRNA-alignment $singleFile_basename tiRNA &
bam_to_plots $outDir/snomiRNA-alignment $singleFile_basename snomiRNA &
#bam_to_plots $outDir/mRNA-ncRNA-alignment $singleFile_basename mRNA &  

### Get RPM-normalised FCount count data
string_padder "Get RPM-normalised read-counts"
python scripts/FCount-to-RPM.py $outDir/FCount-count-output/$singleFile_basename.all-features.count $mapped $outDir/FCount-to-RPM/$singleFile_basename.all-features &
python scripts/FCount-to-RPM.py $outDir/FCount-count-output/tRNA-alignment.count $mapped $outDir/FCount-to-RPM/tRNA-alignment & 
python scripts/FCount-to-RPM.py $outDir/FCount-count-output/snomiRNA-alignment.count $mapped $outDir/FCount-to-RPM/snomiRNA-alignment &
python scripts/FCount-to-RPM.py $outDir/FCount-count-output/mRNA-ncRNA-alignment.count $mapped $outDir/FCount-to-RPM/mRNA-ncRNA-alignment &
wait

sleep 5  # Just making sure everything is finished running

### Move results to Data_and_Plots
cp $outDir/FCount-to-RPM/$singleFile_basename.all-features.rpm.count $outDir/Data_and_Plots/
cp $outDir/tRNA-alignment/*Results.* $outDir/Data_and_Plots/
cp $outDir/snomiRNA-alignment/*Results.* $outDir/Data_and_Plots/

echo "Finised analysing "$singleFile" on $(date)" # Print pipeline end-time
echo "_____________________________________________________________________________________________________________________

"


