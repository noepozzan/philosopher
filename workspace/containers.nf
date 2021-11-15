#!/usr/bin/env nextflow

nextflow.enable.dsl=2

/*
add custom file and database to msfragger and database
*/


process WORKSPACE {
	
	label 'philosopher'

	output:
	val 'workspace'

	script:
	"""
	cd ${projectDir}
	philosopher workspace --init
	"""

}

process DATABASE {

	label 'philosopher'
	
	publishDir "${params.outDir}/database", mode: 'copy'

	input:
	val workspace
	val ID

	output:
	path '*'

	script:
	"""
	# save work directory where nf works on
	workd=\$(pwd)
	# echo \$workd
	# initialize philosopher in current wd and run command
	philosopher workspace --init
	philosopher database --id ${ID} --contam --reviewed
	# copy philosopher output to folder in project workspace
	# cp -a \$workd/. ${params.outDir}/database
	# execute the same command in workspace for philosopher to run properly
	cd ${projectDir}
	philosopher database --id ${ID} --contam --reviewed
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

    input:
    path db
    path closed_fragger

    publishDir "${params.outDir}/changefile", mode: 'copy'
    
    output:
    path 'closed_fragger.params'

    script:
    """
    python ${projectDir}/change_file.py ${db} ${closed_fragger}
    cp closed_fragger.params ${projectDir}
    """

}

process MSFRAGGER {

    //label "msfragger"

    publishDir "${params.outDir}/msfragger", mode: 'copy'

    input:
    path mzML_file
    path closed_fragger
    path db_file

    output:
    path '*.pepXML'

    script:
    """
    echo $mzML_file
    java -Xmx${params.fragger_RAM}g -jar ${projectDir}/MSFragger/MSFragger.jar ${closed_fragger} ${mzML_file}
    cd ${projectDir}
    java -Xmx${params.fragger_RAM}g -jar ${projectDir}/MSFragger/MSFragger.jar ${closed_fragger} ${mzML_file}
    """

}

process PEPTIDEPROPHET {
    
    label "philosopher"

    publishDir "${params.outDir}/peptideprophet", mode: 'copy'
       
    input:
    path db
    path pepXML 
    
    output:
    path "interact-*.pep.xml"
    
    
    script:
    """
    echo $pepXML
    # initalise philosopher workspace in nextflow work directory and execute respective command
	philosopher workspace --init
	philosopher peptideprophet --database ${db} --decoy rev_ --ppm --accmass --expectscore --decoyprobs --nonparam ${pepXML}
	# execute command in workspace (project directory)
	cd ${projectDir}
	philosopher peptideprophet --database ${db} --decoy rev_ --ppm --accmass --expectscore --decoyprobs --nonparam ${pepXML}
    """

}

process PROTEINPROPHET {
    
    label "philosopher"

    publishDir "${params.outDir}/proteinprophet", mode: 'copy'
       
    input:
    path pepxml
    
    output:
    path '*.prot.xml'
     
    script:
    """
    echo $pepxml
	philosopher workspace --init
    philosopher proteinprophet ${pepxml}
	cd ${projectDir}
    philosopher proteinprophet ${pepxml}
    """

}

process FILTERANDFDR {
    
    label "philosopher"

    publishDir "${params.outDir}/filterandfdr", mode: 'copy'
       
    input:
    path pepxml
    path protXML

    output:
    path '*'
     
    script:
    """
    echo $pepxml
    echo $protXML
    rsync -aP --exclude=work --exclude=results ${projectDir}/. .
    philosopher filter --sequential --razor --picked --tag rev_ --pepxml ${pepxml} --protxml ${protXML}
	cd ${projectDir}
    philosopher filter --sequential --razor --picked --tag rev_ --pepxml ${pepxml} --protxml ${protXML}
    """

}

process QUANTIFY {
    
    label "philosopher"

    publishDir "${params.outDir}/quantify", mode: 'copy'

    input:
    path filter

    output:
    path '*'
    
    script:
    """
	rsync -aP --exclude=work --exclude=results ${projectDir}/. .
	philosopher freequant --dir .
	cd ${projectDir}
	philosopher freequant --dir .
    """

}

process REPORT {
    
    label "philosopher"

    publishDir "${params.outDir}/report", mode: 'copy'

    input:
    path quant

    output:
    path '*'
     
    script:
    """
    rsync -aP --exclude=work --exclude=results ${projectDir}/. .
    philosopher report
	cd ${projectDir}
    philosopher report
    """

}

/*
command to be executed from workspace directory: nextflow run containers.nf -profile docker -with-report -with-trace -with-timeline -with-dag dag.png

The msfragger container doesn't have ps installed, so it is not possible to run this pipeline with the -with-report option. A possible solution is suggested on https://github.com/replikation/What_the_Phage/issues/89.
*/

workflow {

	input_ch = Channel.fromPath(params.input)
	ID_ch = Channel.of(params.proteome_ID)

    workspace_obj = WORKSPACE()
	db_obj = DATABASE(workspace_obj, ID_ch)
	params_obj = GENERATEPARAMS(db_obj)
	change_obj = CHANGEFILE(db_obj, params_obj)
	pepXML_obj = MSFRAGGER(input_ch, change_obj, db_obj)
	pepXML_obj.view()
	pepdotxml_obj = PEPTIDEPROPHET(db_obj, pepXML_obj)
	pepdotxml_obj.view()
	protXML_obj = PROTEINPROPHET(pepdotxml_obj)
	protXML_obj.view()
	filter_obj = FILTERANDFDR(pepdotxml_obj, protXML_obj)
	filter_obj.view()
	quant_obj = QUANTIFY(filter_obj)
	report_obj = REPORT(quant_obj)

}
