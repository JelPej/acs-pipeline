// Aggregates QC outputs from FastQC and KneadData into a single report.
// All input files are staged into the work directory — MultiQC scans it automatically.
// Run once after all per-sample steps complete (inputs collected via .collect()).
process MULTIQC {
    label 'process_low'

    publishDir "${params.outdir}/qc_summary", mode: 'copy'

    input:
    path fastqc_zips           // per-sample FastQC zip files
    path kneaddata_logs        // per-sample KneadData log files
    path kneaddata_read_counts // merged kneaddata_read_count_table.tsv

    output:
    path "multiqc_report.html",  emit: report
    path "multiqc_data/",        emit: data

    script:
    def config_flag = params.multiqc_config ? "--config ${params.multiqc_config}" : ''
    """
    multiqc \\
        ${config_flag} \\
        --title "Biobakery WMGX QC Report" \\
        --comment "FastQC + KneadData (Trimmomatic 0.40 / Bowtie2 2.5.5 / host: ${params.kneaddata_db})" \\
        --filename multiqc_report \\
        --outdir . \\
        .
    """
}
