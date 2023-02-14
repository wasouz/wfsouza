#!/bin/bash
version='get-k8s-info v1.0.6'

# SAS INSTITUTE INC. IS PROVIDING YOU WITH THE COMPUTER SOFTWARE CODE INCLUDED WITH THIS AGREEMENT ("CODE") 
# ON AN "AS IS" BASIS, AND AUTHORIZES YOU TO USE THE CODE SUBJECT TO THE TERMS HEREOF. BY USING THE CODE, YOU 
# AGREE TO THESE TERMS. YOUR USE OF THE CODE IS AT YOUR OWN RISK. SAS INSTITUTE INC. MAKES NO REPRESENTATION 
# OR WARRANTY, EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, WARRANTIES OF MERCHANTABILITY, FITNESS FOR 
# A PARTICULAR PURPOSE, NONINFRINGEMENT AND TITLE, WITH RESPECT TO THE CODE.
# 
# The Code is intended to be used solely as part of a product ("Software") you currently have licensed from 
# SAS Institute Inc. or one of its subsidiaries or authorized agents ("SAS"). The Code is designed to either 
# correct an error in the Software or to add functionality to the Software, but has not necessarily been tested. 
# Accordingly, SAS makes no representation or warranty that the Code will operate error-free. SAS is under no 
# obligation to maintain or support the Code.
# 
# Neither SAS nor its licensors shall be liable to you or any third party for any general, special, direct, 
# indirect, consequential, incidental or other damages whatsoever arising out of or related to your use or 
# inability to use the Code, even if SAS has been advised of the possibility of such damages.
#
# Except as otherwise provided above, the Code is governed by the same agreement that governs the Software. 
# If you do not have an existing agreement with SAS governing the Software, you may not use the Code.

# Initialize log file
touch /tmp/get-k8s-info.log
if [[ $? -ne 0 ]]; then 
    echo "ERROR: Unable to write log file '/tmp/get-k8s-info.log'"
    cleanUp 0
else
    logfile='/tmp/get-k8s-info.log'
    echo -e "$version\n$(date -u)\nCommand: ${0} ${@}\n" > $logfile
fi

function usage {
    echo Version: "$version"
    script=$(echo $0 | rev | cut -d '/' -f1 | rev)
    echo; echo "Usage: $script [OPTIONS]..."
    echo;
    echo "Capture information from a Viya deployment."
    echo;
    echo "  -t|--track      (Optional) SAS Tech Support track number"
    echo "  -n|--namespace  (Optional) Viya namespace"
    echo "  -p|--deploypath (Optional) Path of the viya \$deploy directory"
    echo "  -o|--out        (Optional) Path where the .tgz file will be created"
    echo "  -l|--logs       (Optional) Capture logs from pods using a comma separated list of label selectors"
    echo "  -d|--debugtags  (Optional) Enable specific debug tags. Available values are: 'cas', 'config', 'nginx' and 'postgres'"
    echo "  -s|--sastsdrive (Optional) Send the .tgz file to SASTSDrive through sftp."
    echo "                             Only use this option after you were authorized by Tech Support to send files to SASTSDrive for the track."
    echo;
    echo "Examples:"
    echo;
    echo "Run the script with no arguments for options to be prompted interactively"
    echo "  $ $script"
    echo;
    echo "You can also specify all options in the command line"
    echo "  $ $script --track 7613123123 --namespace viya-prod --deploypath /home/user/viyadeployment --out /tmp"
    echo;
    echo "Use the '--logs' and '--debugtags' options to collect logs and information from specific components"
    echo "  $ $script --logs 'sas-microanalytic-score,type=esp,workload.sas.com/class=stateful' --debugtags 'postgres,cas'"
    echo;
    echo "                                 By: Alexandre Gomes - August 17th 2022"
    echo "https://gitlab.sas.com/sbralg/tools-and-scripts/-/blob/main/get-k8s-info"
}
function version {
    echo "$version"
}

# Handle ctrl+c
trap cleanUp SIGINT
function cleanUp() {
    if [ -f $logfile ]; then 
        if [[ $1 -eq 1 || -z $1 ]]; then 
            if [[ -z $1 ]]; then echo -e "\nFATAL: The script was terminated unexpectedly." | tee -a $logfile; fi
            echo -e "\nScript log saved at: /tmp/get-k8s-info.log"
        else rm -f $logfile; fi
    fi
    if [ -d $TEMPDIR ]; then rm -rf $TEMPDIR; fi
    exit $1
}

# Check kubectl
if ! type kubectl > /dev/null 2>> $logfile; then
    echo;echo "ERROR: 'kubectl' not installed in PATH." | tee -a $logfile
    cleanUp 1
