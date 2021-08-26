import glob
import pandas as pd
from snakemake.utils import validate


### Run FastP to trim/filter reads ###

rule fastp_pe:
    input:
        r1 = get_r1,
        r2 = get_r2
    output:
        r1Filtered = "../results/{dataset}/filtered/{sample}.filtered.R1.fastq.gz",
        r2Filtered = "../results/{dataset}/filtered/{sample}.filtered.R2.fastq.gz",
        json = "../results/{dataset}/filtered/{sample}_fastp.json",
        html = "../results/{dataset}/filtered/{sample}_fastp.html"
    conda:
        "../envs/seq_processing.yml"
    threads: 16
    shell: 
        "fastp -i {input.r1} -I {input.r2} --out1 {output.r1Filtered} --out2 {output.r2Filtered} --detect_adapter_for_pe --thread {threads} --length_required 50 -j {output.json} -h {output.html} -V"


rule fastqc:
    input: 
        "../results/{dataset}/filtered/{sample}.filtered.R1.fastq.gz",
        "../results/{dataset}/filtered/{sample}.filtered.R2.fastq.gz"
    output:
        "../results/{dataset}/filtered/fastqc/{sample}.filtered.R1_fastqc.html",
        "../results/{dataset}/filtered/fastqc/{sample}.filtered.R2_fastqc.html"
    params:
        outDir = "../results/{dataset}/filtered/fastqc"
    threads: 12
    shell:
        "module load fastqc/0.11.5 ; fastqc -t {threads} {input} --outdir {params.outDir}"


### Remove contaminant reads aligning to human reference genome ###

rule bwa_map:
    input:
        r1Filtered = "../results/{dataset}/filtered/{sample}.filtered.R1.fastq.gz",
        r2Filtered = "../results/{dataset}/filtered/{sample}.filtered.R2.fastq.gz"
    output:
        cleanFastQ1 = "../results/{dataset}/bwa/{sample}.clean.R1.fastq",
        cleanFastQ2 = "../results/{dataset}/bwa/{sample}.clean.R2.fastq"
    params:
        genome = "/projects/b1042/HartmannLab/jack/SCRIPT/expPipeline_v1/data/genome/hg38.fa.gz",
        sam = "../results/{dataset}/bwa/{sample}.mapped.sam",
        bam = "../results/{dataset}/bwa/{sample}.mapped.bam",
        sortedBam = "../results/{dataset}/bwa/{sample}.mapped.sorted.bam",
        unmappedBam = "../results/{dataset}/bwa/{sample}.unmapped.bam"
    threads: 20
    shell:
        """
        module purge all
        module load bwa/0.7.17
        module load samtools/1.10.1
        module load bedtools/2.29.2
        bwa mem -t {threads} {params.genome} {input.r1Filtered} {input.r2Filtered} > {params.sam}
        samtools view -Subh -o {params.bam} {params.sam}
        samtools sort -o {params.sortedBam} {params.bam}

        samtools view -b -f 12 -F 256 -o {params.unmappedBam} {params.sortedBam}
        bedtools bamtofastq -i {params.unmappedBam} -fq {output.cleanFastQ1} -fq2 {output.cleanFastQ2}
        """


### Setup Metaphlan. Run Metaphlan on samples to make abundance tables ###

def metaphlan_merge_inputs(wildcards):
    files = expand("../results/{dataset}/abundance/metaphlan/{sample}.metaphlan_profile.txt",
        zip, sample=samples["sample"], dataset=samples["dataset"])
    return files


rule metaphlan_setup:
    output:
        metaphlan_db = directory("../resources/metaphlan_db")
    conda: 
        "../envs/metaphlan.yml"
    params:
        metaphlan_idx = config["metaphlan_idx"] # Index for metaphlan
    threads: 10
    shell:
        """
        metaphlan --install --index {params.metaphlan_idx} --bowtie2db {output.metaphlan_db} --nproc {threads}
        """


rule metaphlan:
    input:
        metaphlan_db = rules.metaphlan_setup.output.metaphlan_db,
        cleanFastQ1 = "../results/{dataset}/bwa/{sample}.clean.R1.fastq",
        cleanFastQ2 = "../results/{dataset}/bwa/{sample}.clean.R2.fastq"
    output:
        profile = "../results/{dataset}/abundance/metaphlan/{sample}.metaphlan_profile.txt",
        bowtie_out = "../results/{dataset}/abundance/metaphlan/{sample}.bowtie2.bz2"
    conda: 
        "../envs/metaphlan.yml"
    params:
        metaphlan_idx = config["metaphlan_idx"] # Index for metaphlan
    threads: 20
    shell:
        """
        metaphlan {input.cleanFastQ1},{input.cleanFastQ2} \
        --bowtie2out {output.bowtie_out} \
        --index {params.metaphlan_idx} \
        --bowtie2db {input.metaphlan_db} \
        --nproc {threads} \
        --input_type fastq \
        --unknown_estimation \
        -o {output.profile}
        """


rule metaphlan_merge:
    input:
        metaphlan_merge_inputs
    output:
        "../results/allDatasets/metaphlan/merged_abundance_table.allDatasets.txt"
    conda:
        "../envs/metaphlan.yml"
    shell:
        """
        merge_metaphlan_tables.py {input} > {output}
        """


