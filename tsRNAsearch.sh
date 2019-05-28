#!/bin/bash

# Usage: tsRNAsearch.sh -h
# Author: Paul Donovan
# Email: pauldonovan@rcsi.com
# 19-Oct-2018

asciiArt() { echo '

 _        _____ _   _   ___                          _     
| |      | ___ \ \ | | / _ \                        | |    
| |_ ___ | |_/ /  \| |/ /_\ \___  ___  __ _ _ __ ___| |__  
| __/ __||    /| . ` ||  _  / __|/ _ \/ _` | `__/ __| `_ \ 
| |_\__ \| |\ \| |\  || | | \__ \  __/ (_| | | | (__| | | |
 \__|___/\_| \_\_| \_/\_| |_/___/\___|\__,_|_|  \___|_| |_|
                                                          

	' 1>&1; }
usage() { echo "Usage (single-end): $0 -o OutputDirectory/ -s /path/to/SeqFile.fastq.gz
" 1>&2; }
info() { echo "
Options:

	-h	Print the usage and options information
	-g	Analyse data against 'human' or 'mouse'? {default: human}
	-s	Single-end file for analysis
	-o	Output directory for the results and log files
	-A	Plot all features? yes/no {default: yes}
	-t	Number of threads to use {default is to calculate the number of processors and use 75%}
	

	Input file format should be FASTQ (.fq/.fastq) or gzipped FASTQ (.gz)
	" 1>&2; }

if [ $# -eq 0 ]; then
    echo "No arguments provided"
    asciiArt
	usage
	info
	exit 1
fi

while getopts ":hg:t:s:o:A:" o; do
    case "${o}" in
		h)
			asciiArt
			usage
			info
			exit
			;;
		g)
			genome="$OPTARG"
			;;
		s)
			singleFile="$OPTARG"
			;;
		o)
			outDir="$OPTARG"
			;;
		t)
			threads="$OPTARG"
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
#if [ "$singleFile" ]; then
#    if [[ ! $singleFile = /* ]]; then
#        echo "Error: File paths must absolute. Please specify the full path for the FASTQ input file."
#        exit 1
#    fi
#fi
#########

echo "Started analysing "$singleFile" on $(date)" # Print pipeline start-time

### Are we analysing Human or Mouse? -g parameter
if [ "$genome" ]; then
    if [[ $genome == "human" ]]; then
		genomeDB="DBs/genome_index/human/"
		ncRNADB="DBs/genome_index/human-ncRNAs/"
		genomeGTF="DBs/Homo_sapiens.GRCh37.87.gtf"
		tRNAGTF="DBs/hg19-wholetRNA-CCA_cdhit.gtf"
		snomiRNAGTF="DBs/hg19-snomiRNA_cdhit.gtf"
		tRNA_introns="additional-files/tRNA-introns-for-removal_hg19.tsv"
		empty_tRNAs="additional-files/hg19_empty_tRNA.count"
		empty_snomiRNAs="additional-files/hg19_empty_snomiRNA.count"
		empty_mRNAs="additional-files/hg19_empty_mRNA-ncRNA.count"
	elif [[ $genome == "mouse" ]]; then
		genomeDB="DBs/genome_index/mouse/"
		ncRNADB="DBs/genome_index/mouse-ncRNAs/"
		genomeGTF="DBs/Mus_musculus.GRCm38.95.gtf"
		tRNAGTF="DBs/mm10-tRNAs_renamed_cdhit.gtf"
		snomiRNAGTF="DBs/mouse_snomiRNAs_relative_cdhit.gtf"
		tRNA_introns="additional-files/tRNA-introns-for-removal_mm10.tsv"
		empty_tRNAs="additional-files/mm10_empty_tRNA.count"
		empty_snomiRNAs="additional-files/mm10_empty_snomiRNA.count"
		empty_mRNAs="additional-files/mm10_empty_mRNA-ncRNA.count"
	fi
else # If genome was not specified, default to use human genome/files
	genome="human"
	genomeDB="DBs/genome_index/human/"
	ncRNADB="DBs/genome_index/human-ncRNAs/"
	genomeGTF="DBs/Homo_sapiens.GRCh37.87.gtf"
	tRNAGTF="DBs/hg19-wholetRNA-CCA_cdhit.gtf"
	snomiRNAGTF="DBs/hg19-snomiRNA_cdhit.gtf"
	tRNA_introns="additional-files/tRNA-introns-for-removal_hg19.tsv"
	empty_tRNAs="additional-files/hg19_empty_tRNA.count"
	empty_snomiRNAs="additional-files/hg19_empty_snomiRNA.count"
	empty_mRNAs="additional-files/hg19_empty_mRNA-ncRNA.count"
fi

### Define functions
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

function SAMcollapse () {
	string_padder "Collapsing SAM file..."
	### How many chunks to create:
	readNumber=$(grep -v ^@ $1 | awk '{print $1}' | uniq | wc -l)
	if (( $readNumber > 100000 )); then
		chunksRaw=$(( readNumber / 10000 )) # 10,000 lines per SAM chunk
		chunks=$( echo $chunksRaw | awk '{print int($1+0.5)}' )
		echo "Over 100,000 unique reads in SAM file. Splitting SAM into $chunks files..."
	elif (( readNumber>=10000 && readNumber<=100000 )); then
		chunksRaw=$(( readNumber / 5000 )) # 5000 lines per SAM chunk
		chunks=$( echo $chunksRaw | awk '{print int($1+0.5)}' )
		echo "Between 10,000 and 100,000 unique reads in SAM file. Splitting SAM into $chunks files..."
	elif (( readNumber>=1000 && readNumber<=10000 )); then
		chunks=10 #
		echo "Between 1,000 and 10,000 unique reads in SAM file. Splitting SAM into $chunks files..."
	else
		chunks=2
		echo "Less than 1,000 unique reads in SAM file. Splitting SAM into $chunks files..."
	fi
	### Define variables
	cores=$threads
	if (( $cores > $chunks )); then
		# make sure cores is not set higher than no. of files after split
		cores=$chunks
	fi
	echo "
		Threads: $cores
		# Split SAM files: $chunks"
	fileLen=$(< "$1" wc -l)
	division1=$((fileLen/chunks))
	division=$((division1 + 1))
	myFile="tempFile"
	mkdir -p $outDir/tempDir

	### Remove header
	grep ^@ $1 > $outDir/tempDir/myHeader.txt &
	grep -v ^@ $1 > $outDir/tempDir/mySAM.sam &
	wait
	### 
	fileToCollapse=$outDir/tempDir/mySAM.sam
	### Split file
	echo "Splitting SAM..."
	split -l $division $fileToCollapse $outDir/tempDir/splitFile_
	### Gather first and last read from every split file and add to separate file. Remove these reads from the split files.
	echo "Gathering the names of the first and last reads from every SAM chunk..."
	for i in $outDir/tempDir/splitFile_*; do
		base=$(basename $i)
		first=$(awk 'NR==1' $i | awk '{print $1}') 
		echo $first >> $outDir/tempDir/${myFile}_HeadsAndTails.txt
		last=$(awk 'END{print}' $i | awk '{print $1}') 
		echo $last >> $outDir/tempDir/${myFile}_HeadsAndTails.txt
	done
	echo "Gathering unique set of read names from first/last read names..."
	sort $outDir/tempDir/${myFile}_HeadsAndTails.txt | uniq > $outDir/tempDir/${myFile}_HeadsAndTails_uniq.txt #remove duplicates
	sed -i 's/$/\t/' $outDir/tempDir/${myFile}_HeadsAndTails_uniq.txt # Add tab to end of every line to match pattern exactly
	grep -f $outDir/tempDir/${myFile}_HeadsAndTails_uniq.txt $fileToCollapse > $outDir/tempDir/edit_heads-and-tails #grep all patterns from the heads/tails file
	echo "Extracting alignments for first/last reads from all files..."
	for i in $outDir/tempDir/splitFile_*; do
		base=$(basename $i)
		grep -v -f  $outDir/tempDir/${myFile}_HeadsAndTails_uniq.txt $i > $outDir/tempDir/edit_${base}
	done
	### Run SAMcollapse.py. This loop will only run $cores processes at once
	COUNTER=1
	chunksDiv=$((chunks/10))
	echo "Collapsing every chunk of SAM..."
	for i in $outDir/tempDir/edit_*; 
	do
		base=$(basename $i)
		python bin/SAMcollapse.py $i ${fileToCollapse}_${base} >> $outDir/tRNA-alignment/collapsed-reads.txt & 
		if (( $COUNTER % $chunksDiv == 0 )); then
			echo "Started job $COUNTER of $chunks"
		fi
		numjobs=($(jobs | wc -l))
		#echo Running job number ${COUNTER} of ${chunks}... 
		COUNTER=$[$COUNTER + 1]
		#counter2=$COUNTER
		while (( $numjobs == $cores )); do
			#if (( $COUNTER == $counter2)); then
			#	echo There are $numjobs jobs now. Waiting for jobs to finish...
			#fi
			#counter2=$[$counter2 + 1]
			numjobs=($(jobs | wc -l))
			sleep 5 #Enter next loop iteration
		done
	done
	wait
	readsCollapsedSpecies=$(awk '{split($0,a," "); sum += a[1]} END {print sum}' $outDir/tRNA-alignment/collapsed-reads.txt)
	readsCollapsedGroup=$(awk '{split($0,a," "); sum += a[2]} END {print sum}' $outDir/tRNA-alignment/collapsed-reads.txt)
	echo -e "SAM collapse results:\n\t$readsCollapsedSpecies reads collapsed at the tRNA species level (e.g. 2 gene copies of ProCCG)\n\t$readsCollapsedGroup reads collapsed at the tRNA group level (e.g. ProCCG and ProAAG)"

	### Concatenate results
	echo "Gathering reads that were mapped to similar tRNAs..."
	echo -e "tRNA.group\tread.start\tread.end.approx\tread.name" > $outDir/tRNA-alignment/tRNAs-almost-mapped.txt
	cat $outDir/tempDir/*tRNAs-almost-mapped* | sort >> $outDir/tRNA-alignment/tRNAs-almost-mapped.txt
	mkdir $outDir/tempDir/tRNAsAlmostMapped
	mv $outDir/tempDir/*tRNAs-almost-mapped* $outDir/tempDir/tRNAsAlmostMapped/
	echo "Concatenating SAM header with collapsed files..."
	cat $outDir/tempDir/myHeader.txt ${fileToCollapse}*_edit_* > $outDir/Collapsed.sam
	rm -rf $outDir/tempDir/ # Remove temp directory
	echo "Finished collapsing SAM file"
}

function bam_to_plots () {  ### Steps for plotting regions with high variation in coverage
	### Output coverage of all features we are interested in (e.g. tRNAs)
	samtools depth -aa $1/accepted_hits.bam > $1/accepted_hits.depth   # A lot faster than bedtools genomecov
	cp $1/accepted_hits.depth $1/accepted_hits_raw.depth
	### Normalise by reads per million (RPM)
	python bin/Depth-to-Depth_RPM.py $1/accepted_hits_raw.depth $mapped $1/accepted_hits.depth 
	### If we are working with tRNAs, collapse all tRNAs based on same isoacceptor
	if [[ $3 = "tsRNA" ]]; then
		### Remove introns from tRNA counts (as these will interfere with the read counts of collapsed tRNAs)
		Rscript bin/Remove-introns.R $1/accepted_hits.depth $tRNA_introns $1/accepted_hits_intron-removed.depth 
		### Flip the read coverage of tRNAs that are in the minus orientation
		Rscript bin/Coverage-flipper.R $1/accepted_hits_intron-removed.depth $tRNAGTF $1/accepted_hits_flipped.depth	
		### Collapse tRNAs from the same tRNA species
		python bin/Bedgraph_collapse-tRNAs.py $1/accepted_hits_flipped.depth $1/accepted_hits_collapsed.depth
		### Rename input depth file
		mv $1/accepted_hits.depth $1/accepted_hits_original.depth 
		### Copy the collapsed depth file and name it so that the remaining steps below do not have errors
		cp $1/accepted_hits_collapsed.depth $1/accepted_hits.depth	
	fi
	### Sort by feature name and nucleotide position
	sort -k1,1 -k2,2n $1/accepted_hits.depth > $1/accepted_hits_sorted.depth
	### If -A parameter was provided, plot everything
	if [[ $Plots == "yes" ]]; then # Plot everything
		### Plot the coverage of all features (arg 3 is mean coverage in RPM) and
		### Create plot and txt file describing relationship between 5' and 3' regions of feature
		if [[ $3 = "snomiRNA" ]]; then
			Rscript bin/Bedgraph_plotter.R $1/accepted_hits_sorted.depth $1/$2_$3_Coverage-plots.pdf 0 $snomiRNAGTF
			Rscript bin/Single-replicate-analysis.R $1/accepted_hits_sorted.depth $1/$2_$3_Results $snomiRNAGTF &
		elif [[ $3 == "tsRNA" ]]; then
			Rscript bin/Bedgraph_plotter.R $1/accepted_hits_sorted.depth $1/$2_$3_Coverage-plots.pdf 0
			Rscript bin/Single-replicate-analysis.R $1/accepted_hits_sorted.depth $1/$2_$3_Results &
		else
			Rscript bin/Bedgraph_plotter.R $1/accepted_hits_sorted.depth $1/$2_$3_Coverage-plots.pdf 1000 $genomeGTF
			Rscript bin/Single-replicate-analysis.R $1/accepted_hits_sorted.depth $1/$2_$3_Results &
		fi
		cp $1/$2_$3_Coverage-plots.pdf $outDir/Data_and_Plots/$2_$3_Coverage-plots.pdf
	fi
	### Output the mean, standard deviation and coefficient of variance of each ncRNA/gene
	python bin/Bedgraph-analyser.py $1/accepted_hits_sorted.depth $1/accepted_hits_sorted.tsv
	### Gather all ncRNAs/genes with a mean coverage greater than 0 (pointless step but the cutoff used to be higher than 0)
	awk '$2>0' $1/accepted_hits_sorted.tsv > $1/accepted_hits_sorted_mean-std.tsv
	### Sort the remaining ncRNAs/genes by coef. of variance
	sort -k4,4nr $1/accepted_hits_sorted_mean-std.tsv > $1/$2_$3_accepted_hits_sorted_mean-std_sorted.tsv
	### Move finalised data for further analysis
	cp $1/accepted_hits_sorted.depth $outDir/Data_and_Plots/$2_$3.depth &
	cp $1/$2_$3_accepted_hits_sorted_mean-std_sorted.tsv $outDir/Data_and_Plots/$2_$3_depth.inf
	echo -e "Feature\tMean\tStandard Deviation\tCoefficient of Variation\n" > $outDir/Data_and_Plots/Header.txt
	cat $outDir/Data_and_Plots/Header.txt $outDir/Data_and_Plots/$2_$3_depth.inf > $outDir/Data_and_Plots/$2_$3_depth.stats
	rm $outDir/Data_and_Plots/$2_$3_depth.stats $outDir/Data_and_Plots/Header.txt
	wait
}

# If -A parameter was not provided, default is to plot everything
if [ ! "$Plots" ]; then
    Plots="yes"
fi

# Estimate threads to use if a number has no been provided
if [ -z "$threads" ]; then 
	# Determine max number of threads available
	maxthreads=$(grep -c ^processor /proc/cpuinfo)
	# If the variable "threads" is not an integer, default to use a value of 1
	re='^[0-9]+$'
	if ! [[ $maxthreads =~ $re ]] ; then
		echo "Error: Variable 'maxthreads' is not an integer" >&2
		maxthreads=1
	fi
	threads=$(echo "$maxthreads * 0.75" | bc | awk '{print int($1+0.5)}') # Use 75% of max CPU number
fi

# The documentation for featureCounts says to use 4 threads max.
# This if statement ensures this.
# On revisiting this, I cannot find any such documentation. To be cautious, I'll go for a max of 8 threads
if (( $threads > 8 )); then 
	featureCountthreads=8
else
	featureCountthreads=$threads
fi

# Check if the output directory exists. If not, create it
string_padder "Creating directory structure"
mkdir -p $outDir
mkdir -p $outDir/trim_galore_output
mkdir -p $outDir/FastQC
mkdir -p $outDir/tRNA-alignment
mkdir -p $outDir/snomiRNA-alignment
mkdir -p $outDir/mRNA-ncRNA-alignment
mkdir -p $outDir/FCount-count-output
mkdir -p $outDir/FCount-to-RPM
mkdir -p $outDir/Data_and_Plots

singleFile_base=${singleFile##*/}    # Remove pathname
singleFile_basename="$( cut -d '.' -f 1 <<< "$singleFile_base" )" # Get filename before first occurence of .
if [[ $singleFile == *".gz"* ]]; then
	suffix="fq.gz"
	STARparam="--readFilesCommand zcat"
else
	suffix="fq"
	STARparam=""
fi
printf -v trimmedFile "%s_trimmed.%s" "$singleFile_basename" "$suffix"
printf -v myFile "%s.fq" "$singleFile_basename"
printf -v fastqcFile "%s_trimmed_fastqc.html" "$singleFile_basename"

# Run Trim_Galore
string_padder "Trimming reads using Trim Galore"
if [ ! -f $outDir/trim_galore_output/$trimmedFile ]; then
	bin/trim_galore --stringency 10 --length 15 -o $outDir/trim_galore_output/ $singleFile
	string_padder "Trimming complete. Moving on to FastQC analysis"
else
	string_padder "Found trimmed file. Skipping this step"
fi

# Run FastQC on newly trimmed file
if [ ! -f $outDir/FastQC/$fastqcFile ]; then
	fastqc -o $outDir/FastQC/ -f fastq $outDir/trim_galore_output/$trimmedFile
	string_padder "Finished running FastQC. Moving onto alignment to tRNA database"
else
	string_padder "Found FastQC file. Skipping this step."
fi

# Align trimmed reads to tRNA database using HISAT2/Tophat2

string_padder "Running tRNA/snomiRNA alignment step..."

### STAR ###
STAR --runThreadN $threads --genomeDir $ncRNADB --readFilesIn $outDir/trim_galore_output/$trimmedFile --outFileNamePrefix $outDir/tRNA-alignment/ --outSAMattributes AS nM HI NH --outFilterMultimapScoreRange 0 --outReadsUnmapped Fastx $STARparam
grep "Number of input reads" $outDir/tRNA-alignment/Log.final.out | awk -F '\t' '{print $2}' | tr -d '\040\011\012\015' > $outDir/Stats.log # the tr command removes all types of spaces
echo " reads; of these:" >> $outDir/Stats.log
SAMcollapse $outDir/tRNA-alignment/Aligned.out.sam #Collapse reads aligned to the same tRNA species 
mv $outDir/Collapsed.sam $outDir/tRNA-alignment/aligned_tRNAdb.sam # match hisat2 naming convention
mv $outDir/tRNA-alignment/Unmapped.out.mate1 $outDir/tRNA-alignment/unmapped.fastq
#### STAR ###

### HISAT2 ###
#hisat2 -p $threads -x $ncRNADB -U $outDir/trim_galore_output/$trimmedFile -S $outDir/tRNA-alignment/aligned_tRNAdb.sam --summary-file $outDir/tRNA-alignment/align_summary.txt --un $outDir/tRNA-alignment/unmapped.fastq
#grep "reads" $outDir/tRNA-alignment/align_summary.txt > $outDir/Stats.log
### HISAT2 ###

if [ -f $outDir/tRNA-alignment/aligned_tRNAdb.sam ]; then  #If STAR successfully mapped reads, convert to bam and index
	### Split the resulting SAM file into reads aligned to tRNAs and snomiRNAs
	grep ^@ $outDir/tRNA-alignment/aligned_tRNAdb.sam > $outDir/tRNA-alignment/SamHeader.sam &
	grep ENS $outDir/tRNA-alignment/aligned_tRNAdb.sam > $outDir/tRNA-alignment/snomiRNAs.sam &
	grep -v ENS $outDir/tRNA-alignment/aligned_tRNAdb.sam > $outDir/tRNA-alignment/tsRNAs_aligned.sam &
	wait
	cat $outDir/tRNA-alignment/SamHeader.sam $outDir/tRNA-alignment/snomiRNAs.sam > $outDir/tRNA-alignment/snomiRNAs_aligned.sam
	wait
	samtools view -bS $outDir/tRNA-alignment/tsRNAs_aligned.sam > $outDir/tRNA-alignment/accepted_hits_unsorted.bam
	samtools sort $outDir/tRNA-alignment/accepted_hits_unsorted.bam > $outDir/tRNA-alignment/accepted_hits.bam 
	samtools index $outDir/tRNA-alignment/accepted_hits.bam &
	mv $outDir/tRNA-alignment/unmapped.fastq $outDir/tRNA-alignment/$myFile
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
string_padder "Running mRNA/ncRNA alignment step..."

### HISAT2 ###
#hisat2 -p $threads -x $genomeDB $outDir/tRNA-alignment/$trimmedFile -S $outDir/mRNA-ncRNA-alignment/aligned.sam --summary-file $outDir/mRNA-ncRNA-alignment/align_summary.txt --un $outDir/mRNA-ncRNA-alignment/unmapped.fastq
### HISAT2 ###

### STAR ###
STAR --runThreadN $threads --genomeDir $genomeDB --readFilesIn $outDir/tRNA-alignment/$myFile --outFileNamePrefix $outDir/mRNA-ncRNA-alignment/ --outReadsUnmapped Fastx #$STARparam
mv $outDir/mRNA-ncRNA-alignment/Aligned.out.sam $outDir/mRNA-ncRNA-alignment/aligned.sam
mv $outDir/mRNA-ncRNA-alignment/Unmapped.out.mate1 $outDir/mRNA-ncRNA-alignment/unmapped.fastq
### STAR ###

if [ -f $outDir/mRNA-ncRNA-alignment/aligned.sam ]; then  #If hisat2 successfully mapped reads, convert the unmapped to FASTQ
	echo -e "\nConverting SAM to BAM and sorting..."
	samtools view -bS $outDir/mRNA-ncRNA-alignment/aligned.sam > $outDir/mRNA-ncRNA-alignment/accepted_hits_unsorted.bam
	rm $outDir/mRNA-ncRNA-alignment/aligned.sam &
	samtools sort $outDir/mRNA-ncRNA-alignment/accepted_hits_unsorted.bam > $outDir/mRNA-ncRNA-alignment/accepted_hits.bam
	samtools index $outDir/mRNA-ncRNA-alignment/accepted_hits.bam &
	mv $outDir/mRNA-ncRNA-alignment/unmapped.fastq $outDir/mRNA-ncRNA-alignment/UnmappedReads.fq &
else
	echo "
	mRNA/ncRNA alignment output not found. Reads likely did not map to mRNA/ncRNA reference. 
	"
	cp $outDir/tRNA-alignment/$myFile $outDir/mRNA-ncRNA-alignment/$trimmedFile
fi

# Produce read counts for the three alignment steps. If one of the alignment steps failed, use an empty htseq-count output file.
string_padder "Alignment steps complete. Moving on to read-counting using FCount-count"

# Count for alignment step 3
if [ ! -f $outDir/mRNA-ncRNA-alignment/accepted_hits.bam ]; then
	echo "
No alignment file found for mRNA/ncRNA alignment. Using blank count file instead
"
	cp $empty_mRNAs $outDir/FCount-count-output/mRNA-ncRNA-alignment.count &
else
	echo "
Counting mRNA/ncRNA alignment reads
"
	bin/featureCounts -T $featureCountthreads -a $genomeGTF -o $outDir/FCount-count-output/mRNA-ncRNA-alignment.fcount $outDir/mRNA-ncRNA-alignment/accepted_hits.bam
	grep -v featureCounts $outDir/FCount-count-output/mRNA-ncRNA-alignment.fcount | grep -v ^Geneid | awk -v OFS='\t' '{print $1, $7}' > $outDir/FCount-count-output/mRNA-ncRNA-alignment.count
fi
	
# Count for alignment step 2
if [ ! -f $outDir/snomiRNA-alignment/accepted_hits.bam ]; then
	echo "
No alignment file found for sno/miRNA alignment. Using blank count file instead
"
	cp $empty_snomiRNAs $outDir/FCount-count-output/snomiRNA-alignment.count &
else
	echo "
Counting sno/miRNA alignment reads
"
	bin/featureCounts -T $featureCountthreads -a $snomiRNAGTF -o $outDir/FCount-count-output/snomiRNA-alignment.fcount $outDir/snomiRNA-alignment/accepted_hits.bam
	grep -v featureCounts $outDir/FCount-count-output/snomiRNA-alignment.fcount | grep -v ^Geneid | awk -v OFS='\t' '{print $1, $7}' > $outDir/FCount-count-output/snomiRNA-alignment.count
fi

# Count for alignment step 1
if [ ! -f $outDir/tRNA-alignment/accepted_hits.bam ]; then
	echo "
No alignment file found for tRNA alignment. Using blank count file instead
"
	cp $empty_tRNAs $outDir/FCount-count-output/tRNA-alignment.count &
else
	echo "
Counting tRNA alignment reads
"
	bin/featureCounts -T $featureCountthreads -a $tRNAGTF -o $outDir/FCount-count-output/tRNA-alignment.fcount $outDir/tRNA-alignment/accepted_hits.bam
	grep -v featureCounts $outDir/FCount-count-output/tRNA-alignment.fcount | grep -v ^Geneid | awk -v OFS='\t' '{print $1, $7}' > $outDir/FCount-count-output/tRNA-alignment.count
fi

wait

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
bam_to_plots $outDir/tRNA-alignment $singleFile_basename tsRNA &
bam_to_plots $outDir/snomiRNA-alignment $singleFile_basename snomiRNA &
#bam_to_plots $outDir/mRNA-ncRNA-alignment $singleFile_basename mRNA &  

### Process multi-mapping tRNAs
python bin/Leftovers-to-Bedgraph.py $outDir/tRNA-alignment/tRNAs-almost-mapped.txt additional-files/tRNA-lengths_hg19.txt $outDir/tRNA-alignment/tRNAs-almost-mapped.depth
python bin/Depth-to-Depth_RPM.py $outDir/tRNA-alignment/tRNAs-almost-mapped.depth $mapped $outDir/tRNA-alignment/$singleFile_basename.tRNAs-almost-mapped_RPM.depth

### Get RPM-normalised FCount count data
string_padder "Get RPM-normalised read-counts"
python bin/FCount-to-RPM.py $outDir/FCount-count-output/$singleFile_basename.all-features.count $mapped $outDir/FCount-to-RPM/$singleFile_basename.all-features &
python bin/FCount-to-RPM.py $outDir/FCount-count-output/tRNA-alignment.count $mapped $outDir/FCount-to-RPM/tRNA-alignment & 
python bin/FCount-to-RPM.py $outDir/FCount-count-output/snomiRNA-alignment.count $mapped $outDir/FCount-to-RPM/snomiRNA-alignment &
python bin/FCount-to-RPM.py $outDir/FCount-count-output/mRNA-ncRNA-alignment.count $mapped $outDir/FCount-to-RPM/mRNA-ncRNA-alignment &
wait
sleep 5  # Make sure everything is finished running

### Move results to Data_and_Plots
cp $outDir/FCount-to-RPM/$singleFile_basename.all-features.rpm.count $outDir/Data_and_Plots/
if [[ $Plots == "yes" ]]; then
	### If extra plotting parameter (-A) was selected, copy these files 
	Rscript bin/Bedgraph_plotter.R $outDir/tRNA-alignment/$singleFile_basename.tRNAs-almost-mapped_RPM.depth $outDir/tRNA-alignment/Multi-mappers_tsRNAs_Coverage-plots.pdf 0
	cp $outDir/tRNA-alignment/Multi-mappers_tsRNAs_Coverage-plots.pdf $outDir/Data_and_Plots/
	cp $outDir/tRNA-alignment/*Results.* $outDir/Data_and_Plots/
	cp $outDir/snomiRNA-alignment/*Results.* $outDir/Data_and_Plots/
fi
echo "Finised analysing "$singleFile" on $(date)" # Print pipeline end-time
echo "_____________________________________________________________________________________________________________________

"