elif [ -z "$KUBECONFIG" ] && [ ! -f ~/.kube/config ]; then 
    echo;echo "ERROR: KUBECONFIG environment variable not set and no default config file available." | tee -a $logfile
    cleanUp 1
fi

# Initialize Variables
POSTGRES=false
CAS=false
NGINX=false
CONFIG=false
SASTSDRIVE=false

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help|--usage|-?)
      usage
      cleanUp 0
      ;;
    -v|--version)
      version
      cleanUp 0
      ;;
    -t|--track)
      TRACKNUMBER="$2"
      shift # past argument
      shift # past value
      ;;
    -n|--namespace)
      VIYA_NS="$2"
      shift # past argument
      shift # past value
      ;;
    -d|--debugtags)
      TAGS=$(echo "$2" | tr '[:upper:]' '[:lower:]')
      if [[ $TAGS =~ 'postgres' ]]; then POSTGRES=true;fi
      if [[ $TAGS =~ 'cas' ]]; then CAS=true;fi
      if [[ $TAGS =~ 'nginx' ]]; then NGINX=true;fi
      if [[ $TAGS =~ 'config' ]]; then CONFIG=true;fi
      shift # past argument
      shift # past value
      ;;
    -l|--logs)
      PODLOGS="$2"
      shift # past argument
      shift # past value
      ;;
    -p|--deploypath)
      DEPLOYPATH="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--out)
      OUTPATH="$2"
      shift # past argument
      shift # past value
      ;;
    -s|--sastsdrive)
      timeout 5 bash -c 'cat < /dev/null > /dev/tcp/sft.sas.com/22' > /dev/null 2>> $logfile
      if [ $? -ne 0 ]; then
          echo -e "WARNING: Connection to SASTSDrive not available. The script won't try to send the .tgz file to SASTSDrive.\n" | tee -a $logfile
      else SASTSDRIVE="true"; fi
      shift # past argument
      ;;
    -*|--*)
      usage
      echo -e "ERROR: Unknown option $1" | tee -a $logfile
      cleanUp 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

# Check TRACKNUMBER
if [ -z $TRACKNUMBER ]; then 
    if [ $SASTSDRIVE == 'true' ]; then
        read -p " -> SAS Tech Support track number (required): " TRACKNUMBER
    else
        read -p " -> SAS Tech Support track number (leave blank if not known): " TRACKNUMBER
        if [ -z $TRACKNUMBER ]; then TRACKNUMBER=7600000000; fi
    fi
fi
echo TRACKNUMBER: $TRACKNUMBER >> $logfile
if [ $(echo $TRACKNUMBER | egrep -c '^[0-9]{10}$') -ne 1 ]; then
    echo "ERROR: Invalid 10-digit track number" | tee -a $logfile
    cleanUp 1
fi

# Check DEPLOYPATH
if [ -z $DEPLOYPATH ]; then 
    read -p " -> Specify the path of the viya \$deploy directory ($(pwd)): " DEPLOYPATH
    if [ -z $DEPLOYPATH ]; then DEPLOYPATH=$(pwd)
    elif [ ${DEPLOYPATH::1} == '~' ]; then DEPLOYPATH=$HOME${DEPLOYPATH:1}
    elif [ ${DEPLOYPATH::2} == './' ]; then DEPLOYPATH=$(pwd)/${DEPLOYPATH:2}
    elif [ ${DEPLOYPATH::3} == '../' ]; then DEPLOYPATH=$(dirname $(pwd))/${DEPLOYPATH:3};fi
fi
echo DEPLOYPATH: $DEPLOYPATH >> $logfile
# Exit if deployment assets are not found
if [ $DEPLOYPATH != 'unavailable' ];then 
    if [[ ! -d $DEPLOYPATH/site-config || ! -f $DEPLOYPATH/kustomization.yaml ]]; then 
        echo ERROR: Deployment assets were not found inside the provided \$deploy path: $(echo -e "site-config/\nkustomization.yaml" | grep -E -v $(ls $DEPLOYPATH 2>> $logfile | grep "^site-config$\|^kustomization.yaml$" | tr '\n' '\|')^dummy$)  | tee -a $logfile
        echo -e "\nTo debug some issues, SAS Tech Support requires information collected from files within the \$deploy directory.\nIf you are unable to access the \$deploy directory at the moment, run the script again with '--deploypath unavailable'" | tee -a $logfile
        cleanUp 1
    else
        echo -e "INFO: Deployment assets were found in the provided \$deploy directory" | tee -a $logfile
    fi
