// Step 1 of 4 — run HUMAnN per sample
process HUMANN {
    tag "$sample_id"
    label 'process_high_memory'

    publishDir "${params.output}/humann/main", mode: 'copy'

    input:
    tuple val(sample_id), path(r1), path(r2), path(metaphlan_profile)
    path humann_nt_db
    path humann_prot_db
    path humann_map_db

    output:
    tuple val(sample_id), path("${sample_id}_genefamilies.tsv"),  emit: genefamilies
    tuple val(sample_id), path("${sample_id}_pathabundance.tsv"), emit: pathabundance
    tuple val(sample_id), path("${sample_id}_pathcoverage.tsv"),  emit: pathcoverage
    tuple val(sample_id), path("${sample_id}_humann.log"),        emit: logs

    script:
    """
    # HUMAnN expects a single FASTQ — concatenate paired reads
    cat ${r1} ${r2} > ${sample_id}_concat.fastq.gz

    humann \\
        --input ${sample_id}_concat.fastq.gz \\
        --output . \\
        --output-basename ${sample_id} \\
        --taxonomic-profile ${metaphlan_profile} \\
        --nucleotide-database ${humann_nt_db} \\
        --protein-database ${humann_prot_db} \\
        --pathways-database ${humann_map_db} \\
        --threads ${task.cpus} \\
        --remove-temp-output \\
        --o-log ${sample_id}_humann.log

    rm ${sample_id}_concat.fastq.gz
    """
}

// Step 2 of 4 — regroup UniRef gene families → EC numbers, per sample
process HUMANN_REGROUP {
    tag "$sample_id"
    label 'process_low'

    publishDir "${params.output}/humann/regrouped", mode: 'copy'

    input:
    tuple val(sample_id), path(genefamilies)

    output:
    tuple val(sample_id), path("${sample_id}_ecs.tsv"), emit: ecs

    script:
    """
    humann_regroup_table \\
        --input ${genefamilies} \\
        --output ${sample_id}_ecs.tsv \\
        --groups uniref90_level4ec
    """
}

// Step 3 of 4 — normalize to relative abundance, per sample
// Takes genefamilies + ecs + pathabundance together so all three are
// processed in one task rather than spawning three separate jobs per sample.
process HUMANN_RENORM {
    tag "$sample_id"
    label 'process_low'

    publishDir "${params.output}/humann/relab", mode: 'copy'

    input:
    tuple val(sample_id),
          path(genefamilies),
          path(ecs),
          path(pathabundance)

    output:
    tuple val(sample_id), path("${sample_id}_genefamilies_relab.tsv"),  emit: genefamilies_relab
    tuple val(sample_id), path("${sample_id}_ecs_relab.tsv"),           emit: ecs_relab
    tuple val(sample_id), path("${sample_id}_pathabundance_relab.tsv"), emit: pathabundance_relab

    script:
    """
    humann_renorm_table \\
        --input ${genefamilies} \\
        --output ${sample_id}_genefamilies_relab.tsv \\
        --units relab --update-snames

    humann_renorm_table \\
        --input ${ecs} \\
        --output ${sample_id}_ecs_relab.tsv \\
        --units relab --update-snames

    humann_renorm_table \\
        --input ${pathabundance} \\
        --output ${sample_id}_pathabundance_relab.tsv \\
        --units relab --update-snames
    """
}

// Step 4 of 4 — join per-sample tables into cohort-level merged files
// Run once after all samples complete (inputs collected via .collect()).
process HUMANN_JOIN {
    label 'process_low'

    publishDir "${params.output}/humann/merged", mode: 'copy'

    input:
    path genefamilies_relab_files
    path ecs_relab_files
    path pathabundance_relab_files
    path pathcoverage_files

    output:
    path "genefamilies_relab.tsv",    emit: genefamilies_relab
    path "ecs_relab.tsv",             emit: ecs_relab
    path "pathabundance_relab.tsv",   emit: pathabundance_relab
    path "pathcoverage.tsv",          emit: pathcoverage

    script:
    """
    humann_join_tables \\
        --input . \\
        --output genefamilies_relab.tsv \\
        --file_name genefamilies_relab

    humann_join_tables \\
        --input . \\
        --output ecs_relab.tsv \\
        --file_name ecs_relab

    humann_join_tables \\
        --input . \\
        --output pathabundance_relab.tsv \\
        --file_name pathabundance_relab

    humann_join_tables \\
        --input . \\
        --output pathcoverage.tsv \\
        --file_name pathcoverage
    """
}
