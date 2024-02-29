#!/usr/bin/env bash
#
# Script     : asla.sh
# Usage      : ./asla.sh /path/tp/target /path/to/destination
# Author     : Giuseppe Totaro
# Date       : 2024-02-01
# Last Edited: 2024-02-26
# Description: This script performs the logical acquisition of data from the 
#              target (i.e., the Apple Silicon Mac to be acquired) started in 
#              "share disk mode", by leveraging either "cp" or "rsync" on the 
#              host (i.e., the Mac device of the forensic examiner).
#              Basically, the script performs the following actions:
#              1. If executed in assisted mode, it mounts read-only on the host 
#                 the shared disk of the target.
#              2. On the host, it creates a sparse image which is mounted to be 
#                 used as the destination of the acquisition.
#              3. It leverages a copy tool (i.e., "cp" or "rsync") to copy 
#                 the data from the target to the attached sparse image on the 
#                 host, preserving the original file attributes.
#              4. It detaches the sparse image and generates the log files of 
#                 the acquisition process.
#              This script is released under the MIT License (MIT).
# Notes      : The target must be started in "share disk mode".
#

set -o errexit
set -o pipefail
set -o nounset

# Global Variables

VERSION="1.0"
REPO="https://github.com/giuseppetotaro/asla"
TOOLS=("cp" "rsync")
OUT_FILE=
LOG_FILE=
ERR_FILE=
VOLUME_NAME=

# Functions

#######################################
# Clean up detaching the attached sparse image.
# Globals:
#   VOLUME_NAME
# Arguments:
#   None
# Outputs:
#   Writes error message to stdout.
#######################################
cleanup() {
  echo "# An error occurred. Cleaning up..."
  [[ -d "${VOLUME_NAME}" ]] && detach_image "${VOLUME_NAME}"
  echo "# Process has been terminated with errors."
  echo "# Check manually if target has been mounted anyway and, if so, unmount it."
}

#######################################
# Print help message.
# Arguments:
#   None
# Outputs:
#   Writes the help message to stdout.
#######################################
print_usage() {
cat << EOF
ASLA (Apple Silicon Logical Acquisition)  version $VERSION
Copyright (c) 2024 Giuseppe Totaro
GitHub repo: https://github.com/giuseppetotaro/asla

asla.sh is provided "as is", WITHOUT WARRANTY OF ANY KIND. You are welcome to 
redistribute it under certain conditions. See the MIT Licence for details.

asla.sh is a bash script to perform the logical acquisition of data from the 
targeted Apple Silicon Mac started in "share disk mode".

Usage:  ${0} [OPTION]... TARGET DESTINATION

TARGET       path to the target (i.e., the mount point of the Mac's shared disk 
             to be acquired).
DESTINATION  path to the folder where the sparse image used as destination will 
             be created.

If the target is a path to a non-existing folder, the script will run in 
assisted mode (equivalent to using the -a option) to identify the target.

Examples:
  ./asla.sh /Volumes/ShareDisk /Volumes/ExternalDrive
  ./asla.sh -a -c /tmp/target /Volumes/ExternalDrive
  ./asla.sh -n "MacBook Air" -u user -p password /tmp/target /Volumes/Dest
  ./asla.sh -i MyAcquisition -s 500 /Volumes/ShareDisk /Volumes/Dest
  ./asla.sh -t rsync /Volumes/ShareDisk /Volumes/ExternalDrive

Options:
  -h, --help                 print this help message
  -a, --assisted             run the script in assisted mode
  -c, --calculate-hash       calculate MD5 and SHA1 hashes of the sparse image
  -i, --image-name <name>    name of the sparse image (without extension)
  -n, --name <name>          computer name of the target (only in assisted mode)
      --no-password          no password will be used (only in assisted mode)
  -p, --password <password>  password of the target (only in assisted mode)
  -s, --size <number>        size of the sparse image in KB, otherwise it will 
                             be calculated based on the size of the target
  -t, --tool <cp|rsync>      tool for the acquisition (cp is the default)
  -u, --user <name>          username of the target (only in assisted mode)
EOF
}

#######################################
# Backup the existing sparse image and log files to a specific folder named as
# the current date and time.
# Globals:
#   OUT_FILE
#   LOG_FILE
#   ERR_FILE
# Arguments:
#   destination path, the folder where the backup will be created.
#   image_name, the name of the sparse image without extension.
# Outputs:
#   Writes the backup folder and files to stdout.
#######################################
backup() { 
  local destination="${1}"
  local image_name="${2}"
  local files=()
  files+=("${destination}/${image_name}.sparseimage")
  files+=("${OUT_FILE}")
  files+=("${LOG_FILE}")
  files+=("${ERR_FILE}")
  local now=$(date +'%Y%m%d%H%M%S')
  mkdir -p "${destination}"
  for file in "${files[@]}"
  do
    if [[ -f "${file}" ]]
    then
      mkdir "${destination}/${now}" 2>/dev/null && printf "# Created backup folder %s\n" "${destination}/${now}"
      fname=$(basename "${file}")
      mv "${file}" "${destination}/${now}/${now}.${fname}" 2>/dev/null
      printf "# Backed up %s to %s\n" "${file}" "${destination}/${now}"
    fi
  done
}

