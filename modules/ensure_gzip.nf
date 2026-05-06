process ENSURE_GZIP {
    tag "$sample_id"
    label 'process_low'

    input:
    tuple val(sample_id), path(r1), path(r2)

    output:
    tuple val(sample_id), path("${sample_id}_R1.fastq.gz"), path("${sample_id}_R2.fastq.gz")

    script:
    """
    if gzip -t "${r1}" 2>/dev/null; then
        cp "${r1}" .tmp_R1.fastq.gz
    else
        gzip -c "${r1}" > .tmp_R1.fastq.gz
    fi
    mv .tmp_R1.fastq.gz "${sample_id}_R1.fastq.gz"

    if gzip -t "${r2}" 2>/dev/null; then
        cp "${r2}" .tmp_R2.fastq.gz
    else
        gzip -c "${r2}" > .tmp_R2.fastq.gz
    fi
    mv .tmp_R2.fastq.gz "${sample_id}_R2.fastq.gz"
    """
}
