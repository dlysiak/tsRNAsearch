#!/usr/bin/env bash
set -x

LOGFILE=tsRNAsearch/$(date +%y%m%d-%H%M)-GMT.log
BASE=/home/dlysiak/workspace/datasets/SRApublic/SRP006574                       
OUTS=/home/dlysiak/workspace/outputs/SRApublic/SRP006574                        
INPUT=$BASE/Samples/DCISvsIDC/                                                  
OUTPUT=$OUTS/tsrnasearch_output/2conditions/21_v4_DCISvsIDC                    
LAYOUT=$OUTS/ExpDesign/DCISvsIDC/21DCISvsIDClayout.csv   

nextflow run tsRNAsearch --species human --input_dir $INPUT --output_dir $OUTPUT --layout $LAYOUT 2>&1 | tee $LOGFILE 

