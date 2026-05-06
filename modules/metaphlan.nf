process METAPHLAN {
    tag "$sample_id"
    label 'process_high'

    publishDir "${params.outdir}/metaphlan/main", mode: 'copy'

    input:
    tuple val(sample_id), path(r1), path(r2)
    path metaphlan_db

    output:
    tuple val(sample_id), path("${sample_id}_metaphlan_profile.tsv"),  emit: profiles
    tuple val(sample_id), path("${sample_id}_metaphlan.bowtie2.bz2"),  emit: bowtie2out
    tuple val(sample_id), path("${sample_id}_metaphlan.sam.bz2"),      emit: sam

    script:
    """
    metaphlan \\
        ${r1},${r2} \\
        --input_type fastq \\
        --db_dir ${metaphlan_db} \\
        --index ${params.metaphlan_db_version} \\
        --output_file ${sample_id}_metaphlan_profile.tsv \\
        --mapout ${sample_id}_metaphlan.bowtie2.bz2 \\
        --samout ${sample_id}_metaphlan.sam.bz2 \\
        --nproc ${task.cpus}
    """
}

// Merges per-sample MetaPhlAn profiles into cohort-level tables.
// Run once after all samples complete (inputs collected via .collect()).
process MERGE_TAXONOMIC_PROFILES {
    label 'process_low'

    publishDir "${params.outdir}/metaphlan/merged", mode: 'copy'

    input:
    path profiles   // all per-sample profile TSVs collected

    output:
    path "metaphlan_taxonomic_profiles.tsv",       emit: merged
    path "metaphlan_species_profiles.tsv",         emit: species

    script:
    """
    # Merge all per-sample profiles into one cohort table
    merge_metaphlan_tables.py ${profiles} \\
        -o metaphlan_taxonomic_profiles.tsv

    # Extract species-level rows only (s__ but not strain-level t__)
    # Keeps the header comment lines so the file is self-describing
    head -n 1 metaphlan_taxonomic_profiles.tsv > metaphlan_species_profiles.tsv
    grep -E "\\bs__" metaphlan_taxonomic_profiles.tsv \\
        | grep -v "t__" \\
        >> metaphlan_species_profiles.tsv
    """
}
