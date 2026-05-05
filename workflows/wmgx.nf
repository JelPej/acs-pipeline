nextflow.enable.dsl = 2

include { FASTQC                                          } from '../modules/fastqc'
include { KNEADDATA; KNEADDATA_READ_COUNT_TABLE            } from '../modules/kneaddata'
include { METAPHLAN; MERGE_TAXONOMIC_PROFILES             } from '../modules/metaphlan'
include { HUMANN; HUMANN_REGROUP; HUMANN_RENORM;
          HUMANN_JOIN                                     } from '../modules/humann'
include { MULTIQC                                         } from '../modules/multiqc'

workflow WMGX {
    take:
    raw_reads_ch   // tuple val(sample_id), path(r1), path(r2)

    main:
    // Resolve database paths from params
    kneaddata_db   = file(params.kneaddata_db)
    metaphlan_db   = file(params.metaphlan_db)
    humann_nt_db   = file(params.humann_nt_db)
    humann_prot_db = file(params.humann_prot_db)
    humann_map_db  = file(params.humann_map_db)

    // Step 4 — Raw FASTQ QC
    FASTQC(raw_reads_ch)

    // Step 5 — Host removal & trimming
    KNEADDATA(raw_reads_ch, kneaddata_db)
    KNEADDATA_READ_COUNT_TABLE(KNEADDATA.out.logs.map { it[1] }.collect())

    // Step 6 — Taxonomic profiling (per sample, parallel)
    METAPHLAN(KNEADDATA.out.reads, metaphlan_db)
    MERGE_TAXONOMIC_PROFILES(METAPHLAN.out.profiles.map { it[1] }.collect())

    // StrainPhlAn uses the SAM outputs — kept available for when it is implemented
    // METAPHLAN.out.sam  → tuple val(sample_id), path(sam)

    // Step 7a — Functional profiling (per sample, parallel)
    // Join KneadData reads with matching MetaPhlAn profile by sample_id
    kneaddata_and_metaphlan = KNEADDATA.out.reads
        .join(METAPHLAN.out.profiles, by: 0)

    HUMANN(kneaddata_and_metaphlan, humann_nt_db, humann_prot_db, humann_map_db)

    // Regroup UniRef gene families → ECs, per sample
    HUMANN_REGROUP(HUMANN.out.genefamilies)

    // Normalize to relative abundance — join genefamilies + ecs + pathabundance
    // by sample_id so all three tables are renormed in one task per sample
    to_renorm = HUMANN.out.genefamilies
        .join(HUMANN_REGROUP.out.ecs,         by: 0)
        .join(HUMANN.out.pathabundance,        by: 0)

    HUMANN_RENORM(to_renorm)

    // Collect all per-sample relab files and join into cohort-level tables
    HUMANN_JOIN(
        HUMANN_RENORM.out.genefamilies_relab.map  { it[1] }.collect(),
        HUMANN_RENORM.out.ecs_relab.map           { it[1] }.collect(),
        HUMANN_RENORM.out.pathabundance_relab.map { it[1] }.collect(),
        HUMANN.out.pathcoverage.map               { it[1] }.collect()
    )

    // Step 8 — QC aggregation
    MULTIQC(
        FASTQC.out.zip.map { it[1] }.flatten().collect(),
        KNEADDATA.out.logs.map { it[1] }.flatten().collect(),
        KNEADDATA_READ_COUNT_TABLE.out.read_counts
    )
}
