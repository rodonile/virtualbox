#!/bin/bash
###############################################
# Argument parsing
###############################################
# Defaults
DRY_RUN=NO

RAM=1024
CPUS=2
VRAM=12

ADD_SATA_CONTROLLER=NO
PROVISION_VIRTUAL_HDD=NO
HDD_SIZE=0
ADD_IDE_CONTROLLER=NO
ATTACH_ISO_FILE=NO
CREATE_SYSTEMD_DAEMON=NO

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -h|--help)
    echo "Command reference:"
    echo
    echo "  -h | --help"
    echo "  --ostype [ubuntu|redhat|linux|debian|freebsd]"
    echo "  -c  |  --cpus [1|2|3|4]                       --> default = 2 cores"
    echo "  -m  | --memory [<ram size in MB>]             --> default = 1024MB"
    echo "  --vram [<vram size in MB>]                    --> default = 12MB (for headless VMs is fine)"
    echo "  --SATA                                        --> add SATA controller"
    echo "  --virt_HDD [<HDD_size in MiB> | no]           --> create and attach a XXX MiB virtual HDD or not"
    echo "  --IDE                                         --> add IDE controller"
    echo "  --isofile [<.iso location> | no]              --> attach isofile to IDE controller"
    echo "  --vrdeport [PORT_NUMBER]                      --> enables VRDE at the specified port (check netstat -tupln for free ports before!)"
    echo "  -n  | --name                                  --> VM name"
    echo "  -s  |  --systemd                              --> create systemd daemon to start vm on boot"
    echo "  -d  | --dry-run"
    echo
    echo "Example (20GB HDD): ./create_new_vm.sh -d --ostype ubuntu -c 2 -m 2048 --SATA --virt_HDD 20480 --IDE --isofile '/../<ISOFILE_FULLPATH.iso>' --vrdeport 1000X -n '<VM_NAME>' --systemd"
    echo
    exit 1
    ;;

    --ostype)
      if [[ $2 == "ubuntu" || $2 == "Ubuntu_64" ]]
      then
        OS_TYPE="Ubuntu_64"
      elif [[ $2 == "debian" || $2 == "Debian_64" ]]
      then
        OS_TYPE="Debian_64"
      elif [[ $2 == "redhat" || $2 == "centos" || $2 == "RedHat_64" ]]
      then
        OS_TYPE="RedHat_64"
      elif [[ $2 == "linux" || $2 == "Linux_64" ]]
      then
        OS_TYPE="Linux_64"
      elif [[ $2 == "freebsd" || $2 == "FreeBSD_64" ]]
      then
        OS_TYPE="FreeBSD_64"
      else
        echo "Invalid or not supported OS type"
      fi
      shift
      shift
      ;;

    -c|--cpus)
      CPUS=$2
      shift
      shift
      ;;

    -m|--memory)
      RAM=$2
      shift
      shift
      ;;

    --vram)
      VRAM=$2
      shift
      shift
      ;;

    --SATA)
      ADD_SATA_CONTROLLER=YES
      shift 
      ;;

    --virt_HDD)
      if [[ $2 != "no" && $2 != "" ]]
      then
        PROVISION_VIRTUAL_HDD=YES
        HDD_SIZE=$2
      fi
      shift 
      shift 
      ;;

    --IDE)
      ADD_IDE_CONTROLLER=YES
      shift 
      ;;

    --isofile) 
      if [[ $2 != "no" ]]
      then
        ATTACH_ISO_FILE=YES
        ISO_LOCATION=$2
      fi
      shift
      shift
      ;;
    
    --vrdeport)
      MANUAL_VRDE_PORT=YES
      VRDE_PORT=$2
      shift
      shift
      ;;
    
    -n|--name)
      VM_NAME=$2
      shift
      shift
      ;;

    -s|--systemd)
      CREATE_SYSTEMD_DAEMON=YES
      shift
      ;;

    -d|--dry-run)
      DRY_RUN=YES
      shift
      ;;

    *) # unknown option
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters

# Parameters check
if [[ $OS_TYPE == "" ]]
then
  echo "ERROR: please provide an OS Type (--ostype ubuntu, redhat, debian, linux or freebsd)."
  echo "HINT: --help is available"
  exit 1
elif [[ $VM_NAME == "" ]]
then
  echo "ERROR: please provide a name for the VM with -n | --name."
  echo "HINT: --help is available"
  exit 1
