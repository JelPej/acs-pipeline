#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

/*
 * Biobakery WMGX Pipeline
 * Whole Metagenome Shotgun workflow
 * Nextflow DSL2 — AWS HealthOmics
 */

include { WMGX } from './workflows/wmgx'

workflow {
    if (!params.input)  error "Missing required parameter: --input"
    if (!params.output) error "Missing required parameter: --output"

    if (!params.kneaddata_db)   error "Missing required parameter: --kneaddata_db"
    if (!params.metaphlan_db)   error "Missing required parameter: --metaphlan_db"
    if (!params.humann_nt_db)   error "Missing required parameter: --humann_nt_db"
    if (!params.humann_prot_db) error "Missing required parameter: --humann_prot_db"
    if (!params.humann_map_db)  error "Missing required parameter: --humann_map_db"

    Channel
        .fromFilePairs(params.input, flat: true, size: 2)
        .ifEmpty { error "No paired FASTQ files found at: ${params.input}" }
        .set { raw_reads_ch }

    WMGX(raw_reads_ch)
}