rule metaphlan_species_abundance:
    input:
        "../results/allDatasets/metaphlan/merged_abundance_table.allDatasets.txt"
    output:
        "../results/allDatasets/metaphlan/merged_abundance_table.species.allDatasets.txt"
    conda:
        "../envs/metaphlan.yml"
    shell:
        """
        grep -E "s__|clade|UNKNOWN" {input} | sed 's/^.*s__//g' \
        | cut -f1,3- | sed -e 's/clade_name/sample/g' > {output}
        """


rule metaphlan_genus_abundance:
    input:
        "../results/allDatasets/metaphlan/merged_abundance_table.allDatasets.txt"
    output:
        "../results/allDatasets/metaphlan/merged_abundance_table.genus.allDatasets.txt"
    conda:
        "../envs/metaphlan.yml"
    shell:
        """
        grep -E "g__|clade|UNKNOWN" {input} | sed 's/^.*g__//g' \
        | grep -v s__ |cut -f1,3- | sed -e 's/clade_name/sample/g' > {output}
        """


rule hclust:
    input:
        "../results/allDatasets/metaphlan/merged_abundance_table.species.allDatasets.txt"
    output:
        "../results/allDatasets/metaphlan/abundance_heatmap_species.allDatasets.png"
    conda:
        "../envs/hclust.yml"
    shell:
        """
        hclust2.py -i {input} -o {output} --f_dist_f braycurtis --s_dist_f braycurtis --cell_aspect_ratio 0.5 -l --flabel_size 10 --slabel_size 10 --max_flabel_len 100 --max_slabel_len 100 --minv 0.1 --dpi 300
        """


### Co-assembly with megahit ###

rule concat_reads:
    input:
        cleanFastQ1 = expand("../results/{dataset}/bwa/{sample}.clean.R1.fastq", zip, sample=samples["sample"], dataset=samples["dataset"]),
        cleanFastQ2 = expand("../results/{dataset}/bwa/{sample}.clean.R2.fastq", zip, sample=samples["sample"], dataset=samples["dataset"])
    output:
        concatR1 = "../results/allDatasets/coassembly/concat_reads/concat_reads.clean.R1.fastq",
        concatR2 = "../results/allDatasets/coassembly/concat_reads/concat_reads.clean.R2.fastq"
    shell:
        """
        cat {input.cleanFastQ1} > {output.concatR1}
        cat {input.cleanFastQ2} > {output.concatR2}
        """

rule megahit_coassembly:
    input:
        concatR1 = "../results/allDatasets/coassembly/concat_reads/concat_reads.clean.R1.fastq",
        concatR2 = "../results/allDatasets/coassembly/concat_reads/concat_reads.clean.R2.fastq"
    output:
        scaffolds = "../results/allDatasets/coassembly/megahit_result/final.contigs.fa"
    params:
        outdir = "../results/allDatasets/coassembly/megahit_result/tmp"
    threads: 100
    shell:
        """
        module load megahit/1.0.6.1
        megahit -t {threads} -m 520e9 -1 {input.concatR1} -2 {input.concatR2} -o {params.outdir}
        mv {params.outdir} ../results/allDatasets/coassembly/
        rmdir ../results/allDatasets/coassembly/megahit_result
        mv ../results/allDatasets/coassembly/tmp ../results/allDatasets/coassembly/megahit_result
        """

rule quast_co:
    input:
        "../results/allDatasets/coassembly/megahit_result/final.contigs.fa"
    output:
        direc=directory("../results/allDatasets/coassembly/quast"),
        report="../results/allDatasets/coassembly/quast/report.html"
    threads: 1
    conda:
        "../envs/genome_qc.yml"
    shell:
        "quast.py -o {output.direc} --threads {threads} {input}"


rule megahit_monoassemble:
    input:
        cleanR1 = "../results/{dataset}/bwa/{sample}.clean.R1.fastq",
        cleanR2 = "../results/{dataset}/bwa/{sample}.clean.R2.fastq"
    output:
        scaffolds = "../results/{dataset}/assembly/{sample}/final.contigs.fa"
    params:
        outdir_base = "../results/{dataset}/assembly",
        outdir_final = "../results/{dataset}/assembly/{sample}",
        outdir_tmp = "../results/{dataset}/assembly/{sample}/{sample}_tmp"
    threads: 20
    shell:
        """
        module load megahit/1.0.6.1
        megahit -t {threads} -m 0.9 -1 {input.cleanR1} -2 {input.cleanR1} -o {params.outdir_tmp}
        
        mv {params.outdir_tmp} {params.outdir_base}
        rmdir {params.outdir_final}
        mv {params.outdir_final}_tmp {params.outdir_final}
        """

rule quast_mono:
    input:
        scaffolds = "../results/{dataset}/assembly/{sample}/final.contigs.fa"
    output:
        direc=directory("../results/{dataset}/assembly/quast/{sample}_quast"),
        report="../results/{dataset}/assembly/quast/{sample}_quast/report.html"
    threads: 1
    conda:
        "../envs/genome_qc.yml"
    shell:
        "quast.py -o {output.direc} --threads {threads} -L {input}"
