process FASTQC {
    tag "$sample_id"
    label 'process_medium'

    publishDir "${params.output}/fastqc", mode: 'copy'

    input:
    tuple val(sample_id), path(r1), path(r2)

    output:
    tuple val(sample_id), path("*.html"), emit: html
    tuple val(sample_id), path("*.zip"),  emit: zip

    script:
    """
    fastqc \\
        --threads ${task.cpus} \\
        --outdir . \\
        ${r1} ${r2}
    """
}