#TODO: print_instructions to acquire a Mac with Apple Silicon
#print_instructions() {  
#}

#######################################
# Normalize a string by replacing spaces with %20.
# Arguments:
#   name, the string to be normalized.
#######################################
normalize_name() {
  local name="${1}"
  echo "${name}" | sed 's/ /%20/g'
}

#######################################
# Mount the shared disk of the target at the given mount point.
# Arguments:
#   target_name, the name of the target computer.
#   target_user, the username of the target computer.
#   target_pass, the password of the target computer.
#   mount_point, the mount point of the shared disk.
# Outputs:
#   Writes info about the shared disk to stdout.
#######################################
mount_shared_disk() {
  local target_name=$(normalize_name "${1}")
  local target_user="${2}"
  local target_pass="${3}"
  local mount_point="${4}"
  local mount_pass=
  [[ -z "${target_pass}" ]] && mount_pass="" || mount_pass=":${target_pass}"
  local host="//${target_user}${mount_pass}@${target_name}._smb._tcp.local"
  printf "# Attempting to list resources on %s (password of target might be required) ...\n" "${host}"
  res=$(smbutil view ${host})
  local shared_disk=$(echo "${res}" | sed -rn  's/(.+[^[:space:]])[[:space:]]+Disk.*/\1/p')
  printf "# Found shared disk %s. Creating mount point at %s ...\n" "${shared_disk}" "${mount_point}"
  mkdir -p "${mount_point}"
  norm_shared_disk=$(normalize_name "${shared_disk}")
  printf "# Mounting %s/%s at %s ...\n" "${host}" "${norm_shared_disk}" "${mount_point}"
  mount_smbfs -o ro "${host}/${norm_shared_disk}" "${mount_point}"
}

#######################################
# Print the acquisition info.
# Arguments:
#   target, the target folder.
#   destination, the destination folder.
#   image_name, the name of the sparse image.
#   tool, the tool used to copy data from target.
# Outputs:
#   Writes the acquisition info to stdout.
#######################################
print_acquisition_info() {
  local target="${1}"
  local destination="${2}"
  local image_name="${3}"
  local tool="${4}"
  local target_space=$(df -h "${target}")
cat << EOF
# Process started at ${start_datetime}

# Acquisition Info
# ----------------
# Target:       ${target}
# Destination:  ${destination}
# Image Name:   ${image_name}.sparseimage
# Tool:         ${tool}

# Displaying the target free disk space...
$target_space

EOF
}

#######################################
# Create a sparse image and attach it to the host.
# Globals:
#   VOLUME_NAME
# Arguments:
#   image_size, the size of the sparse image in KiloBytes.
#   destination, the destination folder where the sparse image will be created.
#   image_name, the name of the sparse image.
#   target, the target folder
# Outputs:
#   Writes the backup folder and files to stdout.
#######################################
create_sparse_image() {
  local image_size=${1}
  local destination="${2}"
  local image_name="${3}"  # To be used as volume name
  local target="${4}"
  [[ -z "${image_size}" ]] && image_size=$(df -k "${target}" | tail -1 | awk '{print (substr($2,1,1)+1)*(10^(length($2)-1))}')

cat << EOF
# Sparse Image
# ------------
# Creating and attaching the sparse image of size ${image_size}k...
EOF

  mkdir -p "${destination}"
  destination_fullpath="${destination}/${image_name}"
  out=$(hdiutil create -size ${image_size}k -volname "${image_name}" -fs APFS -layout GPTSPUD -type SPARSE -attach "${destination_fullpath}")

cat << EOF
# Sparse image created at ${destination_fullpath}. Output: 
"${out}"

EOF

  # Commentary: The volume name should be the image name unless a volume with 
  # the same name already exists. This is to get the actual volume name from the
  # output of the hdiutil command.
  VOLUME_NAME=$(echo "${out}" | sed -rn 's/.+(\/Volumes\/.+[^[:space:]]).*/\1/p' | head -1)
}

