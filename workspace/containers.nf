#!/usr/bin/env nextflow

nextflow.enable.dsl=2

/*
How about just running all of the files in one process?
That way, also only one philosopher container would be started and all the metadata (.meta) should be available for the downstream steps. (btw, this is probably why the philosopher pipeline has to be run from one directory only)

-> Funny observation:
I was running philosopher in its container and then called the MSFragger command line tool. The process did not work twice, but then finally after the third try returned a pepXML file.
(The process was running fine and then just said killed.)


Run this nextflow script with the argument -profile docker to have your local environment communicating with the container
*/

process WORKSPACE {
	
	container 'prvst/philosopher:4.0.0'

	script:
	"""
	cd ${projectDir}
	philosopher workspace --init
	"""

}


process DATABASE {
	
	container 'prvst/philosopher:4.0.0'

	publishDir "${params.outDir}/database", mode: 'copy'

	input:
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

	container 'singjust/msfragger:3.1.1'

	publishDir "${params.outDir}/generateparams", mode: 'copy'

    input:
    path db
    
    output:
    path 'closed_fragger.params'

    script:
    """
    workd=\$(pwd)
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
    python ${params.parentDir}/change_file.py ${db} ${closed_fragger}
    cp closed_fragger.params ${projectDir}
    """

}

process MSFRAGGER {

    //label "msfragger"
    
    //container 'singjust/msfragger:3.1.1'

    publishDir "${params.outDir}/msfragger", mode: 'copy'

    input:
    path mzML_file
    path closed_fragger
    path db_file

    output:
    path '*.pepXML'

    script:
    """
    workd=\$(pwd)
    java -Xmx${params.fragger_RAM}g -jar ${params.parentDir}/MSFragger/MSFragger.jar ${closed_fragger} ${mzML_file}
    cd ${projectDir}
    java -Xmx${params.fragger_RAM}g -jar ${params.parentDir}/MSFragger/MSFragger.jar ${closed_fragger} ${mzML_file}
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
    # save work directory where nf works on
	workd=\$(pwd)
	# echo \$workd
	# initialize philosopher in current wd and run command
	philosopher workspace --init
	philosopher peptideprophet --database ${db} --decoy rev_ --ppm --accmass --expectscore --decoyprobs --nonparam ${pepXML}
	# copy philosopher output to folder in project workspace
	# cp -a \$workd/. ${projectDir}/peptideprophet
	# execute the same command in workspace for philosopher to run properly
	cd ${projectDir}
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
	cd ${projectDir}
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
	#philosopher workspace --init
    #philosopher filter --sequential --razor --picked --tag rev_ --pepxml ${pepxml} --protxml ${protXML}
	cd ${projectDir}
    philosopher filter --sequential --razor --picked --tag rev_ --pepxml ${pepxml} --protxml ${protXML}

    """
}

/*
Inside of the container:
I might try to pass in the whole workspace directory into this process and then capturing the output
like:
workd=\${pwd}
cp -a ${projectDir} \$workd
*/
process QUANTIFY {
    
    label "philosopher"

    container 'prvst/philosopher:4.0.0'

    publishDir "${params.outDir}/quantify", mode: 'copy'
    
    script:
    """
	#philosopher workspace --init
    #philosopher freequant --dir .
	cd ${projectDir}
    philosopher freequant --dir .
    """
}

process REPORT {
    
    label "philosopher"

    container 'prvst/philosopher:4.0.0'

    publishDir "${params.outDir}/report", mode: 'copy'
     
    script:
    """
    #philosopher workspace --init
    #philosopher report
	cd ${projectDir}
    philosopher report
    """
}

// command: nextflow run containers.nf -profile docker -with-report -with-trace -with-timeline -with-dag dag.png

workflow {

	params.input_file = "001_TPP7-21_C19.mzML"
    params.input_noext = "001_TPP7-21_C19"
    params.input = "${projectDir}/${params.input_file}"
    input_ch = Channel.fromPath(params.input)
    params.outDir = "/Users/noepozzan/Documents/unibas/nesvilab/workspace/results"
    params.parentDir = "/Users/noepozzan/Documents/unibas/nesvilab"
    params.proteome_ID = "UP000000589"
    ID_ch = Channel.of(params.proteome_ID)
    params.fragger_RAM = 4
	
	// this process has to have some logic to be executed first
	WORKSPACE()

	db_obj = DATABASE(ID_ch)
	db_obj.view()
	params_obj = GENERATEPARAMS(db_obj)
	params_obj.view()
	change_obj = CHANGEFILE(db_obj, params_obj)
	change_obj.view()
	pepXML_obj = MSFRAGGER(input_ch, params_obj, db_obj)
	pepXML_obj.view()
	pepdotxml_obj = PEPTIDEPROPHET(db_obj, pepXML_obj)
	pepdotxml_obj.view()
	protXML_obj = PROTEINPROPHET(pepdotxml_obj)
	protXML_obj.view()

	filter_obj = FILTERANDFDR(pepdotxml_obj, protXML_obj)
	
	//QUANTIFY()
	//REPORT()




}
