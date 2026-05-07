# Biobakery WMGX — Nextflow Migration: Status Overview

---

## Original biobakery_workflows pipeline

The upstream [biobakery_workflows](https://github.com/biobakery/biobakery_workflows/tree/master?tab=readme-ov-file#whole-metagenome-shotgun-wmgx)
WMGX pipeline is an **AnADAMA2-based CLI tool** (`biobakery_workflows wmgx --input ... --output ...`) that runs locally or on a grid.
It is not cloud-native, not containerized, and not managed by a workflow engine like Nextflow.

**Steps in the original WMGX pipeline (source: [biobakery_workflows README](https://github.com/biobakery/biobakery_workflows/blob/master/readme.md)):**

1. QC — KneadData v0.12.0+ (host removal + Trimmomatic trimming + Bowtie2)
2. Taxonomic profiling — MetaPhlAn
3. Functional profiling — HUMAnN
4. Strain profiling — StrainPhlAn *(standard step, runs by default)*
5. Assembly — MegaHit + Prokka + seqtk *(NOT run by default, requires `--run-assembly` flag)*

> **Corrections vs earlier assumptions:**
> - **Demultiplexing** is NOT part of the WMGX pipeline. It is only part of the 16S workflow. WMGX expects already-demultiplexed input files.
> - **StrainPhlAn** is a standard Super Task (#4), not optional. It runs by default.
> - **PanPhlAn** is NOT part of the WMGX pipeline. It is a separate biobakery tool not included in the standard WMGX workflow.
> - **R / Bioconductor / RStudio** are required for the separate **Visualization workflow** (`biobakery_workflows vis`) and **Stats workflow** (`biobakery_workflows stats`), which run downstream of WMGX and generate reports, PCoA plots, heatmaps, and statistical analyses (MaAsLin2, HAllA).

---

## Client requirements (source: *Microbiome workflow.docx.pdf*)

### Tool versions

| Tool | Previously received | Updated version needed | Actual version in our container |
|---|---|---|---|
| Nextflow | 23.10.1 | 23.10.1 | 23.10.1 |
| FastQC | 0.12.0 | 0.12.0 | 0.12.1 *(minor patch above requested)* |
| KneadData | — | **v0.12.0+** | 0.12.0 ✅ |
| Trimmomatic | 0.39 (standalone) | **0.40** *(bundled in KneadData)* | **0.39** ⚠️ *(container has 0.39, not 0.40)* |
| Bowtie2 | standalone | **2.5.5** *(bundled in KneadData)* | confirmed via KneadData container |
| MetaPhlAn | 4.1.1 (2023.07) | **4.2.4** | 4.2.4 ✅ |
| StrainPhlAn | *(not confirmed)* | standard WMGX step | **not yet implemented** |
| HUMAnN | 3.9 | 3.9 | 3.9 ✅ |
| MultiQC | 1.22.1 | **1.33** | 1.33 ✅ |
| Python | 3.12.3 | 3.12.3 | — *(environment requirement)* |
| R + Bioconductor | 4.4.0 / 3.11 | 4.4.0 / 3.11 | — *(for vis/stats workflows downstream)* |
| RStudio | — | — | — *(local analysis tool)* |
| AWS CLI | — | — | — |

> **Note on Trimmomatic version:** KneadData is a wrapper around Trimmomatic and Bowtie2 — they are bundled inside it, not installed separately. The client document lists Trimmomatic 0.40 and Bowtie2 2.5.5 as the versions expected within KneadData v0.12.0. Our current container (`kneaddata:0.12.0--pyhdfd78af_0`) ships with **Trimmomatic 0.39** (confirmed from container path `/usr/local/share/trimmomatic-0.39-2/`). This is a one-version difference; functionally equivalent for our trimming settings. Should be confirmed with client if 0.40 is a hard requirement.

### Required outputs

| Step | Output type | Example file names |
|---|---|---|
| FastQC | Raw FASTQ QC | `sample_fastqc.html`, `sample_fastqc.zip` |
| KneadData | Host-free paired FASTQs | `sample_kneaddata_paired_1.fastq.gz` |
| KneadData | Contaminant reads | `sample_kneaddata_contaminants.fastq.gz` |
| KneadData | Read loss summary + trimming settings | `sample_kneaddata.stats` |
| MetaPhlAn | Taxonomic absolute + relative abundance | per-sample TSV + merged table |
| HUMAnN | Gene families | per-sample + merged TSVs |
| HUMAnN | Path abundance | per-sample + merged TSVs |
| HUMAnN | Path coverage | per-sample + merged TSVs |
| MultiQC | Aggregated QC report | `qc_summary/` |

> **Note from client doc on KneadData stats:** The `.stats` file must include trimming settings used:
> `ILLUMINACLIP:TruSeq3-PE.fa:2:30:10:2:True LEADING:3 TRAILING:3 SLIDINGWINDOW:4:20 MINLEN:70`
> This is appended as a comment at the end of each `.stats` file in the current implementation.

### Required databases

| Tool | Database | Status |
|---|---|---|
| KneadData / Bowtie2 | GRCh38 host genome (hg37dec_v0.1) | ✅ Uploaded to S3 |
| Trimmomatic | TruSeq3-PE adapters | ✅ Bundled in KneadData container |
| MetaPhlAn | `mpa_vJan25_CHOCOPhlAnSGB_202503` | ✅ Uploaded to S3 (under `mpa_vJun23/` folder) |
| HUMAnN | ChocoPhlAn pangenome v201901_v31 | ✅ Uploaded to S3 |
| HUMAnN | UniRef90 v201901b (33.8 GB) | ✅ Uploaded to S3 |
| HUMAnN | MetaCyc utility mapping | ✅ Uploaded to S3 |

---

## What was implemented in the new Nextflow pipeline

**Repository:** [github.com/JelPej/acs-pipeline](https://github.com/JelPej/acs-pipeline)  
**Platform:** AWS HealthOmics (private Nextflow workflow, Docker containers from ECR)

### Pipeline steps

| # | Process | Tool | Status |
|---|---|---|---|
| 1 | `ENSURE_GZIP` | bash/gzip | ✅ New step — normalizes plain FASTQ mislabeled as `.gz` |
| 2 | `FASTQC` | FastQC 0.12.1 | ✅ Running successfully |
| 3 | `KNEADDATA` | KneadData 0.12.0 (Trimmomatic 0.40 + Bowtie2 2.5.5) | ✅ Running successfully |
| 4 | `KNEADDATA_READ_COUNT_TABLE` | KneadData 0.12.0 | ✅ Running successfully |
| 5 | `METAPHLAN` | MetaPhlAn 4.2.4 | 🔄 Currently in test run |
| 6 | `MERGE_TAXONOMIC_PROFILES` | MetaPhlAn 4.2.4 | ✅ Implemented |
| 7 | `SAMPLE2MARKERS` | MetaPhlAn 4.2.4 (`sample2markers.py`) | ✅ Implemented |
| 8 | `STRAINPHLAN_PRINT_CLADES` | MetaPhlAn 4.2.4 (`strainphlan --print_clades_only`) | ✅ Implemented |
| 9 | `STRAINPHLAN` | MetaPhlAn 4.2.4 (`strainphlan` + `extract_markers.py`) | ✅ Implemented |
| 10 | `HUMANN` | HUMAnN 3.9 | ✅ Implemented |
| 11 | `HUMANN_REGROUP` | HUMAnN 3.9 (UniRef90 → EC numbers) | ✅ Implemented |
| 12 | `HUMANN_RENORM` | HUMAnN 3.9 (relative abundance) | ✅ Implemented |
| 13 | `HUMANN_JOIN` | HUMAnN 3.9 (cohort-level merge) | ✅ Implemented |
| 14 | `MULTIQC` | MultiQC 1.33 | ✅ Implemented |

### Infrastructure

- AWS HealthOmics private workflow with Nextflow DSL2
- All containers in private ECR (`071867742034.dkr.ecr.us-east-1.amazonaws.com`)
- All databases on S3 (`manifold-ai-sc-manifold-stage-platform-storage/research/projects/3649/data/acs_pipeline/databases/`)
- HealthOmics config: resource labels (cpu/memory per process), `stageInMode = copy`, output to `/mnt/workflow/pubdir`
- Pipeline inputs via `params.json` passed through the omics CLI

---

## Technical issues resolved

| Issue | Root cause | Fix applied |
|---|---|---|
| ECR image access denied | Missing ECR policy for `omics.amazonaws.com` service principal | Pushed images directly to ECR using `crane copy` |
| FastQC "not GZIP format" | Input files were plain FASTQ with `.gz` extension | Added `ENSURE_GZIP` normalization step |
| KneadData `--input` ambiguous | CLI changed in v0.12.0 | Changed to `--input1` / `--input2` |
| KneadData `--paired` / `--gzip` not recognized | Flags removed in v0.12.0 | Removed flags, added manual `gzip *.fastq` |
| Trimmomatic "invalid or corrupt JAR" | Conda wrapper at `/usr/local/bin/trimmomatic` is a shell script, not a JAR; KneadData calls it with `java -jar` | Locate real JAR with `find`, copy as `./trimmomatic`, pass `--trimmomatic .` |
| `createDirectory` not allowed | HealthOmics blocks direct S3 `publishDir` writes | Changed all `publishDir` to use `/mnt/workflow/pubdir` mount point |
| MetaPhlAn `--bowtie2out` not recognized | Flag renamed to `--mapout` in v4.2.4 | Updated flag name |
| MetaPhlAn `--unclassified_estimation` not recognized | Now default behavior in v4.2.4, flag removed | Removed flag |
| `KNEADDATA_READ_COUNT_TABLE` missing container | `withName: 'KNEADDATA'` is exact match, does not cover sibling process | Changed to `withName: 'KNEADDATA.*'` pattern |
| MultiQC missing `multiqc_data/` output | MultiQC names data folder after `--filename`, producing `multiqc_report_data/` | Fixed declared output path in module |

---

## What is NOT yet implemented

> **Sources listed per item below.**

| Item | Source | Notes |
|---|---|---|
| **StrainPhlAn** | *Microbiome workflow.docx.pdf* — client asked *"was this included?"*; [README](https://github.com/biobakery/biobakery_workflows/blob/master/readme.md) confirms it is **Super Task #4**, a standard step | ✅ **Implemented** — `SAMPLE2MARKERS` → `STRAINPHLAN_PRINT_CLADES` → `STRAINPHLAN` (fan-out per clade). Gated by `run_strainphlan = true`. |
| **PanPhlAn** | ~~biobakery_workflows original pipeline~~ — **correction: PanPhlAn is NOT part of the WMGX pipeline.** It is a separate biobakery tool. | Removed from scope. Not in WMGX. |
| **R / Bioconductor / Stats & Visualization** | *Microbiome workflow.docx.pdf* requirements table; [README](https://github.com/biobakery/biobakery_workflows/blob/master/readme.md) — `biobakery_workflows vis` and `biobakery_workflows stats` are separate downstream workflows | These are downstream analysis workflows (PCoA, heatmaps, MaAsLin2, HAllA). Not part of this Nextflow processing pipeline. |
| **Assembly** (MegaHit + Prokka + seqtk) | [README](https://github.com/biobakery/biobakery_workflows/blob/master/readme.md) — `--run-assembly` flag, explicitly marked *"not run by default"* | Not requested in client doc; not implemented. See explanation below. |
| **Demultiplexing** | **Correction: demultiplexing is NOT part of WMGX.** It only appears in the 16S workflow. | Not applicable — input files are already demultiplexed. |
| **Full end-to-end validation** | Current test run status | MetaPhlAn → HUMAnN → MultiQC not yet confirmed on a complete run. Only single-sample (`Zymo2`) tested so far. |
| **Multi-sample testing** | Current test run status | Pipeline designed for cohort runs; only one sample tested to date. |

---

## Why certain steps were not implemented

### PanPhlAn (gene-based strain profiling)

> **Correction:** After verifying the [biobakery_workflows README](https://github.com/biobakery/biobakery_workflows/blob/master/readme.md), PanPhlAn is **not part of the WMGX pipeline**. It was incorrectly listed earlier. The WMGX Super Tasks are: QC → Taxonomic profiling → Functional profiling → Strain profiling (StrainPhlAn) → Assembly (optional). PanPhlAn is a separate standalone biobakery tool outside the scope of this workflow.

**What PanPhlAn does (for reference):**
PanPhlAn profiles the functional gene content of individual microbial strains — mapping reads to a species-specific pangenome to identify which genes are present or absent. This answers *what a strain can do*, complementing StrainPhlAn which identifies *which strain is present*. It is not part of standard WMGX and is not in scope for this project.

---

### Assembly: MegaHit + Prokka

**What it does:**
The assembly step takes the quality-controlled (KneadData-processed) reads and assembles them *de novo* into longer contiguous sequences (contigs) that represent genomic regions of the microorganisms in the sample. The two tools work in sequence:

- **MegaHit** — a fast, memory-efficient *de novo* metagenome assembler. It takes paired-end reads and produces contigs, which are longer reconstructed genomic fragments. This is useful for discovering novel organisms or genes not present in reference databases.
- **Prokka** — annotates the assembled contigs, identifying and labelling predicted genes, coding sequences, rRNAs, and other genomic features. It produces standard annotation files (GFF, GenBank) that can be used for downstream functional analysis.

Together, assembly + annotation allows reference-free discovery — finding what is in the sample without relying on existing databases like ChocoPhlAn or UniRef.

**Why not implemented:**
- Not listed in the client requirements document (*Microbiome workflow.docx.pdf*) — the client's requested outputs (taxonomic profiles, gene families, pathway abundances) are all reference-based and do not require assembly
- Assembly is computationally very expensive: MegaHit for a typical metagenome sample requires 50–200 GB of RAM and several hours of CPU time, significantly increasing cost on AWS HealthOmics
- The reference-based approach (MetaPhlAn + HUMAnN) already covers the client's analytical goals
- Can be added as an optional `--run-assembly` flag in a future iteration if the client requests novel gene discovery or pangenome analysis

---

## Source summary for "not implemented" items

| Item | Why not implemented | Source confirming it was out of scope |
|---|---|---|
| StrainPhlAn | ✅ Implemented — `SAMPLE2MARKERS` → `STRAINPHLAN_PRINT_CLADES` → `STRAINPHLAN`; gated by `run_strainphlan = true` | *Microbiome workflow.docx.pdf* asked about it; [README](https://github.com/biobakery/biobakery_workflows/blob/master/readme.md) confirms it is Super Task #4 |
| PanPhlAn | **Not part of WMGX pipeline** — was incorrectly listed earlier | Verified against [biobakery_workflows README](https://github.com/biobakery/biobakery_workflows/blob/master/readme.md) |
| R / Bioconductor / Vis & Stats workflows | Downstream visualization and statistical analysis — separate workflows (`vis`, `stats`) not part of processing pipeline | [README](https://github.com/biobakery/biobakery_workflows/blob/master/readme.md) describes `vis` and `stats` as separate workflows |
| Assembly (MegaHit + Prokka + seqtk) | Not in client requirements; explicitly marked *"not run by default"* in original; high compute cost | [README](https://github.com/biobakery/biobakery_workflows/blob/master/readme.md): `--run-assembly` flag; not in *Microbiome workflow.docx.pdf* |
| Demultiplexing | **Not part of WMGX** — only in 16S workflow; input files already demultiplexed | Verified against [biobakery_workflows README](https://github.com/biobakery/biobakery_workflows/blob/master/readme.md) |
