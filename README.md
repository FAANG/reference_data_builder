# Reference data builder

This is a Hive/LSF pipeline to build reference files required for genomic analysis from fasta and gtf files. It exists because we expect to deal with many types of genomic and epigenomic data across multiple species. We need to ensure that a standard set of reference files are available in a consistent manner across all species.

The data is organised in a directory structure like this

* root output directory
    * _species name_
      * _assembly name_
        * annotation
          * _annotation name_
            * indexes
              * _program name_
        * genome_fasta
        * genome_index
        * indexes
          * _program name_

For assemblies, the pipeline requires a fasta file. The pipeline provides
 * a gzipped copy of the fasta file
 * a fai file (for use with [samtools faidx](http://www.htslib.org/doc/samtools.html))
 * a dict file for the fasta (from [picard](http://broadinstitute.github.io/picard/command-line-overview.html#CreateSequenceDictionary))
 * a list of chromosomes and their sizes (for use with various tools, e.g. bedToBigBed)
 * indexes for bwa, bowtie, bowtie2 and bismark
 * TODO mappability files and stats
 
For gene annotations, the pipeline requires a GTF file. Each annotation must be based on an assembly. The pipeline provides.
 * a gzipped copy of the gtf file
 * ref_flat and rRNA interval files (for use with [picard](http://broadinstitute.github.io/picard/command-line-overview.html#CollectRnaSeqMetrics))
 * indexes for STAR and RSEM.
 

## Preparation

You will need an installation of  ensembl-hive ([2.2](https://github.com/Ensembl/ensembl-hive)), and a compute cluster using LSF. It should be possible to use an alternative system by updating the resource_classes listed in Bio::RefBuild::PipeConfig::RefBuilderConf. Hive needs a mysql database to track the pipeline.

The pipeline requires several external programs. The version used in development is listed:

 * bedtools ([v2.17.0](https://github.com/arq5x/bedtools2/releases))
 * bgzip ([tabix 0.2.4](http://www.htslib.org/download/))
 * bismark ([v0.14.3](http://www.bioinformatics.babraham.ac.uk/projects/bismark/))
 * bowtie ([1.1.1](http://bowtie-bio.sourceforge.net/index.shtml))
 * bowtie2 ([2.2.5](http://bowtie-bio.sourceforge.net/bowtie2/index.shtml))
 * bwa ([0.7.5a](https://sourceforge.net/projects/bio-bwa/files/))
 * gtfToGenePred ([downloaded 2015-06-30](http://hgdownload.cse.ucsc.edu/admin/exe/linux.x86_64/))
 * java ([1.6.0_24](https://java.com/en/download/))
 * picard( ([1.135](http://broadinstitute.github.io/picard/))
 * rsem ([1.2.21](http://deweylab.biostat.wisc.edu/rsem/))
 * samtools ([1.2](http://www.htslib.org/download/)) (including the script misc/seq\_cache\_populate.pl) 
 * star ([2.4.2a](https://github.com/alexdobin/STAR/releases/tag/STAR_2.4.2a))

In addition, the pipeline expects to run under linux and makes use of standard linux tools:

 * cp
 * cut
 * find
 * gunzip
 * rm
 * sed
 * tee

Download the reference\_data\_builder code, install the perl dependencies listed in the cpanfile and add the lib/ dir to your PERL5LIB environment variable.


## Setup the pipeline 

Use hive's init pipeline to create a pipeline database:

    init_pipeline.pl Bio::RefBuild::PipeConfig::RefBuilderConf \
      -host <dbhost> -port <dbport> -user <dbuser> -password <dbpassword> \
      -bedtools /path/to/bedtools \
      -bowtie1_dir /path/to//bowtie-1 \
      -bowtie2_dir /path/to/bowtie2-2 \
      -bwa /path/to/bwa-0.7.5a/bwa \
      -java /path/to/java \
      -picard /path/to/picard.jar \
      -samtools /path/to/samtools \
      -bgzip /path/to/tabix/bgzip \
      -star /path/to/STAR/bin/Linux_x86_64/STAR \
      -gtfToGenePred /path/to/gtfToGenePred \
      -rsem_dir /path/to/rsem \
      -bismark_dir /path/to/bismark \
      -bedGraphToBigWig /path/to/bedGraphToBigWig \
      -wiggletools /path/to/wiggletools \
      -cram_seq_cache_populate_script /path/to/seq\_cache\_populate.pl \
      -lsf_queue_name a_queue_name \
      -cram_cache_root /path/to/cram/cache/root
      -output_root /path/to/output_dir
      
You may also specfiy `-lsf_std_param` to add additional LSF parameters for all jobs. For example, we use  `-lsf_std_param '-R"select[lustre]"'` to ensure that all nodes can see the required storage area. The CRAM reference cache is explained on the [HTSlib](http://www.htslib.org/workflow/#the-refpath-and-refcache) site. Set `cram_cache_root` to the  directory used in the `REF_CACHE` environment variable.

The output of this will include the database URL required for later steps, e.g. `mysql://dbuser:dbpassword@dbhost:dbport/myuser_ref_builder`

## Workflow

You can choose to run everything at once, or run each major step individually. The major steps are:

1. Create assembly specific resources
2. Create one or more annotation specific resources
3. Create mappability tracks for a range of kmer/read lengths
4. Create a manifest file describing all files produced

### Assembly specific resources

Seed the pipeline with the species and assembly names, the path to the gzipped fasta file, and a source URL of the fasta file (this will be used in the sequence dictionary). The fasta file should have the chromosomes in the order you wish to use for your output. The description lines can contain as much information as you wish, but the sequence name (e.g. chr1) should be the first thing after the > character, and should be separated from any additional information by a space (i.e. '>1 dna:chromosome' is OK, '>1**|**dna:chromosome' is not). 

    seed_pipeline.pl -url mysql://dbuser:dbpassword@dbhost:dbport/myuser_ref_builder \
      -logic_name start_assembly -input_id \
      "{assembly_name => 'galgal4', species_name => 'Gallus gallus', fasta_uri => 'ftp://ftp.ensembl.org/pub/release-80/fasta/gallus_gallus/dna/Gallus_gallus.Galgal4.dna.toplevel.fa.gz', fasta_file => 'Gallus_gallus.Galgal4.dna.toplevel.fa.gz', }"
 
 Run the pipeline with hive's beekeeper. This will take some time, it is best to run it under [GNU Screen](http://www.gnu.org/software/screen/) or [tmux](https://tmux.github.io/):
 
     beekeeper.pl -url mysql://dbuser:dbpassword@dbhost:dbport/myuser_ref_builder -loop

### Gene set specific resources

Once the assembly has been processed, you can add gene set annotations to it. These should be in the form of a gzipped gtf file. The annotation pipeline relies on the output of the assembly steps, and should be based on the same assembly.  

    seed_pipeline.pl -url mysql://dbuser:dbpassword@dbhost:dbport/myuser_ref_builder \
      -logic_name start_assembly -input_id \
      "{assembly_name => 'galgal4', species_name => 'Gallus gallus', gtf_file => 'Gallus_gallus.Galgal4.80.gtf.gz', annotation_name => 'e80', }"
    
    beekeeper.pl -url mysql://dbuser:dbpassword@dbhost:dbport/myuser_ref_builder -loop
    
The pipeline has been most thoroughly tested with Ensembl GTF files. We are also testing it with RefSeq annotation for goat, converted to GTF using the script `scripts/example_gff3_to_gtf_conversion.pl`. For simplicities sake, we reduce the GTF to just exons with gene\_id and transcript\_id attributes for use with RSEM and STAR, since these are the only features they can use.
    
### Write manifest

It can be useful to have a manifest file, listing the size and a checksum value for each file. 

    seed_pipeline.pl -url mysql://dbuser:dbpassword@dbhost:dbport/myuser_ref_builder \
      -logic_name start_manifest -input_id \
      "{assembly_name => 'galgal4', species_name => 'Gallus gallus',}"
    
      beekeeper.pl -url mysql://dbuser:dbpassword@dbhost:dbport/myuser_ref_builder -loop

### Run everything at once

For ease of use, you can seed all steps in one go:

    seed_pipeline.pl -url mysql://dbuser:dbpassword@dbhost:dbport/myuser_ref_builder \
      -logic_name start_all -input_id \
      "{assembly_name=>'Galgal4',fasta_uri=>'ftp://ftp.ensembl.org/pub/release-80/fasta/gallus_gallus/dna/Gallus_gallus.Galgal4.dna.toplevel.fa.gz',fasta_file=>'Gallus_gallus.Galgal4.dna.toplevel.fa.gz',species_name=>'Gallus gallus',kmer_sizes=>'50,100,150,200',annotation_name=>'e80',gtf_file=>'Gallus_gallus.Galgal4.80.gtf.gz'}"  
    
    beekeeper.pl -url mysql://dbuser:dbpassword@dbhost:dbport/myuser_ref_builder -loop
    
 ## Funding
The FAANG Data Coordination Centre has received funding from the [European Union’s Horizon 2020](https://ec.europa.eu/programmes/horizon2020/) research and innovation program under 
Grant Agreement Nos. 815668, 817923 and 817998, and also form the Biotechnology and [Biological Sciences Research Council](https://bbsrc.ukri.org/) under Grant Agreement No. BB/N019563/1.
    