else
    echo "WARNING: --deploypath set as 'unavailable'. Please note that SAS Tech Support may still require and request information from the \$deploy directory" | tee -a $logfile
fi

# Check VIYA_NS
if [ -z $VIYA_NS ]; then 
    namespaces=($(kubectl get cm --all-namespaces 2>> $logfile | grep deployment-metadata | awk '{print $1}' | sort | uniq))
    if [ ${#namespaces[@]} -gt 0 ]; then
        nsCount=0
        if [ ${#namespaces[@]} -gt 1 ]; then
            echo -e '\nNamespaces with a Viya deployment:\n' | tee -a $logfile
            for ns in "${namespaces[@]}"; do 
                echo "[$nsCount] ${namespaces[$nsCount]}" | tee -a $logfile
                nsCount=$[ $nsCount + 1 ]
            done
            echo;read -n 1 -p " -> Select the namespace where the information should be collected from: " nsCount;echo
            if [ ! ${namespaces[$nsCount]} ]; then
                echo -e "\nERROR: Option '$nsCount' invalid." | tee -a $logfile
                cleanUp 1
            fi
        fi
        VIYA_NS=${namespaces[$nsCount]}
        echo VIYA_NS: $VIYA_NS >> $logfile
        echo -e "INFO: Information will be collected from the '$VIYA_NS' namespace." | tee -a $logfile
    else
        echo "ERROR: A namespace was not provided and no Viya deployment was found in any namespace of the current kubernetes cluster. Is the KUBECONFIG file correct?" | tee -a $logfile
        cleanUp 1
    fi
else
    echo VIYA_NS: $VIYA_NS >> $logfile
    if [ $(kubectl get cm -n $VIYA_NS 2>> $logfile | grep -c deployment-metadata) -eq 0 ]; then
        echo "ERROR: A Viya deployment wasn't found in the '$VIYA_NS' namespace." | tee -a $logfile
        cleanUp 1
    fi
fi

# Check NGINX_NS
ingressns=($(kubectl get cm --all-namespaces 2>> $logfile | grep ingress-nginx-controller | awk '{print $1}' | sort | uniq))
if [ ${#ingressns[@]} -gt 0 ]; then
    ingNsCount=0
    if [ ${#ingressns[@]} -gt 1 ]; then
        echo -e '\nNamespaces with an Nginx instance:\n' | tee -a $logfile
        for ns in "${ingressns[@]}"; do 
            echo "[$ingNsCount] ${ingressns[$ingNsCount]}" | tee -a $logfile
            ingNsCount=$[ $ingNsCount + 1 ]
        done
        echo;read -n 1 -p " -> Select the namespace where the Nginx information should be collected from: " ingNsCount;echo
        if [ ! ${ingressns[$ingNsCount]} ]; then
            echo -e "\nERROR: Option '$ingNsCount' invalid." | tee -a $logfile
            cleanUp 1
        fi
    fi
    NGINX_NS=${ingressns[$ingNsCount]}
    echo NGINX_NS: $NGINX_NS >> $logfile
    echo -e "INFO: Nginx information will be collected from the '$NGINX_NS' namespace." | tee -a $logfile
else
    echo "WARNING: An Nginx Ingress Controller instance wasn't found in the current kubernetes cluster." | tee -a $logfile
    echo "WARNING: The script will continue without collecting nginx information." | tee -a $logfile
    NGINX=false
fi

# Check OUTPATH
if [ -z $OUTPATH ]; then 
    read -p " -> Specify the path where the script output file will be saved ($(pwd)): " OUTPATH
    if [ -z $OUTPATH ]; then OUTPATH=$(pwd)
    elif [ ${OUTPATH::1} == '~' ]; then OUTPATH=$HOME${OUTPATH:1}
    elif [ ${OUTPATH::2} == './' ]; then OUTPATH=$(pwd)/${OUTPATH:2}
    elif [ ${OUTPATH::3} == '../' ]; then OUTPATH=$(dirname $(pwd))/${OUTPATH:3};fi
fi
echo OUTPATH: $OUTPATH >> $logfile
if [ ! -d $OUTPATH ]; then 
    echo "ERROR: Output path '$OUTPATH' doesn't exist" | tee -a $logfile
    cleanUp 1
else
    touch $OUTPATH/T${TRACKNUMBER}.tgz 2>> $logfile
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to write output file '$OUTPATH/T${TRACKNUMBER}.tgz'." | tee -a $logfile
        cleanUp 1
    fi
fi
function addPod {
    for pod in $@; do
        if [ -z podCount ];then podCount=0;fi
        podList[$podCount]="$pod"
        podCount=$[ $podCount + 1 ]
    done
}
function addLabelSelector {
    for label in $@; do
        if [[ ! $label =~ "=" ]]; then label="app=$label" # Default label selector key is "app"
        elif [[ ${label:0-1} = "=" ]]; then label="${label%=}"; fi # Accept keys without values as label selectors
        pods=$(kubectl -n $VIYA_NS get pod -l "$label" 2>> $logfile | grep -v NAME | awk '{print $1}' | tr '\n' ' ')
        addPod $pods
    done
}
function removeSensitiveData {
    for file in $@; do
        echo "    - Removing sensitive data from ${file#*/*/*/}" | tee -a $logfile
        isSensitive='false'
        # If file contains Secrets
        if [ $(grep -c '^kind: Secret$' $file) -gt 0 ]; then
            secretStartLines=($(grep -n '^---$\|^kind: Secret$' $file | grep 'kind: Secret' -B1 | grep -v Secret | cut -d ':' -f1))
            secretEndLines=($(grep -n '^---$\|^kind: Secret$' $file | grep 'kind: Secret' -A1 | grep -v Secret | cut -d ':' -f1))
            sed -n 1,$[ ${secretStartLines[0]} -1 ]p $file > $file.parsed
            printf '%s\n' "---" >> $file.parsed
            i=0
            while [ $i -lt ${#secretStartLines[@]} ]
            do
                while IFS="" read -r p || [ -n "$p" ]
                do
                    if [[ $isSensitive == 'true' ]]; then
                        if [[ ${p::2} == '  ' ]]; then
                            printf '%s: %s\n' "${p%%:*}" '{{ sensitive data removed }}' >> $file.parsed
                        else
                            isSensitive='false'
                            if [ "${p}" != '---' ]; then printf '%s\n' "${p}" >> $file.parsed; fi
                        fi
                    else
                        if [ "${p}" != '---' ]; then printf '%s\n' "${p}" >> $file.parsed; fi
                        if grep -q '^data:\|^stringData:' <<< "$p"; then isSensitive='true'; fi
                    fi
                done < <(sed -n ${secretStartLines[i]},${secretEndLines[i]}p $file)
                i=$[ $i + 1 ]
                if [ $i -lt ${#secretStartLines[@]} ]; then printf '%s\n' "---" >> $file.parsed; fi
            done
            sed -n ${secretEndLines[-1]},\$p $file >> $file.parsed
        else
            while IFS="" read -r p || [ -n "$p" ]
            do
                if [ ${file##*.} == 'yaml' ]; then
                    if [[ "${p}" =~ ':' || "${p}" == '---' ]]; then
                        isSensitive='false'
                        # Check for Certificates or HardCoded Passwords
                        if [[ "${p}" =~ '-----BEGIN ' || $p =~ 'ssword: ' ]]; then
                            isSensitive='true'
                            printf '%s: %s\n' "${p%%:*}" '{{ sensitive data removed }}' >> $file.parsed
                        else
                            printf '%s\n' "${p}" >> $file.parsed
                        fi
                    # Print only if not sensitive
                    elif [ $isSensitive == 'false' ]; then
                        printf '%s\n' "${p}" >> $file.parsed
                    fi
                elif [ ${file##*/} == 'consul-config.out' ]; then
                    # New key
                    if [[ "${p}" =~ 'config/' ]]; then
                        isSensitive='false'
                        if [[ "${p}" =~ '-----BEGIN' || "${p}" =~ 'password=' ]]; then
                            isSensitive='true'
                            printf '%s=%s\n' "${p%%=*}" '{{ sensitive data removed }}' >> $file.parsed
                        elif [[ "${p}" =~ 'pwd=' ]] ;then
                            printf '%s%s%s\n' "${p%%pwd*}" 'pwd={{ sensitive data removed }};' "$(cut -d ';' -f2- <<< ${p##*pwd=})" >> $file.parsed
                        else
                            printf '%s\n' "${p}" >> $file.parsed
                        fi
                    elif [ $isSensitive == 'false' ]; then
                        printf '%s\n' "${p}" >> $file.parsed
                    fi
                fi
            done < $file
        fi
        rm -f $file
        mv $file.parsed $file
    done
}

TEMPDIR=$(mktemp -d)

echo "INFO: Capturing environment information..." | tee -a $logfile

echo "  - Kubernetes and Kustomize versions" | tee -a $logfile
kubectl version --short > $TEMPDIR/kubernetes.txt 2>> $logfile
cat $TEMPDIR/kubernetes.txt >> $logfile
kustomize version --short > $TEMPDIR/kustomize.txt 2>> $logfile
cat $TEMPDIR/kustomize.txt >> $logfile

if [ "$(kubectl -n $VIYA_NS get $(kubectl -n $VIYA_NS get cm -o name 2>> $logfile| grep sas-certframe-user-config | tail -1) -o=jsonpath='{.data.SAS_CERTIFICATE_GENERATOR}' 2>> $logfile)" == 'cert-manager' ]; then 
    echo "  - cert-manager version" | tee -a $logfile
    CERTMGR_NS=$(kubectl get deployment --all-namespaces 2>> $logfile | grep cert-manager | head -1 | awk '{print $1}')
    echo CERTMGR_NS: $CERTMGR_NS >> $logfile
    if [ ! -z $CERTMGR_NS ]; then
        kubectl -n $CERTMGR_NS get deploy cert-manager -o jsonpath='{.spec.template.spec.containers[].image}' > $TEMPDIR/cert-manager.txt 2>> $logfile
        cat $TEMPDIR/cert-manager.txt >> $logfile
    else
        echo "WARNING: cert-manager configured to be used by Viya, but an instance wasn't found running in the kubernetes cluster." | tee -a $logfile
    fi
fi

echo "  - nginx-ingress version" | tee -a $logfile
if [ ! -z $NGINX_NS ]; then
    kubectl -n $NGINX_NS get deploy ingress-nginx-controller -o jsonpath='{.spec.template.spec.containers[].image}' > $TEMPDIR/nginx-ingress.txt 2>> $logfile
    cat $TEMPDIR/nginx-ingress.txt >> $logfile
fi

echo "  - Getting order number" | tee -a $logfile
grep '\- username' $DEPLOYPATH/sas-bases/base/secrets.yaml 2>> $logfile | cut -d '=' -f2 > $TEMPDIR/order.txt 2>> $logfile
cat $TEMPDIR/order.txt >> $logfile

echo "  - Getting cadence information" | tee -a $logfile
kubectl -n $VIYA_NS get cm $(kubectl get cm -n $VIYA_NS 2>> $logfile | grep deployment-metadata | cut -f1 -d' ') -o jsonpath='{"\n"}{.data.SAS_CADENCE_DISPLAY_NAME}{"\n"}{.data.SAS_CADENCE_RELEASE}{"\n"}' > $TEMPDIR/cadence.txt 2>> $logfile
cat $TEMPDIR/cadence.txt >> $logfile

echo "  - Kubernetes resource information" | tee -a $logfile
kubectl -n $VIYA_NS get sc,pv,pvc,po,deploy,sts,rs,svc,ing,crd,cm,secrets,podtemplate -o wide > $TEMPDIR/resources.txt 2>> $logfile
kubectl -n $VIYA_NS describe all,podtemplate,ingress > $TEMPDIR/describe.txt 2>> $logfile
kubectl describe nodes > $TEMPDIR/nodes.txt 2>> $logfile
for sasdeployment in $(kubectl -n $VIYA_NS get sasdeployment 2> /dev/null | grep -v NAME | awk '{print $1}'); do
	kubectl -n $VIYA_NS get sasdeployment $sasdeployment -o yaml > $TEMPDIR/$sasdeployment-sasdeployment.yaml 2>> $logfile
    removeSensitiveData $TEMPDIR/$sasdeployment-sasdeployment.yaml
done
kubectl -n kube-system get all -o wide > $TEMPDIR/kubesystem-resources.txt 2>> $logfile
kubectl -n kube-system describe all > $TEMPDIR/kubesystem-describe.txt 2>> $logfile

# Collect logs from pods in PODLOGS variable
addLabelSelector $(echo $PODLOGS | tr ',' ' ')
# Collect logs from Not Ready pods
notreadylist=$(kubectl -n $VIYA_NS get pod -l "sas.com/deployment=sas-viya" 2>> $logfile | grep -v '1/1\|2/2\|3/3\|4/4\|5/5\|6/6\|7/7\|8/8\|9/9\|Completed\|NAME' | awk '{print $1}' | tr '\n' ' ')
addPod $notreadylist
# Collect logs from upper pods (using same rules as start-sequencer)
## Level 1: Pods that should wait for Consul to be ready
if [[ $notreadylist =~ 'sas-arke' || $notreadylist =~ 'sas-cache' || $notreadylist =~ 'sas-redis' ]]; then 
    echo "INFO: Including logs from sas-consul-server pods, because there are dependent pods not ready..." | tee -a $logfile
    addLabelSelector 'sas-consul-server'
fi
# Level 2: Pods that should wait for Consul, Arke, and Postgres
if [[ $notreadylist =~ 'sas-logon-app' || $notreadylist =~ 'sas-identities' || $notreadylist =~ 'sas-configuration' || $notreadylist =~ 'sas-authorization' ]]; then 
    echo "INFO: Including logs from sas-consul-server and sas-arke pods and enabling 'postgres' debugtag, because there are dependent pods not ready..." | tee -a $logfile
    addLabelSelector 'sas-consul-server sas-arke'
    POSTGRES=true
fi
# Level 3: Pods that should wait for SAS Logon
if [[ $notreadylist =~ 'sas-app-registry' || $notreadylist =~ 'sas-types' || $notreadylist =~ 'sas-transformations' || $notreadylist =~ 'sas-relationships' || \
      $notreadylist =~ 'sas-preferences' || $notreadylist =~ 'sas-folders' || $notreadylist =~ 'sas-files' || $notreadylist =~ 'sas-cas-administration' || \
      $notreadylist =~ 'sas-launcher' || $notreadylist =~ 'sas-feature-flags' || $notreadylist =~ 'sas-audit' || $notreadylist =~ 'sas-credentials' || \
      $notreadylist =~ 'sas-model-publish' || $notreadylist =~ 'sas-forecasting-pipelines' || $notreadylist =~ 'sas-localization' || \
      $notreadylist =~ 'sas-cas-operator' || $notreadylist =~ 'sas-app-registry' || $notreadylist =~ 'sas-types' || $notreadylist =~ 'sas-transformations' || \
      $notreadylist =~ 'sas-relationships' || $notreadylist =~ 'sas-preferences' || $notreadylist =~ 'sas-folders' || $notreadylist =~ 'sas-files' || \
      $notreadylist =~ 'sas-cas-administration' || $notreadylist =~ 'sas-launcher' || $notreadylist =~ 'sas-feature-flags' || $notreadylist =~ 'sas-audit' || \
      $notreadylist =~ 'sas-credentials' || $notreadylist =~ 'sas-model-publish' || $notreadylist =~ 'sas-forecasting-pipelines' || \
      $notreadylist =~ 'sas-localization' || $notreadylist =~ 'sas-cas-operator' ]]; then 
    echo "INFO: Including logs from sas-logon-app pod, because there are dependent pods not ready..." | tee -a $logfile
    addLabelSelector 'sas-logon-app'
fi

if [[ "$CAS" = true || $notreadylist =~ 'sas-cas-' ]]; then
    echo "  - Getting cas information" | tee -a $logfile
    addLabelSelector "sas-cas-control" "sas-cas-operator" "app.kubernetes.io/name=sas-cas-server"
    for casdeployment in $(kubectl -n $VIYA_NS get casdeployment 2>> $logfile | grep -v NAME | awk '{print $1}'); do
        kubectl -n $VIYA_NS get casdeployment $casdeployment -o yaml > $TEMPDIR/$casdeployment-casdeployment.yaml 2>> $logfile
    done
fi
if [[ "$CONFIG" = true ]]; then
    echo "  - Dumping consul config" | tee -a $logfile
    kubectl -n $VIYA_NS exec -it sas-rabbitmq-server-0 -c sas-rabbitmq-server -- /opt/sas/viya/home/bin/sas-bootstrap-config kv read --prefix 'config/' --recurse > $TEMPDIR/consul-config.out 2>> $logfile
    if [ $? -ne 0 ]; then kubectl -n $VIYA_NS exec -it sas-rabbitmq-server-1 -c sas-rabbitmq-server -- /opt/sas/viya/home/bin/sas-bootstrap-config kv read --prefix 'config/' --recurse > $TEMPDIR/consul-config.out 2>> $logfile
        if [ $? -ne 0 ]; then kubectl -n $VIYA_NS exec -it sas-rabbitmq-server-2 -c sas-rabbitmq-server -- /opt/sas/viya/home/bin/sas-bootstrap-config kv read --prefix 'config/' --recurse > $TEMPDIR/consul-config.out 2>> $logfile; fi
    fi
    removeSensitiveData $TEMPDIR/consul-config.out
fi
if [ "$NGINX" = true ]; then
    echo "  - Getting nginx information" | tee -a $logfile
    kubectl -n $NGINX_NS get all -o wide > $TEMPDIR/nginx-resources.txt 2>> $logfile
    kubectl -n $NGINX_NS describe all > $TEMPDIR/nginx-describe.txt 2>> $logfile
    for ingresspod in $(kubectl get pod -n $NGINX_NS 2>> $logfile | grep ingress-nginx-controller | awk '{print $1}'); do 
        kubectl -n "$NGINX_NS" logs "$ingresspod" > $TEMPDIR/$ingresspod.log 2>> $logfile
    done
fi
if [[ "$POSTGRES" = true || $notreadylist =~ 'sas-data-server-operator' || $notreadylist =~ 'sas-crunchy' ]]; then
    echo "  - Getting postgres information" | tee -a $logfile
    addLabelSelector "sas-data-server-operator"
    if [ $(kubectl get crd postgresclusters.postgres-operator.crunchydata.com > /dev/null 2>&1;echo $?) -ne 0 ]; then
        #Crunchy4 commands
        for pgcluster in $(kubectl -n $VIYA_NS get pgclusters.webinfdsvr.sas.com 2>> $logfile | grep -v NAME | awk '{print $1}'); do
            kubectl -n $VIYA_NS get pgclusters.webinfdsvr.sas.com $pgcluster -o yaml > $TEMPDIR/$pgcluster-pgcluster.yaml 2>> $logfile
            if [[ $pgcluster =~ 'crunchy' ]]; then 
                kubectl -n $VIYA_NS get configmap $pgcluster-pgha-config -o yaml > $TEMPDIR/$pgcluster-pgha-config.yaml 2>> $logfile
                MASTER=$(kubectl -n $VIYA_NS get pod -l "crunchy-pgha-scope=$pgcluster,role=master" 2>> $logfile | grep crunchy | awk '{print $1}' | tr '\n' ' ')
                kubectl -n $VIYA_NS exec -it $MASTER -c database -- patronictl list > $TEMPDIR/$pgcluster-patronictl.log 2>> $logfile
                addLabelSelector "vendor=crunchydata"
            fi
        done
    else
        #Crunchy5 commands
        for pgcluster in $(kubectl -n $VIYA_NS get postgresclusters.postgres-operator.crunchydata.com 2>> $logfile | grep -v NAME | awk '{print $1}'); do
            kubectl -n $VIYA_NS get postgresclusters.postgres-operator.crunchydata.com $pgcluster -o yaml > $TEMPDIR/$pgcluster-pgcluster.yaml 2>> $logfile
            if [[ $pgcluster =~ 'crunchy' ]]; then 
                kubectl -n $VIYA_NS describe cm -l 'postgres-operator.crunchydata.com/cluster=sas-crunchy-platform-postgres' > $TEMPDIR/$pgcluster-configmaps.txt 2>> $logfile
                MASTER=$(kubectl -n $VIYA_NS get pod -l "postgres-operator.crunchydata.com/role=master,postgres-operator.crunchydata.com/cluster=$pgcluster" 2>> $logfile | grep crunchy | awk '{print $1}' | tr '\n' ' ')
                kubectl -n $VIYA_NS exec -it $MASTER -c database -- patronictl list > $TEMPDIR/$pgcluster-patronictl.log 2>> $logfile
                addLabelSelector "postgres-operator.crunchydata.com/cluster=$pgcluster"
                crunchypods=$(kubectl -n $VIYA_NS get pod 2>> $logfile | grep crunchy | awk '{print $1}' | tr '\n' ' ')
                addPod $crunchypods
            fi
        done
    fi
fi

# Collect logs
if [ ! -z "$podList" ]; then
    echo "  - Getting pod logs" | tee -a $logfile
    mkdir $TEMPDIR/Logs
    for pod in ${podList[@]}; do 
        if [ $(find $TEMPDIR/Logs -maxdepth 1 -name $pod* | wc -l) -eq 0 ]; then
            echo "    - $pod" | tee -a $logfile
            for container in $(kubectl -n $VIYA_NS get pod $pod -o=jsonpath='{.spec.initContainers[*].name}' 2>> $logfile) $(kubectl -n $VIYA_NS get pod $pod -o=jsonpath='{.spec.containers[*].name}' 2>> $logfile); do 
                kubectl -n $VIYA_NS logs $pod $container > $TEMPDIR/Logs/$pod\_$container.log 2>> $logfile
                # Remove if empty
                if [ ! -s $TEMPDIR/Logs/$pod\_$container.log ]; then rm -f $TEMPDIR/Logs/$pod\_$container.log; fi
            done
        fi
    done
fi
# If a pod has ever been restarted by kubernetes, try to capture its previous logs
restartedPodList=$(kubectl -n $VIYA_NS get pod 2>> $logfile | grep -v NAME | awk '{if ($4 > 0) print $1}' | tr '\n' ' ')
if [ ! -z "$restartedPodList" ]; then
    echo "  - Getting pod previous logs" | tee -a $logfile
    mkdir -p $TEMPDIR/Logs/previous
    for pod in $restartedPodList; do
        echo "    - $pod" | tee -a $logfile
        for container in $(kubectl -n $VIYA_NS get pod $pod -o=jsonpath='{.spec.initContainers[*].name}' 2>> $logfile) $(kubectl -n $VIYA_NS get pod $pod -o=jsonpath='{.spec.containers[*].name}' 2>> $logfile); do 
            kubectl -n $VIYA_NS logs $pod $container --previous > $TEMPDIR/Logs/previous/$pod\_$container\_previous.log 2>> $logfile
            # Remove if empty
            if [ ! -s $TEMPDIR/Logs/previous/$pod\_$container\_previous.log ]; then rm -f $TEMPDIR/Logs/previous/$pod\_$container\_previous.log; fi
        done
    done
fi

# Collect 'kviya' compatible playback file (https://gitlab.sas.com/sbralg/tools-and-scripts/-/blob/main/kviya)
saveTime=$(date -u +"%YD%mD%d_%HT%MT%S")
mkdir $TEMPDIR/$saveTime
kubectl get node > $TEMPDIR/$saveTime/getnodes.out 2>> $logfile
kubectl describe node > $TEMPDIR/$saveTime/nodes-describe.out 2>> $logfile
kubectl -n $VIYA_NS get pod -o wide > $TEMPDIR/$saveTime/getpod.out 2>> $logfile
kubectl -n $VIYA_NS get events > $TEMPDIR/$saveTime/podevents.out 2>> $logfile
kubectl top node > $TEMPDIR/$saveTime/nodesTop.out 2>> $logfile
kubectl -n $VIYA_NS top pod > $TEMPDIR/$saveTime/podsTop.out 2>> $logfile
tar -czf $TEMPDIR/$saveTime.tgz --remove-files --directory=$TEMPDIR $saveTime 2>> $logfile

if [ $DEPLOYPATH != 'unavailable' ]; then
    echo "  - Getting deployment assets" | tee -a $logfile
    mkdir $TEMPDIR/assets 2>> $logfile
    cd $DEPLOYPATH 2>> $logfile
    find . -path ./sas-bases -prune -false -o -name "*.yaml" -exec tar -rf $TEMPDIR/assets/assets.tar {} \; 2>> $logfile
    tar xf $TEMPDIR/assets/assets.tar --directory $TEMPDIR/assets 2>> $logfile
    rm -rf $TEMPDIR/assets/assets.tar 2>> $logfile
    removeSensitiveData $(find $TEMPDIR/assets -type f)
fi

cp $logfile $TEMPDIR
tar -czf $OUTPATH/T${TRACKNUMBER}.tgz --directory=$TEMPDIR .
if [ $? -eq 0 ]; then
    if [ $SASTSDRIVE == 'true' ]; then
        echo -e "\nDone! File '$OUTPATH/T${TRACKNUMBER}.tgz' was successfully created." | tee -a $logfile
        # use an sftp batch file since the user password is expected from stdin
        cat > $TEMPDIR/SASTSDrive.batch <<< "put $OUTPATH/T${TRACKNUMBER}.tgz $TRACKNUMBER"
        echo -e "\nINFO: Performing SASTSDrive login. Use only an email that was authorized by SAS Tech Support for the track\n" | tee -a $logfile
        read -p " -> SAS Profile Email: " EMAIL
        echo '' | tee -a $logfile
        sftp -oPubkeyAuthentication=no -oPasswordAuthentication=no -oNumberOfPasswordPrompts=2 -oConnectTimeout=1 -oBatchMode=no -b $TEMPDIR/SASTSDrive.batch "${EMAIL}"@sft.sas.com > /dev/null 2>> $logfile
        if [ $? -ne 0 ]; then 
            echo -e "\nERROR: Failed to send the '$OUTPATH/T${TRACKNUMBER}.tgz' file to SASTSDrive through sftp. Will not retry." | tee -a $logfile
            echo -e "\nSend the '$OUTPATH/T${TRACKNUMBER}.tgz' file to SAS Tech Support using a browser (https://support.sas.com/kb/65/014.html#upload) or through the track.\n" | tee -a $logfile
            cleanUp 1
        else 
            echo -e "\nDone! File successfully sent to SASTSDrive.\n" | tee -a $logfile
            cleanUp 0
        fi
    else
        echo -e "\nDone! File '$OUTPATH/T${TRACKNUMBER}.tgz' was successfully created. Send it to SAS Tech Support.\n" | tee -a $logfile
        cleanUp 0
    fi
else
    echo "ERROR: Failed to save output file '$OUTPATH/T${TRACKNUMBER}.tgz'." | tee -a $logfile
    cleanUp 1
fi