#######################################
# Acquire data from the target to the attached sparse image on the host.
# Globals:
#   LOG_FILE
#   ERR_FILE
# Arguments:
#   target, the target folder.
#   volume_name, the volume name of the attached sparse image.
#   tool, the tool used to copy data from target (cp or rsync).
# Outputs:
#   Writes the paths to target and attached volume to stdout, copied files to 
#   LOG_FILE, and errors to ERR_FILE.
#######################################
acquire_data() {
  local target=$(echo "${1}" | sed -e 's#[^/]$#&/#')
  local volume_name=$(echo "${2}" | sed -e 's#[^/]$#&/#')
  local tool="${3}"

cat << EOF
# Data Acquisition
# ----------------
# Acquiring data from ${target} to ${volume_name}...
EOF
  if [[ "${tool}" == "cp" ]]
  then
    cp -PRpvi "${target}." "${volume_name}" > "${LOG_FILE}" 2> "${ERR_FILE}" && rc=$? || rc=$?
  elif [[ "${tool}" == "rsync" ]]
  then
    rsync -artvqX --log-file="${LOG_FILE}" "${target}" "${volume_name}" > "${LOG_FILE}" 2> "${ERR_FILE}" && rc=$? || rc=$?
  fi

  if [[ ${rc} -eq 0 ]]
  then
    printf "# Data from %s copied to %s with %s completed successfully\n\n" "${target}" "${volume_name}" "${tool}"
  else
    printf "# Data from %s copied to %s with %s has terminated with error code %s\n" "${target}" "${volume_name}" "${tool}" "${rc}"
    printf "# It is expected to encounter errors while copying some files. Please check '%s'\n\n" "${ERR_FILE}"
  fi
}

#######################################
# Detach the attached sparse image from the host.
# Arguments:
#   volume_name, the volume name of the attached sparse image.
# Outputs:
#   Writes the output of the detach command to stdout.
#######################################
detach_image() {
  local volume_name="${1}"
  printf "# Detaching %s. Output: \n" "${volume_name}"
  hdiutil detach -force "${volume_name}" && rc=$? || rc=$?
  printf "# Detach completed with code %s\n\n" "${rc}"
}

#######################################
# Calculate the MD5 hash of the sparse image.
# Arguments:
#   destination, the destination folder.
#   image_name, the name of the sparse image.
# Outputs:
#   Writes the MD5 hash to stdout.
#######################################
calculate_md5() {
  local destination="${1}"
  local image_name="${2}"
  md5_hash=$(md5 -q "${destination}/${image_name}.sparseimage")
  echo "${md5_hash}"
}

#######################################
# Calculate the SHA1 hash of the sparse image.
# Arguments:
#   destination, the destination folder.
#   image_name, the name of the sparse image.
# Outputs:
#   Writes the SHA1 hash to stdout.
#######################################
calculate_sha1() {
  local destination="${1}"
  local image_name="${2}"
  sha1_hash=$(openssl sha1 "${destination}/${image_name}.sparseimage" | awk '{print $2}')
  echo "${sha1_hash}"
}

#######################################
# Print the summary of the acquisition process.
# Globals:
#   LOG_FILE
#   ERR_FILE
# Arguments:
#   start_datetime, the start date and time of the acquisition process.
#   destination, the destination folder.
#   image_name, the name of the sparse image.
#   hash, the flag to include, if true, the hash values of the sparse image.
# Outputs:
#   Writes the summary to stdout.
#######################################
print_summary() {
  local start_datetime="${1}"
  local destination="${2}"
  local image_name="${3}"
  local hash="${4}"

cat << EOF
# Summary
# -------
# Start time:  ${start_datetime}"
# End time:    $(date)"
# Destination: ${destination}
# Image Name:  ${image_name}.sparseimage
EOF
  if [[ "${hash}" == "true" ]]
  then
    printf "# MD5:         %s\n" $(calculate_md5 "${destination}" "${image_name}")
    printf "# SHA1:        %s\n" $(calculate_sha1 "${destination}" "${image_name}")
  fi

  printf "\n# Process has completed. Output created in %s\n\n" "${destination}"
  printf "# Please check the following log files about the copy:\n# FILES : %s\n# ERRORS: %s\n\n" "${LOG_FILE}" "${ERR_FILE}"
  printf "# Thanks for using ASLA - %s\n\n" "${REPO}"
}

#######################################
# Print the banner of the script.
#######################################
print_banner() {
cat << EOF
#
# Apple Silicon Logical Acquisition (ASLA)
#
# GitHub repo: https://github.com/giuseppetotaro/asla
#

EOF
}

