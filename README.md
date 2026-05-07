# ACS WMGX Pipeline

Nextflow DSL2 implementation of the [Biobakery](https://github.com/biobakery/biobakery_workflows) whole metagenome shotgun (WMGX) workflow, designed to run on **AWS HealthOmics**.

## Pipeline overview

```
Raw paired FASTQ
  └─ ENSURE_GZIP          normalize to .fastq.gz
  └─ FASTQC               raw read QC
  └─ KNEADDATA            host removal + adapter trimming
  └─ METAPHLAN            taxonomic profiling (per sample)
  └─ MERGE_TAXONOMIC_PROFILES   cohort-level taxonomy table
  └─ HUMANN               functional profiling (per sample)
  └─ HUMANN_REGROUP       gene families → ECs
  └─ HUMANN_RENORM        relative abundance normalization
  └─ HUMANN_JOIN          cohort-level functional tables
  └─ MULTIQC              QC report
  └─ [optional] SAMPLE2MARKERS + STRAINPHLAN   strain profiling
```

---

## S3 locations

### Input data

| Item | S3 path |
|------|---------|
| Raw reads | `s3://manifold-ai-sc-manifold-stage-platform-storage/research/projects/3649/data/acs_pipeline/input/` |

Reads must be paired-end FASTQ (`.fastq` or `.fastq.gz`). Files should follow the naming pattern:

```
<sample_id>_R1.fastq.gz
<sample_id>_R2.fastq.gz
```

The `input` parameter uses a glob, e.g.:

```
s3://.../input/*_R{1,2}.fastq.gz
```

### Databases

| Database | S3 path |
|----------|---------|
| KneadData (GRCh38 host) | `s3://manifold-ai-sc-manifold-stage-platform-storage/research/projects/3649/data/acs_pipeline/databases/kneaddata/GRCh38/` |
| MetaPhlAn (`mpa_vJun23`) | `s3://manifold-ai-sc-manifold-stage-platform-storage/research/projects/3649/data/acs_pipeline/databases/metaphlan/mpa_vJun23/` |
| HUMAnN nucleotide (ChocoPhlAn) | `s3://manifold-ai-sc-manifold-stage-platform-storage/research/projects/3649/data/acs_pipeline/databases/humann/chocophlan/` |
| HUMAnN protein (UniRef) | `s3://manifold-ai-sc-manifold-stage-platform-storage/research/projects/3649/data/acs_pipeline/databases/humann/uniref/` |
| HUMAnN mapping (MetaCyc) | `s3://manifold-ai-sc-manifold-stage-platform-storage/research/projects/3649/data/acs_pipeline/databases/humann/metacyc/utility_mapping/` |

### Output

| Item | S3 path |
|------|---------|
| Pipeline outputs | `s3://manifold-ai-sc-manifold-stage-platform-storage/research/projects/3649/data/acs_pipeline/output/` |
| Test run outputs | `s3://manifold-ai-sc-manifold-stage-platform-storage/research/projects/3649/data/acs_pipeline/output/test/` |

#### Output directory structure

```
output/
├── fastqc/                         raw read QC (per sample)
├── kneaddata/
│   ├── <sample_id>/                trimmed/filtered reads
│   └── kneaddata_read_counts.tsv   cohort read-count table
├── metaphlan/
│   ├── main/<sample_id>_metaphlan_profile.tsv   per-sample taxonomy
│   └── merged/
│       ├── metaphlan_taxonomic_profiles.tsv     all ranks
│       └── metaphlan_species_profiles.tsv       species only
├── humann/
│   ├── main/                       per-sample gene families, path abundance/coverage
│   ├── regroup/                    per-sample EC tables
│   ├── renorm/                     per-sample relative abundance tables
│   └── joined/                     cohort-level tables (genefamilies, ecs, pathabundance, pathcoverage)
├── strainphlan/                    (only when run_strainphlan=true)
│   ├── markers/                    per-sample consensus marker .json files
│   ├── clades.txt                  detected SGB clade IDs
│   └── clades/<t__SGB*>/           per-clade phylogenetic tree (.tre) and log
└── multiqc/                        aggregated QC report
```

---

## Running on AWS HealthOmics

### Prerequisites

- AWS CLI configured with access to the account
- The workflow registered in HealthOmics (note the `WORKFLOW_ID`)
- An IAM role with permissions to read S3 inputs/databases and write to the output bucket

### Start a run

```bash
aws omics start-run \
  --workflow-id <WORKFLOW_ID> \
  --role-arn arn:aws:iam::<ACCOUNT_ID>:role/<OMICS_ROLE_NAME> \
  --output-uri s3://manifold-ai-sc-manifold-stage-platform-storage/research/projects/3649/data/acs_pipeline/output/ \
  --parameters file://params.json \
  --name "acs-wmgx-run-$(date +%Y%m%d)" \
  --region us-east-1
```

### Test run (single sample)

```bash
aws omics start-run \
  --workflow-id <WORKFLOW_ID> \
  --role-arn arn:aws:iam::<ACCOUNT_ID>:role/<OMICS_ROLE_NAME> \
  --output-uri s3://manifold-ai-sc-manifold-stage-platform-storage/research/projects/3649/data/acs_pipeline/output/test/ \
  --parameters file://params.test.json \
  --name "acs-wmgx-test-$(date +%Y%m%d)" \
  --region us-east-1
```

### Check run status

```bash
aws omics get-run --id <RUN_ID> --region us-east-1
```

### params.json reference

```json
{
    "input":          "s3://.../input/*_R{1,2}.fastq.gz",
    "output":         "s3://.../output/",
    "outdir":         "/mnt/workflow/pubdir",

    "kneaddata_db":   "s3://.../databases/kneaddata/GRCh38/",
    "metaphlan_db":   "s3://.../databases/metaphlan/mpa_vJun23/",
    "humann_nt_db":   "s3://.../databases/humann/chocophlan/",
    "humann_prot_db": "s3://.../databases/humann/uniref/",
    "humann_map_db":  "s3://.../databases/humann/metacyc/utility_mapping/",

    "run_strainphlan": false
}
```

Set `"run_strainphlan": true` to enable optional strain profiling (adds SAMPLE2MARKERS + STRAINPHLAN steps). Use `"strainphlan_max_clades": 20` to cap the number of species profiled.

---

## Running locally (Docker)

```bash
nextflow run main.nf \
  -profile local \
  -params-file params.json
```

Requires Docker and Nextflow ≥ 23.x.