elif [[ $CPUS -gt 4 || $CPUS -lt 1 ]]
then
  echo "ERROR: incompatible number of cores (${CPUS}). Possible values: 1|2|3|4"
  echo "HINT: --help is available"
  exit 1
elif [[ $RAM -gt 4096 ]]    # Change it according to available system resources
then
  echo "ERROR: too much RAM (more than 4GB not allowed, could change threshold in the script if required...)"
  exit 1
fi


# Parameters display
echo "DRY-RUN                   = ${DRY_RUN}"
echo "OS TYPE                   = ${OS_TYPE}"
echo "CPUs                      = ${CPUS}"
echo "MEMORY                    = ${RAM} MB"
echo "VRAM                      = ${VRAM} MB"
echo "ADD_SATA_CONTROLLER       = ${ADD_SATA_CONTROLLER}"
echo "PROVISION_VIRTUAL_HDD     = ${PROVISION_VIRTUAL_HDD}"
echo "HDD_SIZE                  = ${HDD_SIZE} MiB"
echo "ADD_IDE_CONTROLLER        = ${ADD_IDE_CONTROLLER}"
echo "ATTACH_ISO_FILE           = ${ATTACH_ISO_FILE}"
echo "ISO_LOCATION              = ${ISO_LOCATION}"
echo "VRDE_PORT                 = ${VRDE_PORT}"
echo "VM_NAME                   = ${VM_NAME}"
echo "CREATE_SYSTEMD_DAEMON     = ${CREATE_SYSTEMD_DAEMON}"


###############################################
# Create the VM
###############################################
if [[ $DRY_RUN == 'NO' ]]
then
  echo "Registering the VM and allocating resources..."
  vboxmanage createvm --name ${VM_NAME} --ostype ${OS_TYPE} --register
  vboxmanage modifyvm ${VM_NAME} --cpus $CPUS --memory $RAM --vram $VRAM
  vboxmanage modifyvm ${VM_NAME} --nic1 bridged --bridgeadapter1 eno1

  if [[ ${ADD_SATA_CONTROLLER} == 'YES' ]]
  then
    echo "Adding SATA controller..."
    vboxmanage storagectl ${VM_NAME} --name "SATA Controller" --add sata --bootable on
  fi

  if [[ ${PROVISION_VIRTUAL_HDD} == 'YES' ]]
  then
    echo "Creating Hard Drive (dynamically allocated)..."
    vboxmanage createhd --filename "~/virtualbox/HDD_${VM_NAME}_${HDD_SIZE}MB.vdi" --size ${HDD_SIZE} --variant Standard
    if [[ ${ADD_SATA_CONTROLLER} == 'YES' ]]
    then
      echo "Attach Hard Drive to SATA controller..."
      vboxmanage storageattach ${VM_NAME} --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "~/virtualbox/HDD_${VM_NAME}_${HDD_SIZE}MB.vdi"
    fi
  fi

  if [[ ${ADD_IDE_CONTROLLER} == 'YES' ]]
  then
    echo "Adding IDE controller..."
    vboxmanage storagectl ${VM_NAME} --name "IDE Controller" --add ide
    vboxmanage modifyvm ${VM_NAME} --boot1 dvd --boot2 disk --boot3 none --boot4 none 
    echo "HINT: Remove ISO file (also possible with VM booted!):"
    echo "---> vboxmanage storageattach <VM_NAME> --storagectl "IDE Controller" --port 0  --device 0 --type dvddrive --medium emptydrive"
    if [[ ${ATTACH_ISO_FILE} == 'YES' ]]
    then
      echo "Attach ISO file to IDE controller..."
      vboxmanage storageattach ${VM_NAME} --storagectl "IDE Controller" --port 0  --device 0 --type dvddrive --medium ${ISO_LOCATION}
    fi
  fi

  if [[ ${VRDE_PORT} != '' ]]
  then
    echo "Setting up VRDE"
    vboxmanage modifyvm ${VM_NAME} --vrde on
    vboxmanage modifyvm ${VM_NAME} --vrdemulticon on --vrdeport ${VRDE_PORT} 
    sudo ufw allow ${VRDE_PORT}
  fi  

  if [[ ${CREATE_SYSTEMD_DAEMON} == 'YES' ]]
  then
    sudo systemctl enable vbox_vm_start@${VM_NAME}
  fi

  echo "VM created! Exiting..."
fi