#######################################
# Run the acquisition process.
#######################################
run_process() {
  print_acquisition_info "${target}" "${destination}" "${image_name}" "${tool}"
  create_sparse_image "${size}" "${destination}" "${image_name}" "${target}"
  trap cleanup EXIT
  acquire_data "${target}" "${VOLUME_NAME}" "${tool}"
  detach_image "${VOLUME_NAME}"
  print_summary "${start_datetime}" "${destination}" "${image_name}" "${hash}"
}

#######################################
# Main function.
#######################################
main() {
  # Positional arguments
  local position=0 # Positional argument counter
  local target=
  local destination=

  # Keyword arguments
  local assisted=
  local hash=
  local image_name="ACQUISITION"
  local size=
  local tool="cp" # Default command-line tool for the acquisition
  local target_name=
  local target_pass=
  local target_user=
  local nopassword=

  while [[ "${#}" -gt 0 ]]
  do
    case "${1}" in
      -h|--help)
        print_usage
        exit 0
        ;;
      -a|--assisted)
        assisted="true"
        shift
        ;;
      -c|--calculate-hash)
        hash="true"
        shift
        ;;
      -i|--image-name)
        image_name="${2:-}"
        [[ -z "${image_name}" ]] && printf "%s must have a value\n\n" "${1}" >&2 && print_usage >&2 && exit 1
        shift 2
        ;;
      -n|--name)
        target_name="${2:-}"
        [[ -z "${target_name}" ]] && printf "%s must have a value\n\n" "${1}" >&2 && print_usage >&2 && exit 1
        shift 2
        ;;
      --no-password)
        nopassword="true"
        shift
        ;;
      -p|--password)
        target_pass="${2:-}"
        [[ -z "${target_pass}" ]] && printf "%s must have a value\n\n" "${1}" >&2 && print_usage >&2 && exit 1
        shift 2
        ;;
      -s|--size)
        size="${2}"
        shift 2
        ;;
      -t|--tool)
        tool="${2:-}"
        [[ -z "${tool}" ]] && printf "%s must have a value\n\n" "${1}" >&2 && print_usage >&2 && exit 1
        shift 2
        ;;
      -u|--user)
        target_user="${2:-}"
        [[ -z "${target_user}" ]] && printf "%s must have a value\n\n" "${1}" >&2 && print_usage >&2 && exit 1
        shift 2
        ;;
      *)
        case "${position}" in
          0)
            target="${1}"
            position=1
            shift
            ;;
          1) 
            destination="${1}"
            position=2
            shift
            ;;
          2)
            printf "Unknown argument passed: %s\n\n" "${1}" >&2
            print_usage >&2
            exit 1
            ;;
        esac
        ;;
    esac
  done

  # Validation 

  [[ -z "${target}" ]] && printf "Requires target folder\n\n" >&2 && print_usage >&2 && exit 1
  [[ -z "${destination}" ]] && printf "Requires destination folder\n\n" >&2 && print_usage >&2 && exit 1
  [[ ! $(echo "${TOOLS[@]}" | grep -w "${tool}") ]] && printf "Unknown data transfer tool. Only cp and rsync are supported\n\n" >&2 && print_usage >&2 && exit 1

  # Acquisition

  # Discussion: It might be useful to give the option to change the name of log 
  # files. This can be done with an option for each log file or a single option 
  # where the same name is used for all log files, which would differ only in 
  # the file extension.
  OUT_FILE="${destination}/${image_name}.out"
  LOG_FILE="${destination}/${image_name}.log"
  ERR_FILE="${destination}/${image_name}.err"

  clear -x  # Clear the screen without attempting to clear the terminal's 
            # scrollback buffer
  print_banner

  backup "${destination}" "${image_name}"

  start_datetime=$(date)

  if [[ ! -d "${target}" || "${assisted}" == "true" ]]
  then
    while true
    do
      [[ "${assisted}" == "true" ]] && answer="y" || read -p "# Do you want to continue in assisted mode to identify the target? [yn] " answer
      case $answer in
          [Yy])
            printf "# Assisted mode selected\n" | tee -a "${OUT_FILE}"
            [[ -z "${target_name}" ]] && read -p "# Please provide the computer name of the target: " target_name
            [[ -z "${target_user}" ]] && read -p "# Please provide the username of the target: " target_user
            if [[ "${nopassword}" != "true" ]]
            then 
              [[ -z "${target_pass}" ]] && read -p "# Please provide the password of the target: " target_pass
            fi
            mount_shared_disk "${target_name}" "${target_user}" "${target_pass}" "${target}" | tee -a "${OUT_FILE}"
            break
            ;;
          [Nn]) 
            echo "# Target folder must be provided! Exiting...";
            exit 1
            ;;
          * ) echo "# Please answer yes or no.";;
      esac
    done
  fi

  run_process | tee -a "${OUT_FILE}"
}

main "${@:-}"
