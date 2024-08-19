/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { PREPARE_ASSEMBLY                      } from '../subworkflows/local/prepare_assembly'
include { PREPROCESS_RNASEQ                     } from '../subworkflows/local/preprocess_rnaseq'
include { ALIGN_RNASEQ                          } from '../subworkflows/local/align_rnaseq'
include { PREPARE_EXT_PROTS                     } from '../subworkflows/local/prepare_ext_prots'
include { FASTA_BRAKER3                         } from '../subworkflows/local/fasta_braker3'
include { FASTA_LIFTOFF                         } from '../subworkflows/local/fasta_liftoff'
include { PURGE_BRAKER_MODELS                   } from '../subworkflows/local/purge_braker_models'
include { GFF_MERGE_CLEANUP                     } from '../subworkflows/local/gff_merge_cleanup'
include { GFF_EGGNOGMAPPER                      } from '../subworkflows/local/gff_eggnogmapper'
include { PURGE_NOHIT_MODELS                    } from '../subworkflows/local/purge_nohit_models'
include { GFF_STORE                             } from '../subworkflows/local/gff_store'
include { FASTA_ORTHOFINDER                     } from '../subworkflows/local/fasta_orthofinder'
include { FASTA_GXF_BUSCO_PLOT                  } from '../subworkflows/gallvp/fasta_gxf_busco_plot/main'
include { CAT_CAT as SAVE_MARKED_GFF3           } from '../modules/nf-core/cat/cat/main'
include { softwareVersionsToYAML                } from '../subworkflows/nf-core/utils_nfcore_pipeline'

