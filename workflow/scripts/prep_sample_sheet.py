import os
import glob
import argparse

# Create argument parse
parser = argparse.ArgumentParser(
    description='Prepare samples sheet for MLM Snakemake pipeline'
    )
parser.add_argument('--path', help="Path to directory with raw sequencing data",
                    type=str,
                    default="data"
                    )
parser.add_argument('--extension', help ='FastQ file extension',
                    choices=[".fastq.gz", ".fq.gz"],
                    default=".fastq.gz"
                    )
parser.add_argument("--out", help="Sample sheet file name",
                    default="config/sample_sheet.tsv"
                    )
parser.add_argument("--delimiter", 
                    help="Delimiter to split the file name to get the sample name (default is extension)",
                    type=str
                    )
parser.add_argument("--delimiter_number", 
                    help="The 'column' to pick for the sample name after delimiting (Default=0)",
                    type=int,
                    default=0)
parser.add_argument("--subdirectories", 
                    help="If set to true, will search subdirectories in given path for fastq files",
                    type=bool,
                    default=False,
                    choices=[True, False])
parser.add_argument("--absolute_path", 
                    help="if you want to set fastq paths as absolute paths rather than relative paths",
                    type=bool,
                    default=False,
                    choices=[True, False])
parser.add_argument("--r1_common", 
                    help="Naming convention to distinguish between R1/R2 in PE fastq files. Typically 'R1_001' if raw reads from illumina",
                    default="R1_001")
parser.add_argument("--r2_common", 
                    help="Naming convention to distinguish between R1/R2 in PE fastq files. Typically 'R2_001' if raw reads from illumina",
                    default="R2_001")
parser.add_argument("--dataset", 
                    help="Dataset Name",
                    default="MGX_DATA"
                    )
args = parser.parse_args()

# If no delimiter is given, make it the same as the extension
if args.delimiter is None:
    args.delimiter=args.extension

# Use glob to get all the file names in a given directory based on the provided extension
def get_file_names(path, extension, subdirectories):
    if path[-1] != "/":
        path = path + "/"
    if subdirectories:
        path = path + "*/"
    glob_path = "{}*{}".format(path, extension)
    files = glob.glob(glob_path)
    return files
    
# Helper function
def get_paths_absolute(file):
    return os.path.abspath(file)

# Modular operations done to both i and j files in main parser below
def file_name_operations(file, extension, rx_common, delimiter, delimiter_number):
    base = os.path.basename(file).split(args.extension)[0]
    paired_base = base.split(rx_common)[0]
    sample = base.split(delimiter)[delimiter_number]
    return base, paired_base, sample
    
# Helper function to write the main helper sheet to the given output file
def write_sample_sheet(sample_sheet, out_file):
    base_format="{}\t{}\t{}\t{}\n"
    with open(out_file, "w+") as sample_tsv:
        sample_tsv.write(base_format.format("sample", "dataset", "forward_read", "reverse_read"))
        # Sort dictionary by alphabetical order of keys (sample names)
        sorted_samples = list(sample_sheet.keys())
        sorted_samples.sort()
        for key in sorted_samples:
            column=sample_sheet[key]
            sample_tsv.write(base_format.format(column[0], column[1], column[2], column[3]))
           
            
# Get + glob files of interest
files = get_file_names(args.path, args.extension, args.subdirectories)

# Parse globbed files into dictionary that will be read out as a tab-delimited file 
sample_sheet = {}
for i in files:
    if args.r1_common in i:
        i_base, i_base_reads, i_sample = file_name_operations(
            i, args.extension, args.r1_common, args.delimiter, args.delimiter_number)
        print(i_base, i_base_reads, i_sample)
        for j in files:
            if args.r2_common in j:
                j_base, j_base_reads, j_sample = file_name_operations(
                    j, args.extension, args.r2_common, args.delimiter, args.delimiter_number)
                if i_base_reads == j_base_reads:
                    if args.absolute_path:
                        i=get_paths_absolute(i)
                        j=get_paths_absolute(j)
                    else:
                        pass
                    if i_base in sample_sheet:
                        print("{} in sample sheet already".format)
                    else:
                        sample_sheet[i_sample] = [i_sample, args.dataset, i, j]
write_sample_sheet(sample_sheet, args.out)
