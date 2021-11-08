nextflow.enable.dsl=2


process DATABASE {
    
    label "philosopher"

    container 'prvst/philosopher:4.0.0'

    publishDir "${params.outDir}/database", mode: 'copy'
         
    input:
    val x

    output:
    file '*'
    
    script:
    """
    philosopher workspace --init
    philosopher database --id $x --contam --reviewed
    """
}

process CHANGEFILE {

    input:
    path db

    publishDir "${params.outDir}/changefile", mode: 'copy'
    
    output:
    path tubel_file

    script:
    """
    python ${params.parentDir}/change_file.py ${db} > tubel_file
    """

}

process MSFRAGGER {

    label "msfragger"
    
    //container 'singjust/msfragger:3.1.1'

    publishDir "${params.outDir}/msfragger", mode: 'copy'

    input:
    path mzML_file
    path db_file

    output:
    path '*.pepXML'

    script:
    """
    java -Xmx4g -jar ${params.parentDir}/MSFragger/MSFragger.jar ${db_file} ${mzML_file}
    """
}

process PEPTIDEPROPHET {
    
    label "philosopher"

    container 'prvst/philosopher:4.0.0'

    publishDir "${params.outDir}/peptideprophet", mode: 'copy'
       
    input:
    path db
    path pepXML 
    
    output:
    path "interact-${params.input_noext}.pep.xml"
    
    
    script:
    """
    philosopher workspace --init
    philosopher peptideprophet --database ${db} --decoy rev_ --ppm --accmass --expectscore --decoyprobs --nonparam ${pepXML} 
    """
}

process PROTEINPROPHET {
    
    label "philosopher"

    container 'prvst/philosopher:4.0.0'

    publishDir "${params.outDir}/proteinprophet", mode: 'copy'
       
    input:
    path pepxml
    
    output:
    path '*.prot.xml'
     
    script:
    """
    philosopher workspace --init
    philosopher proteinprophet ${pepxml}
    """
}

process FILTERANDFDR {
    
    label "philosopher"

    container 'prvst/philosopher:4.0.0'

    publishDir "${params.outDir}/filterandfdr", mode: 'copy'
       
    input:
    path pepxml
    path protXML
     
    script:
    """
    philosopher workspace --init
    philosopher filter --sequential --razor --picked --tag rev_ --pepxml ${pepxml} --protxml ${protXML}
    """
}



workflow {
    
    params.input_file = "001_TPP7-21_C19.mzML"
    params.input_noext = "001_TPP7-21_C19"
    params.input = "${projectDir}/${params.input_file}"
    input_ch = Channel.fromPath(params.input)
    params.outDir = "results"
    params.parentDir = "/Users/noepozzan/Documents/unibas/nesvilab"
    params.proteome_ID = "UP000000589"
    ID_ch = Channel.of(params.proteome_ID)


    db_obj = DATABASE(ID_ch)
    params_obj = CHANGEFILE(db_obj)
    pepXML_obj = MSFRAGGER(input_ch, params_obj)
    pepdotxml_obj = PEPTIDEPROPHET(db_obj, pepXML_obj)
    protXML_obj = PROTEINPROPHET(pepdotxml_obj)
    FILTERANDFDR(pepdotxml_obj, protXML_obj)



}