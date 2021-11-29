#!/usr/bin/env nextflow

nextflow.enable.dsl=2

/*
Important (25.11.21):

run our philosopher-msfragger pipeline much more like FragPipe.
*/


process WORKSPACE {
    
    label 'philosopher'

    output:
    val 'tubel'

    script:
    """
    # initialize philosopher workspace in workspace
    cd ${projectDir}
    philosopher workspace --clean
    philosopher workspace --init
    """

}

process DATABASE {

    label 'philosopher'
    
    publishDir "${params.outDir}/database", mode: 'copy'

    input:
    val workspace
    path db

    output:
    path '*.fas'

    script:
    """
    workd=\$(pwd)

    # initialize philosopher in current wd and run command
    # mv ${projectDir}/.meta . 
    # philosopher workspace --init
    # philosopher database --custom ${db} --contam
    # mv .meta ${projectDir}

    cd ${projectDir}
    # philosopher workspace --init
    philosopher database --custom ${db} --contam
    
    cp ${projectDir}/*.fas \$workd
    """

}

process GENERATEPARAMS {

    label 'msfragger'

    publishDir "${params.outDir}/generateparams", mode: 'copy'

    input:
    path db
    
    output:
    path 'closed_fragger.params'

    script:
    """
    java -jar /MSFragger.jar --config

    cp closed_fragger.params ${projectDir}
    """

}

process CHANGEFILE {

    publishDir "${params.outDir}/changefile", mode: 'copy'

    input:
    path db
    path closed_fragger
    
    output:
    path 'closed_fragger.params'

    script:
    """
    python ${projectDir}/change_file.py ${db} ${closed_fragger}

    cp closed_fragger.params ${projectDir}
    """

}

process MSFRAGGER {

    label "msfragger"

    publishDir "${params.outDir}/msfragger/", mode: 'copy'

    input:
    path mzML_file
    path closed_fragger
    path db_file

    output:
    path '*.pepXML'

    /*
    MSFragger is doing some stupid stuff again: it outputs the .pepXML file right next to the mzML file. So, the data files must absolutely just plainly be in the workspace directory.

    So, I devised a strategy: I move the mzML files into the directory where msfragger nextflow is working on, so I am sure that the pepXML files will be output right in the work directory. After this step, I will move the mzML files back into the workspace.
    */
    
    script:
    if( params.fragger_mode == "local" )
        """
	workd=\$(pwd)

	# try to skip computation-heavy steps to make the pipeline run faster
        # execute MSFragger on the mzML file (output will be located in this work dir)
        # java -Xmx${params.fragger_ram}g -jar ${projectDir}/MSFragger/MSFragger.jar ${closed_fragger} ${mzML_file}

        cd ${projectDir}
        java -Xmx${params.fragger_ram}g -jar ${projectDir}/MSFragger/MSFragger.jar ${closed_fragger} ${mzML_file} 2> msfragger.out
        
	cp *.pepXML \$workd
        """

    else if( params.fragger_mode == "docker" )
        """
	workd=\$(pwd)

        # execute MSFragger on the mzML file (output will be located in this work dir)
        # java -Xmx${params.fragger_ram}g -jar /MSFragger.jar ${closed_fragger} ${mzML_file}

        cd ${projectDir}
        java -Xmx${params.fragger_ram}g -jar /MSFragger.jar ${closed_fragger} ${mzML_file} 2> msfragger.out
        
	cp *.pepXML \$workd
        """

}

process PEPTIDEPROPHET {
    
    label "philosopher"

    publishDir "${params.outDir}/peptideprophet", mode: 'copy'
       
    input:
    path db
    path pepXML
    
    output:
    path "*.pep.xml"
    
    script:
    """
    workd=\$(pwd)
    #mv ${projectDir}/.meta .
    #philosopher peptideprophet --combine --database ${db} --decoy rev_ --ppm --accmass --expectscore --decoyprobs --nonparam ${pepXML}
    #mv .meta ${projectDir}

    cd ${projectDir}
    philosopher peptideprophet --combine --database ${db} --decoy rev_ --ppm --accmass --expectscore --decoyprobs --nonparam ${pepXML} 2> peptideprophet.out
    
    cp ${projectDir}/interact.pep.xml \$workd
    """

}

process PROTEINPROPHET {
    
    label "philosopher"

    publishDir "${params.outDir}/proteinprophet", mode: 'copy'
       
    input:
    path pepxml
    
    output:
    path "*.prot.xml"
     
    script:
    """
    workd=\$(pwd)

    #mv ${projectDir}/.meta .
    #philosopher proteinprophet ${pepxml}
    #mv .meta ${projectDir}

    cd ${projectDir}
    philosopher proteinprophet ${pepxml} 2> proteinprophet.out

    cp ${projectDir}/interact.prot.xml \$workd
    """
    
    /*
    if( params.skip_proteinprophet == true )
        """

        """

    else if( params.skip_proteinprophet == false )
        """


        """

    */

}

process FILTERANDFDR {
    
    label "philosopher"

    publishDir "${params.outDir}/filterandfdr", mode: 'copy'

    input:
    path pepxml
    path protXML

    output:
    //path 'filterandfdr.out'
    val 'filterandfdr'
 
    script:
    """
    #mv ${projectDir}/.meta .
    #philosopher filter --sequential --razor --picked --tag rev_ --pepxml ${pepxml} --protxml ${protXML} 2> filterandfdr.out
    #mv .meta ${projectDir}

    cd ${projectDir}
    philosopher filter --sequential --razor --picked --tag rev_ --pepxml ${pepxml} --protxml ${protXML} 2> filterandfdr.out
    
    """

}

process QUANTIFY {

    label "philosopher"

    publishDir "${params.outDir}/quantify", mode: 'copy'

    input:
    val filterandfdr

    output:
    //path 'freequant.out'
    val 'freequant'

    script:
    """
    # rsync -av --exclude=work --exclude=results --exclude=MSFragger ${projectDir}/. .
    # philosopher freequant --dir . 2> freequant.out

    cd ${projectDir}
    philosopher freequant --dir . 2> freequant.out
    """

}

process REPORT {
    
    label "philosopher"

    publishDir "${params.outDir}/report", mode: 'copy'

    input:
    //path protXML
    val freequant

    output:
    //path 'report.out'
    val 'report'
 
    script:
    """
    # rsync -av --exclude=work --exclude=results --exclude=MSFragger ${projectDir}/. .
    # philosopher report --msstats 2> report.out

    cd ${projectDir}
    philosopher report --msstats 2> report.out
    """

}


workflow {

    input_ch = Channel.fromPath(params.input)
    input_ch.view()
    db_ch = Channel.of(params.db)

    //

    workspace_obj = WORKSPACE()

    db_obj = DATABASE(workspace_obj, db_ch)

    params_obj = GENERATEPARAMS(db_obj)

    change_obj = CHANGEFILE(db_obj, params_obj)

    pepXML_obj = MSFRAGGER(input_ch.collect(), change_obj, db_obj)

    pepdotxml_obj = PEPTIDEPROPHET(db_obj, pepXML_obj)

    protXML_obj = PROTEINPROPHET(pepdotxml_obj)

    filter_obj = FILTERANDFDR(pepdotxml_obj, protXML_obj)
 
    quant_obj = QUANTIFY(filter_obj)

    report_obj = REPORT(quant_obj)
    report_obj.view()

}
