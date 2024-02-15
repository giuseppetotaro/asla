#!/usr/bin/env bash
#
# Script     : asla.sh
# Usage      : ./asla.sh /path/tp/target /path/to/destination
# Author     : Giuseppe Totaro
# Date       : 2024-02-01
# Last Edited: 2024-02-14
# Description: This script performs the logical acquisition of data from the 
#              target (i.e., the Apple Silicon Mac to be acquired) started in 
#              "share disk mode", by leveraging either "cp" or "rsync" on the 
#              host (i.e., the Mac device of the forensic examiner).
#              Basically, the script performs the following actions:
#              1. If executed in assisted mode, it mounts on the host the shared
#                 disk of the target
#              2. On the host, it creates a sparse image which is mounted to be 
#                 used as the destination of the acquisition
#              3. It leverages a copy utility (i.e., "cp" or "rsync") to copy 
#                 the data from the target to the attached sparse image on the 
#                 host, preserving the original file attributes.
#              4. It detaches the sparse image and generates the log files of 
#                 the acquisition process
#              This script is released under the MIT License (MIT).
# Notes      : The target must be started in "share disk mode".
#

set -o errexit
set -o pipefail
set -o nounset

# Global Variables

UTILITIES=("cp" "rsync")
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
  Usage:  ${0} target destination [-i image_name] [-s size] [-u utility]

  target                      path to the target (i.e., the mount point of the Mac's shared disk to be acquired)
  destination                 path to the folder where the destination sparse image will be created

  If the target is a path to a non-existing folder, the script will run in assisted mode (equivalent to using the -a option).

  Options:
    -h, --help                print this help message
    -a, --assisted            run the script in assisted mode to identify the target
    -c, --calculate-hash      calculate MD5 and SHA1 hashes of the sparse image
    -i, --image-name <name>   name of the sparse image (without .sparseimage extension)
    -s, --size <number>       size of the sparse image in GigaBytes (default is 1000)
    -u, --utility <cp|rsync>  utility for the acquisition (cp or rsync; cp is the default)
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
  for file in "${files[@]}"
  do
    if [[ -f "${file}" ]]
    then
      mkdir "${destination}/${now}" 2>/dev/null && printf "# Created backup folder %s\n" "${destination}/${now}"
      printf "# Backing up %s to %s\n" "${file}" "${destination}/${now}"
      fname=$(basename "${file}")
      mv "${file}" "${destination}/${now}/${now}.${fname}" 2>/dev/null
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
#   mount_point, the mount point of the shared disk.
# Outputs:
#   Writes info about the shared disk to stdout.
#######################################
mount_shared_disk() {
  local target_name=$(normalize_name "${1}")
  local target_user="${2}"
  local mount_point="${3}"
  local host="//${target_user}@${target_name}._smb._tcp.local"
  echo "# Attempting to list resources on ${host} (password of target might be required)..."
  res=$(smbutil view ${host})
  local shared_disk=$(echo "${res}" | sed -rn  's/(.+[^[:space:]])[[:space:]]+Disk.*/\1/p')
  echo "# Found shared disk ${shared_disk}. Creating mount point at ${mount_point}..."
  mkdir -p "${mount_point}"
  norm_shared_disk=$(normalize_name "${shared_disk}")
  echo "# Mounting ${host}/${norm_shared_disk} at ${mount_point}..."
  mount_smbfs -o ro "${host}/${norm_shared_disk}" "${mount_point}"
}

#TODO: print_banner

#######################################
# Print the acquisition info.
# Arguments:
#   target, the target folder.
#   destination, the destination folder.
#   image_name, the name of the sparse image.
#   utility, the utility used for the acquisition.
# Outputs:
#   Writes the acquisition info to stdout.
#######################################
print_acquisition_info() {
  local target="${1}"
  local destination="${2}"
  local image_name="${3}"
  local utility="${4}"
cat << EOF

# Process started at ${start_datetime}

# Acquisition Info
# ----------------
# Target:       ${target}
# Destination:  ${destination}
# Image Name:   ${image_name}.sparseimage
# Utility:      ${utility}

EOF
}

#######################################
# Create a sparse image and attach it to the host.
# Globals:
#   VOLUME_NAME
# Arguments:
#   image_size, the size of the sparse image in GigaBytes.
#   destination, the destination folder where the sparse image will be created.
#   image_name, the name of the sparse image.
# Outputs:
#   Writes the backup folder and files to stdout.
#######################################
create_sparse_image() {
  local image_size=${1}
  local destination=${2}
  local image_name=${3}  # To be used as volume name

cat << EOF
# Sparse Image
# ------------
# Creating and attaching the sparse image...
EOF

  destination_fullpath="${destination}/${image_name}"
  out=$(hdiutil create -size ${image_size}g -volname ${image_name} -fs APFS -layout GPTSPUD -type SPARSE -attach ${destination_fullpath})

cat << EOF
# Sparse image created at ${destination_fullpath}. Output: 
"${out}"

EOF

  # Commentary: The volume name should be the image name unless a volume with 
  # the same name already exists. This is to get the actual volume name from the
  # output of the hdiutil command.
  VOLUME_NAME=$(echo "${out}" | sed -rn 's/.+(\/Volumes\/.+[^[:space:]]).*/\1/p')
}

#######################################
# Acquire data from the target to the attached sparse image on the host.
# Globals:
#   LOG_FILE
#   ERR_FILE
# Arguments:
#   target, the target folder.
#   volume_name, the volume name of the attached sparse image.
#   utility, the utility used for the acquisition (cp or rsync).
# Outputs:
#   Writes the paths to target and attached volume to stdout, copied files to 
#   LOG_FILE, and errors to ERR_FILE.
# Returns:
#   0 if the copy is successful, non-zero on error.
#######################################
acquire_data() {
  local target="${1}"
  local volume_name="${2}"
  local utility="${3}"

cat << EOF
#  Data Acquisition
#  ----------------
#  Acquiring data from ${target} to ${volume_name}...

EOF
  if [[ ${utility} == "cp" ]]
  then
    cp -PRpvi "${target}/" "${volume_name}" > ${LOG_FILE} 2> ${ERR_FILE} && rc=$? || rc=$?
  elif [[ ${utility} == "rsync" ]]
  then
    rsync -artvqX "${target}/" "${volume_name}/" > ${LOG_FILE} 2> ${ERR_FILE} && rc=$? || rc=$?
  fi

  echo "# ERROR: Copying data from '${target}' to '${volume_name}' with '${utility}' hash failed with code '${rc}'"
  return ${rc}
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
  hdiutil detach -force "${volume_name}"
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
    printf "# MD5:         %s" "${md5_hash}"
    printf "# SHA1:        %s" "${sha1_hash}"
  fi

  printf "# Process has completed. Output created in %s\n\n" "${destination}"
}

#######################################
# Run the acquisition process.
#######################################
run_process() {
  print_acquisition_info "${target}" "${destination}" "${image_name}" "${utility}"
  create_sparse_image "${size}" "${destination}" "${image_name}"
  trap cleanup EXIT
  acquire_data "${target}" "${VOLUME_NAME}" "${utility}"
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
  local image_name="ACQUISITION"
  local utility="cp" # Default utility for the acquisition
  local size=1000 # Default size of the disk in GigaBytes, i.e., 1TB
  local hash=
  local assisted=

  while [[ "${#}" -gt 0 ]]
  do
    case "${1}" in
      -h|--help)
        print_usage
        exit 0
        ;;
      -s|--size)
        size="${2}"
        shift 2
        ;;
      -i|--image-name)
        image_name="${2:-}"
        [[ -z "${image_name}" ]] && printf "%s must have a value\n\n" "${1}" >&2 && print_usage >&2 && exit 1
        shift 2
        ;;
      -u|--utility)
        utility="${2:-}"
        [[ -z "${utility}" ]] && printf "%s must have a value\n\n" "${1}" >&2 && print_usage >&2 && exit 1
        shift 2
        ;;
      -c|--calculate-hash)
        hash="true"
        shift
        ;;
      -a|--assisted)
        assisted="true"
        shift
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
  [[ ! $(echo "${UTILITIES[@]}" | grep -w "${utility}") ]] && printf "Unknown transfer utility. Only cp and cp are supported\n\n" >&2 && print_usage >&2 && exit 1

  # Acquisition Process

  #TODO: Give the option to change log files
  OUT_FILE="${destination}/${image_name}.out"
  LOG_FILE="${destination}/${image_name}.log"
  ERR_FILE="${destination}/${image_name}.err"

  clear -x  # Clear the screen without attempting to clear the terminal's scrollback buffer

  backup "${destination}" "${image_name}"

  start_datetime=$(date)

  if [[ ! -d "${target}" || "${assisted}" == "true" ]]
  then
    while true
    do
      read -p "# Do you want to continue in assisted mode to identify the target for you? [yn] " answer
      case $answer in
          [Yy])
            printf "# Assisted mode selected\n" | tee -a ${OUT_FILE}
            read -p "# Please provide the computer name of the target: " target_name
            read -p "# Please provide the username of the target: " target_user
            mount_shared_disk "${target_name}" "${target_user}" "${target}" | tee -a ${OUT_FILE}
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

  run_process | tee -a ${OUT_FILE}
}

main "${@:-}"