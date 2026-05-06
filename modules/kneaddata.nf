process KNEADDATA {
    tag "$sample_id"
    label 'process_high'

    publishDir "${params.outdir}/kneaddata/main",  mode: 'copy', pattern: "*.fastq.gz"
    publishDir "${params.outdir}/kneaddata/logs",  mode: 'copy', pattern: "*.log"
    publishDir "${params.outdir}/kneaddata/stats", mode: 'copy', pattern: "*.stats"

    input:
    tuple val(sample_id), path(r1), path(r2)
    path  kneaddata_db

    output:
    tuple val(sample_id),
          path("${sample_id}_kneaddata_paired_1.fastq.gz"),
          path("${sample_id}_kneaddata_paired_2.fastq.gz"),  emit: reads
    tuple val(sample_id), path("${sample_id}_kneaddata_contaminants.fastq.gz"), emit: contaminants, optional: true
    tuple val(sample_id), path("${sample_id}_kneaddata.log"),                   emit: logs
    tuple val(sample_id), path("${sample_id}_kneaddata.stats"),                 emit: stats

    script:
    """
    TRIMMOMATIC_DIR=\$(dirname \$(find /opt/conda /usr/local/share -name "trimmomatic.jar" 2>/dev/null | head -1))

    kneaddata \\
        --input1 ${r1} \\
        --input2 ${r2} \\
        --reference-db ${kneaddata_db} \\
        --output . \\
        --output-prefix ${sample_id}_kneaddata \\
        --trimmomatic "\$TRIMMOMATIC_DIR" \\
        --trimmomatic-options "${params.trimmomatic_options}" \\
        --threads ${task.cpus} \\
        --log ${sample_id}_kneaddata.log

    gzip *.fastq

    # Verify paired outputs exist — fail early with a clear message if missing
    if [[ ! -f "${sample_id}_kneaddata_paired_1.fastq.gz" || \\
          ! -f "${sample_id}_kneaddata_paired_2.fastq.gz" ]]; then
        echo "ERROR: KneadData did not produce paired outputs for ${sample_id}" >&2
        echo "Check ${sample_id}_kneaddata.log for details" >&2
        exit 1
    fi

    # Merge all contaminant files (one per reference DB + paired end) into
    # a single file matching the expected output name
    cat *contam*.fastq.gz > ${sample_id}_kneaddata_contaminants.fastq.gz || true

    # Generate per-sample .stats file from the log
    # Includes read counts at each step + the trimming settings used
    kneaddata_read_count_table \\
        --input . \\
        --output ${sample_id}_kneaddata.stats

    # Append trimming settings so the client has a full record in one file
    echo "" >> ${sample_id}_kneaddata.stats
    echo "# Trimming settings" >> ${sample_id}_kneaddata.stats
    echo "# ${params.trimmomatic_options}" >> ${sample_id}_kneaddata.stats
    """
}

// Aggregates per-sample KneadData logs into a single read-count summary table.
// Run once after all samples complete (inputs collected via .collect()).
process KNEADDATA_READ_COUNT_TABLE {
    label 'process_low'

    publishDir "${params.outdir}/kneaddata/merged", mode: 'copy'

    input:
    path logs   // all per-sample .log files collected

    output:
    path "kneaddata_read_count_table.tsv", emit: read_counts

    script:
    """
    kneaddata_read_count_table \\
        --input . \\
        --output kneaddata_read_count_table.tsv
    """
}
