// Step 1: Extract per-sample consensus marker profiles from MetaPhlAn SAM outputs.
// sample2markers.py decompresses the .sam.bz2 and writes one .json marker file
// per sample (StrainPhlAn 4.1 uses .json format, not .pkl as in older versions).
process SAMPLE2MARKERS {
    tag "$sample_id"
    label 'process_high_memory'

    publishDir "${params.outdir}/strainphlan/markers", mode: 'copy'

    input:
    tuple val(sample_id), path(sam_bz2)
    path metaphlan_db

    output:
    path "*.pkl", emit: markers, optional: true

    script:
    """
    MPADB=${metaphlan_db}/${params.metaphlan_db_version}.pkl
    echo "Using database: \$MPADB" >&2
    sample2markers.py \\
        --input ${sam_bz2} \\
        --output_dir . \\
        -d "\$MPADB" \\
        --nprocs ${task.cpus}
    echo "=== Files in work dir after sample2markers ===" >&2
    ls -la . >&2
    """
}

// Step 2: Scan all sample markers to identify which SGB clades are present
// across the cohort. In StrainPhlAn 4.x clades are identified by t__SGB IDs
// (e.g. t__SGB1877), not s__-prefixed species names.
process STRAINPHLAN_PRINT_CLADES {
    label 'process_medium'

    publishDir "${params.outdir}/strainphlan", mode: 'copy'

    input:
    path markers   // all per-sample .json marker files collected into one list

    output:
    path "clades.txt", emit: clades

    script:
    """
    strainphlan \\
        --samples *.pkl \\
        --output_dir . \\
        --print_clades_only \\
        --nprocs ${task.cpus} \\
        > clades_raw.txt 2>&1 || true

    # Extract SGB clade IDs (t__ prefix used in StrainPhlAn 4.x); skip comments/header
    grep '^t__' clades_raw.txt | awk '{print \$1}' > clades.txt
    """
}

// Step 3: Profile each detected clade. For each SGB, extract its marker genes
// from the MetaPhlAn database, then run StrainPhlAn to produce a phylogenetic
// tree. One task per clade; runs in parallel across all clades.
// Tree output is optional — StrainPhlAn skips clades with too few samples.
process STRAINPHLAN {
    tag "$clade"
    label 'process_high_memory'

    publishDir "${params.outdir}/strainphlan/clades/${clade}", mode: 'copy'

    input:
    val  clade
    path markers       // all per-sample .json marker files (staged in work dir)
    path metaphlan_db  // MetaPhlAn database directory (contains .pkl for extract_markers.py)

    output:
    path "*.tre",        emit: trees, optional: true
    path "${clade}.log", emit: log

    script:
    """
    # Locate the MetaPhlAn .pkl database file needed by extract_markers.py
    MPADB=\$(find ${metaphlan_db} -name "*.pkl" | head -1)

    # --clades takes nargs='+'; pass single clade ID (t__SGB*)
    extract_markers.py \\
        --database "\$MPADB" \\
        --clades ${clade} \\
        --output_dir .

    strainphlan \\
        --samples *.pkl \\
        --clade_markers ${clade}.fna \\
        --output_dir . \\
        --clade ${clade} \\
        --nprocs ${task.cpus} \\
        > ${clade}.log 2>&1

    # Rename RAxML best-tree file to a consistent .tre extension
    find . -name "RAxML_bestTree.*" -exec cp {} ${clade}.tre \\; || true
    """
}
