nextflow.enable.dsl=2

include { GUNZIP as GUNZIP_TARGET_ASSEMBLY  } from '../modules/nf-core/gunzip'
include { GUNZIP as GUNZIP_TE_LIBRARY       } from '../modules/nf-core/gunzip'
include { FASTA_VALIDATE                    } from '../modules/local/fasta_validate'
include { REPEATMASKER                      } from '../modules/kherronism/repeatmasker'

include { PERFORM_EDTA_ANNOTATION           } from '../subworkflows/local/perform_edta_annotation'

include { validateParams                    } from '../modules/local/validate_params'

validateParams(params)

workflow PAN_GENE {

    // Versions
    Channel.empty()
    | set { ch_versions }
    
    // GUNZIP: target_assemblies
    Channel.fromList(params.target_assemblies)
    | map { tag, filePath ->
        [[id:tag], file(filePath, checkIfExists: true)]
    }
    | branch { meta, file ->
        gz: "$file".endsWith(".gz")
        rest: !"$file".endsWith(".gz")
    }
    | set { ch_target_assemblies }

    GUNZIP_TARGET_ASSEMBLY(
        ch_target_assemblies.gz
    )
    .gunzip
    | mix(
        ch_target_assemblies.rest
    )
    | set { ch_gunzip_target_assemblies }

    ch_versions.mix(GUNZIP_TARGET_ASSEMBLY.out.versions)
    | set { ch_versions }

    // FASTA_VALIDATE
    FASTA_VALIDATE(ch_gunzip_target_assemblies)
    .valid_fasta
    | set { ch_validated_target_assemblies }

    ch_versions.mix(FASTA_VALIDATE.out.versions)
    | set { ch_versions }

    // GUNZIP: te_libraries
    Channel.fromList(params.te_libraries)
    | map { tag, filePath ->
        [[id:tag], file(filePath, checkIfExists: true)]
    }
    | branch { meta, file ->
        gz: "$file".endsWith(".gz")
        rest: !"$file".endsWith(".gz")
    }
    | set { ch_te_libraries }

    GUNZIP_TE_LIBRARY(
        ch_te_libraries.gz
    )
    .gunzip
    | mix(
        ch_te_libraries.rest
    )
    | set { ch_gunzip_te_libraries }

    ch_versions.mix(GUNZIP_TE_LIBRARY.out.versions)
    | set { ch_versions }

    // PERFORM_EDTA_ANNOTATION
    ch_validated_target_assemblies
    | join(
        ch_gunzip_te_libraries, remainder: true
    )
    | filter { meta, assembly, teLib ->
        teLib == null
    }
    | map {[it[0], it[1]]}
    | PERFORM_EDTA_ANNOTATION

    ch_versions.mix(PERFORM_EDTA_ANNOTATION.out.versions)
    | set { ch_versions }
    
    // REPEATMASKER
    ch_validated_target_assemblies
    | join(
        PERFORM_EDTA_ANNOTATION.out.te_lib_fasta.mix(ch_gunzip_te_libraries)
    )
    | set { ch_assemblies_n_te_libs }

    REPEATMASKER(
        ch_assemblies_n_te_libs.map {meta, assembly, te_lib -> [meta, assembly]},
        ch_assemblies_n_te_libs.map {meta, assembly, te_lib -> te_lib},
    )
    .fasta_masked
    | view
}