include { GXF_FASTA_AGAT_SPADDINTRONS_SPEXTRACTSEQUENCES } from '../subworkflows/gallvp/gxf_fasta_agat_spaddintrons_spextractsequences/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow GENEPAL {

    take:
    target_assembly
    tar_assm_str
    is_masked
    te_library
    braker_annotation
    braker_ex_asm_str
    rna_fq
    rna_bam
    rna_bam_by_assembly
    sortmerna_fastas
    ext_prot_fastas
    liftoff_fasta
    liftoff_gff
    tsebra_config
    orthofinder_pep


    // Versions channel
    ch_versions                 = Channel.empty()

    // SUBWORKFLOW: PREPARE_ASSEMBLY
    PREPARE_ASSEMBLY(
        ch_target_assembly,
        ch_te_library,
        params.repeat_annotator,
        ch_braker_ex_asm_str,
        ch_is_masked
    )

    ch_valid_target_assembly    = PREPARE_ASSEMBLY.out.target_assemby
    ch_masked_target_assembly   = PREPARE_ASSEMBLY.out.masked_target_assembly
    ch_target_assemby_index     = PREPARE_ASSEMBLY.out.target_assemby_index
    ch_versions                 = ch_versions.mix(PREPARE_ASSEMBLY.out.versions)

    // SUBWORKFLOW: PREPROCESS_RNASEQ
    PREPROCESS_RNASEQ(
        ch_rna_fq,
        ch_tar_assm_str,
        ch_braker_ex_asm_str,
        params.skip_fastqc,
        params.skip_fastp,
        params.save_trimmed,
        params.min_trimmed_reads,
        params.remove_ribo_rna,
        ch_sortmerna_fastas
    )

    ch_trim_reads               = PREPROCESS_RNASEQ.out.trim_reads
    ch_reads_target             = PREPROCESS_RNASEQ.out.reads_target
    ch_versions                 = ch_versions.mix(PREPROCESS_RNASEQ.out.versions)

    // SUBWORKFLOW: ALIGN_RNASEQ
    ALIGN_RNASEQ(
        ch_reads_target,
        ch_trim_reads,
        ch_rna_bam_by_assembly,
        ch_target_assemby_index,
    )

    ch_rnaseq_bam               = ALIGN_RNASEQ.out.bam
    ch_versions                 = ch_versions.mix(ALIGN_RNASEQ.out.versions)

    // MODULE: PREPARE_EXT_PROTS
    PREPARE_EXT_PROTS(
        ch_ext_prot_fastas
    )

    ch_ext_prots_fasta          = PREPARE_EXT_PROTS.out.ext_prots_fasta
    ch_versions                 = ch_versions.mix(PREPARE_EXT_PROTS.out.versions)

    // SUBWORKFLOW: FASTA_BRAKER3
    FASTA_BRAKER3(
        ch_masked_target_assembly,
        ch_braker_ex_asm_str,
        ch_rnaseq_bam,
        ch_ext_prots_fasta,
        ch_braker_annotation
    )

    ch_braker_gff3              = FASTA_BRAKER3.out.braker_gff3
    ch_braker_hints             = FASTA_BRAKER3.out.braker_hints
    ch_versions                 = ch_versions.mix(FASTA_BRAKER3.out.versions)

    // SUBWORKFLOW: FASTA_LIFTOFF
    FASTA_LIFTOFF(
        ch_valid_target_assembly,
        ch_liftoff_fasta,
        ch_liftoff_gff,
        params.filter_liftoff_by_hints,
        ch_braker_hints,
        ch_tsebra_config,
        params.allow_isoforms
    )

    ch_liftoff_gff3             = FASTA_LIFTOFF.out.gff3
    ch_versions                 = ch_versions.mix(FASTA_LIFTOFF.out.versions)

    // SUBWORKFLOW: PURGE_BRAKER_MODELS
    PURGE_BRAKER_MODELS(
        ch_braker_gff3,
        ch_braker_hints,
        ch_liftoff_gff3,
        ch_tsebra_config,
        params.allow_isoforms
    )

    ch_braker_purged_gff        = PURGE_BRAKER_MODELS.out.braker_purged_gff
    ch_versions                 = ch_versions.mix(PURGE_BRAKER_MODELS.out.versions)

    // SUBWORKFLOW: GFF_MERGE_CLEANUP
    GFF_MERGE_CLEANUP(
        ch_braker_purged_gff,
        ch_liftoff_gff3
    )

    ch_merged_gff               = GFF_MERGE_CLEANUP.out.gff
    ch_versions                 = ch_versions.mix(GFF_MERGE_CLEANUP.out.versions)

    // SUBWORKFLOW: GFF_EGGNOGMAPPER
    GFF_EGGNOGMAPPER(
        ch_merged_gff,
        ch_valid_target_assembly,
        params.eggnogmapper_db_dir,
    )

    ch_eggnogmapper_hits        = GFF_EGGNOGMAPPER.out.eggnogmapper_hits
    ch_eggnogmapper_annotations = GFF_EGGNOGMAPPER.out.eggnogmapper_annotations
    ch_versions                 = ch_versions.mix(GFF_EGGNOGMAPPER.out.versions)

    // SUBWORKFLOW: PURGE_NOHIT_MODELS
    PURGE_NOHIT_MODELS(
        ch_merged_gff,
        ch_eggnogmapper_hits,
        params.eggnogmapper_purge_nohits && params.eggnogmapper_db_dir
    )

    ch_purged_gff               = PURGE_NOHIT_MODELS.out.purged_gff
    ch_versions                 = ch_versions.mix(PURGE_NOHIT_MODELS.out.versions)

    // SUBWORKFLOW: GFF_STORE
    GFF_STORE(
        ch_purged_gff,
        ch_eggnogmapper_annotations,
        ch_valid_target_assembly,
        params.eggnogmapper_db_dir
    )

    ch_final_gff                = GFF_STORE.out.final_gff
    ch_final_proteins           = GFF_STORE.out.final_proteins
    ch_versions                 = ch_versions.mix(GFF_STORE.out.versions)

    // SUBWORKFLOW: FASTA_ORTHOFINDER
    FASTA_ORTHOFINDER(
        ch_final_proteins,
        ch_orthofinder_pep
    )

    ch_versions                 = ch_versions.mix(FASTA_ORTHOFINDER.out.versions)

    // SUBWORKFLOW: FASTA_GXF_BUSCO_PLOT
    ch_busco_fasta              = params.busco_skip
                                ? Channel.empty()
                                : ch_valid_target_assembly

    ch_busco_gff                = params.busco_skip
                                ? Channel.empty()
                                : ch_final_gff

    FASTA_GXF_BUSCO_PLOT(
        ch_busco_fasta,
        ch_busco_gff,
        'genome',
        params.busco_lineage_datasets?.tokenize(' '),
        [], // val_busco_lineages_path
        [] // val_busco_config
    )

    ch_versions                 = ch_versions.mix(FASTA_GXF_BUSCO_PLOT.out.versions)

    // SUBWORKFLOW: GXF_FASTA_AGAT_SPADDINTRONS_SPEXTRACTSEQUENCES
    GXF_FASTA_AGAT_SPADDINTRONS_SPEXTRACTSEQUENCES(
        ch_final_gff,
        ch_valid_target_assembly
    )

    ch_splicing_marked_gff3     = GXF_FASTA_AGAT_SPADDINTRONS_SPEXTRACTSEQUENCES.out.marked_gff3
    ch_versions                 = ch_versions.mix(GXF_FASTA_AGAT_SPADDINTRONS_SPEXTRACTSEQUENCES.out.versions)

    // MODULE: CAT_CAT as SAVE_MARKED_GFF3
    SAVE_MARKED_GFF3 ( ch_splicing_marked_gff3 )

    // Collate and save software versions
    ch_versions                 = ch_versions
                                | unique
                                | map { yml ->
                                    if ( yml ) { yml }
                                }

    ch_versions_yml             = softwareVersionsToYAML(ch_versions)
                                | collectFile(
                                    storeDir: "${params.outdir}/pipeline_info",
                                    name: 'software_versions.yml',
                                    sort: true,
                                    newLine: true,
                                    cache: false
                                )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
