#!/usr/bin/env bash
# Sync a FOLDER to google drive forever using labbots/google-drive-upload

_usage() {
    printf "
The script can be used to sync your local folder to google drive.

Utilizes google-drive-upload bash scripts.\n
Usage: %s [options.. ]\n
Options:\n
  -d | --directory - Gdrive foldername.\n
  -k | --kill - to kill the background job using pid number ( -p flags ) or used with input, can be used multiple times.\n
  -j | --jobs - See all background jobs that were started and still running.\n
     Use --jobs v/verbose to more information for jobs.\n
  -p | --pid - Specify a pid number, used for --jobs or --kill or --info flags, can be used multiple times.\n
  -i | --info - See information about a specific sync using pid_number ( use -p flag ) or use with input, can be used multiple times.\n
  -t | --time <time_in_seconds> - Amount of time to wait before try to sync again in background.\n
     To set wait time by default, use %s -t default='3'. Replace 3 with any positive integer.\n
  -l | --logs - To show the logs after starting a job or show log of existing job. Can be used with pid number ( -p flag ).
     Note: If multiple pid numbers or inputs are used, then will only show log of first input as it goes on forever.
  -a | --arguments - Additional arguments for gupload commands. e.g: %s -a '-q -o -p 4 -d'.\n
     To set some arguments by default, use %s -a default='-q -o -p 4 -d'.\n
  -D | --debug - Display script command trace, use before all the flags to see maximum script trace.\n
  -h | --help - Display usage instructions.\n" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}"
    exit
}

_short_help() {
    printf "No valid arguments provided, use -h/--help flag to see usage.\n"
    exit
}

###################################################
# Check if a pid exists by using ps
# Globals: None
# Arguments: 1
#   ${1} = pid number of a sync job
# Result: return 0 or 1
###################################################
_check_pid() {
    { ps -p "${1}" &> /dev/null && return 0; } || return 1
}

###################################################
# Show information about a specific sync job
# Globals: 1 variable, 2 functions
#   Variable - SYNC_LIST
#   Functions - _check_pid, _setup_loop_variables
# Arguments: 1
#   ${1} = pid number of a sync job
#   ${2} = anything: Prints extra information ( optional )
#   ${3} = all information about a job ( optional )
# Result: read description
###################################################
_get_job_info() {
    declare input local_folder pid times extra
    pid="${1}"
    input="${3:-$(grep "${pid}" "${SYNC_LIST}" || :)}"
    if [[ -n ${input} ]]; then
        if _check_pid "${pid}"; then
            printf "\n%s\n" "PID: ${pid}"
            : "${input#*"|:_//_:|"}" && local_folder="${_/"|:_//_:|"*/}"
            printf "Local Folder: %s\n" "${local_folder}"
            printf "Drive Folder: %s\n" "${input/*"|:_//_:|"/}"
            times="$(ps -p "${pid}" -o etimes --no-headers)"
            printf "Running Since: %s\n" "$(_display_time "${times}")"
            if [[ -n ${2} ]]; then
                extra="$(ps -p "${pid}" -o %cpu,%mem --no-headers)"
                printf "CPU usage:%s\n" "${extra% *}"
                printf "Memory usage: %s\n" "${extra##* }"
                _setup_loop_variables "${local_folder}" "${input/*"|:_//_:|"/}"
                printf "Success: %s\n" "$(_count < "${SUCCESS_LOG}")"
                printf "Failed: %s\n" "$(_count < "${ERROR_LOG}")"
            fi
            return 0
        else
            return 1
        fi
    else
        return 11
    fi
}

###################################################
# Remove a sync job information from database
# Globals: 2 variables, 2 functions
#   Variables - SYNC_LIST, SYNC_DETAIL_DIR
#   Functions - _get_job_info, _remove_job
# Arguments: 1
#   ${1} = pid number of a sync job
# Result: read description
###################################################
_remove_job() {
    declare pid="${1}" input local_folder drive_folder
    input="$(grep "${pid}" "${SYNC_LIST}")"
    : "${input#*"|:_//_:|"}" && local_folder="${_/"|:_//_:|"*/}"
    drive_folder="${input/*"|:_//_:|"/}"
    new_list="$(grep -v "${pid}" "${SYNC_LIST}")"
    printf "%s\n" "${new_list}" >| "${SYNC_LIST}"
    rm -rf "${SYNC_DETAIL_DIR:?}/${drive_folder}${local_folder}"
    # Cleanup dir if empty
    if find "${SYNC_DETAIL_DIR:?}/${drive_folder}" -type f &> /dev/null; then
        rm -rf "${SYNC_DETAIL_DIR:?}/${drive_folder}"
    fi
}

###################################################
# Kill a sync job and do _remove_job
# Globals: 1 function
#   _remove_job
# Arguments: 1
#   ${1} = pid number of a sync job
# Result: read description
###################################################
_kill_job() {
    declare pid="${1}"
    kill -9 "${pid}" &> /dev/null
    _remove_job "${pid}"
    printf "Killed.\n"
}

###################################################
# Show total no of sync jobs running
# Globals: 1 variable, 2 functions
#   Variable - SYNC_LIST
#   Functions - _get_job_info, _remove_job
# Arguments: 1
#   ${1} = v/verbose: Prints extra information ( optional )
# Result: read description
###################################################
_show_jobs() {
    declare list pid total=0
    list="$(grep -v '^$' "${SYNC_LIST}" || :)"
    printf "%s\n" "${list}" >| "${SYNC_LIST}"
    while read -r -u 4 line; do
        if [[ -n ${line} ]]; then
            : "${line/"|:_//_:|"*/}" && pid="${_/*: /}"
            _get_job_info "${pid}" "${1}" "${line}"
            { [[ ${?} = 1 ]] && _remove_job "${pid}"; } || { ((total += 1)) && no_task="printf"; }
        fi
    done 4< "${SYNC_LIST}"
    printf "\nTotal Jobs Running: %s\n" "${total}"
    [[ v${1} = v ]] && "${no_task:-:}" "For more info: %s -j/--jobs v/verbose\n" "${0##*/}"
}

###################################################
# Setup required variables for a sync job
# Globals: 1 Variable
#   SYNC_DETAIL_DIR
# Arguments: 1
#   ${1} = Local folder name which will be synced
# Result: read description
###################################################
_setup_loop_variables() {
    declare folder="${1}" drive_folder="${2}"
    DIRECTORY="${SYNC_DETAIL_DIR}/${drive_folder}${folder}"
    PID_FILE="${DIRECTORY}/pid"
    SUCCESS_LOG="${DIRECTORY}/success_list"
    ERROR_LOG="${DIRECTORY}/failed_list"
    LOGS="${DIRECTORY}/logs"
}

###################################################
# Create folder and files for a sync job
# Globals: 4 variables
#   DIRECTORY, PID_FILE, SUCCESS_LOG, ERROR_LOG
# Arguments: None
# Result: read description
###################################################
_setup_loop_files() {
    mkdir -p "${DIRECTORY}"
    for file in PID_FILE SUCCESS_LOG ERROR_LOG; do
        printf "" >> "${!file}"
    done
    PID="$(< "${PID_FILE}")"
}

###################################################
# Check for new files in the sync folder and upload it
# A list is generated everytime, success and error.
# Globals: 4 variables, 1 function
#   Variables - SUCCESS_LOG, ERROR_LOG, COMMAND_NAME, ARGS, GDRIVE_FOLDER
#   Function  - _remove_array_duplicates
# Arguments: None
# Result: read description
###################################################
_check_and_upload() {
    declare all initial final new_files new_file

    mapfile -t initial < "${SUCCESS_LOG}"

    mapfile -t all <<< "$(printf "%s\n%s\n" "$(< "${SUCCESS_LOG}")" "$(< "${ERROR_LOG}")")"
    # check if folder is empty
    { all+=(*) && [[ ${all[1]} = "*" ]] && return 0; } || :

    mapfile -t final <<< "$(_remove_array_duplicates "${all[@]}")"

    mapfile -t new_files <<< "$(diff \
        --new-line-format="%L" \
        --old-line-format="" \
        --unchanged-line-format="" \
        <(printf "%s\n" "${initial[@]}") <(printf "%s\n" "${final[@]}"))"

    if [[ -n ${new_files[0]} ]]; then
        printf "" >| "${ERROR_LOG}"
        for new_file in "${new_files[@]}"; do
            # shellcheck disable=SC2086
            if "${COMMAND_NAME}" "${new_file}" ${ARGS} -C "${GDRIVE_FOLDER}"; then
                printf "%s\n" "${new_file}" >> "${SUCCESS_LOG}"
            else
                printf "%s\n" "${new_file}" >> "${ERROR_LOG}"
                printf "%s\n" "Error: Input - ${new_file}"
            fi
            printf "\n"
        done
    fi
}

###################################################
# Loop _check_and_upload function, sleep for sometime in between
# Globals: 1 variable, 2 function
#   Variable - SYNC_TIME_TO_SLEEP
#   Function - _check_and_upload, _bash_sleep
# Arguments: None
# Result: read description
###################################################
_loop() {
    while true; do
        _check_and_upload
        _bash_sleep "${SYNC_TIME_TO_SLEEP}"
    done
}

###################################################
# Check if a loop exists with given input
# Globals: 3 variables, 3 function
#   Variable - FOLDER, PID, GDRIVE_FOLDER
#   Function - _setup_loop_variables, _setup_loop_files, _check_pid
# Arguments: None
# Result: return 0 - No existing loop, 1 - loop exists, 2 - loop only in database
#   if return 2 - then remove entry from database
###################################################
_check_existing_loop() {
    _setup_loop_variables "${FOLDER}" "${GDRIVE_FOLDER}"
    _setup_loop_files
    if [[ -z ${PID} ]]; then
        return 0
    elif _check_pid "${PID}"; then
        return 1
    else
        _remove_job "${PID}"
        _setup_loop_variables "${FOLDER}" "${GDRIVE_FOLDER}"
        _setup_loop_files
        return 2
    fi
}

###################################################
# Start a new sync job by _loop function
# Print sync job information
# Globals: 6 variables, 1 function
#   Variable - LOGS, PID_FILE, INPUT, GDRIVE_FOLDER, FOLDER, SYNC_LIST
#   Function - _loop
# Arguments: None
# Result: read description
#   Show logs at last and don't hangup if SHOW_LOGS is set
###################################################
_start_new_loop() {
    _loop &> "${LOGS}" &
    printf "%s\n" "$!" >| "${PID_FILE}"
    PID="$(< "${PID_FILE}")"
    printf "%b\n" "Job started.\nLocal Folder: ${INPUT}\nDrive Folder: ${GDRIVE_FOLDER}"
    printf "%s\n" "PID: ${PID}"
    printf "%b\n" "PID: ${PID}|:_//_:|${FOLDER}|:_//_:|${GDRIVE_FOLDER}" >> "${SYNC_LIST}"
    { [[ -n ${SHOW_LOGS} ]] && tail -f "${LOGS}"; } || :
}

###################################################
# Triggers in case either -j & -k or -l flag ( both -k|-j if with positive integer as argument )
# Priority: -j > -i > -l > -k
# Globals: 5 variables, 6 functions
#   Variables - JOB, SHOW_JOBS_VERBOSE, INFO_PID, LOG_PID, KILL_PID ( all array )
#   Functions - _check_pid, _setup_loop_variables
#               _kill_job, _show_jobs, _get_job_info, _remove_job
# Arguments: None
# Result: show either job info, individual info or kill job(s) according to set global variables.
#   Script exits after -j and -k if kill all is triggered )
###################################################
_do_job() {
    case "${JOB[*]}" in
        *SHOW_JOBS*)
            _show_jobs "${SHOW_JOBS_VERBOSE:-}"
            exit
            ;;
        *KILL_ALL*)
            PIDS="$(_show_jobs | grep -o 'PID:.*[0-9]' | sed "s/PID: //g" || :)" && total=0
            if [[ -n ${PIDS} ]]; then
                for _pid in ${PIDS}; do
                    printf "PID: %s - " "${_pid##* }"
                    _kill_job "${_pid##* }"
                    ((total += 1))
                done
            fi
            printf "\nTotal Jobs Killed: %s\n" "${total}"
            exit
            ;;
        *PIDS*)
            for pid in "${ALL_PIDS[@]}"; do
                if [[ ${JOB_TYPE} =~ INFO ]]; then
                    _get_job_info "${pid}" more
                    status="${?}"
                    if [[ ${status} != 0 ]]; then
                        { [[ ${status} = 1 ]] && _remove_job "${pid}"; } || :
                        printf "No job running with given PID ( %s ).\n" "${pid}" 1>&2
                    fi
                fi
                if [[ ${JOB_TYPE} =~ SHOW_LOGS ]]; then
                    input="$(grep "${pid}" "${SYNC_LIST}" || :)"
                    if [[ -n ${input} ]]; then
                        if _check_pid "${pid}"; then
                            : "${input#*"|:_//_:|"}" && local_folder="${_/"|:_//_:|"*/}"
                            _setup_loop_variables "${local_folder}" "${input/*"|:_//_:|"/}"
                            tail -f "${LOGS}"
                        fi
                    else
                        printf "No job running with given PID ( %s ).\n" "${pid}" 1>&2
                    fi
                fi
                if [[ ${JOB_TYPE} =~ KILL ]]; then
                    _get_job_info "${pid}"
                    status="${?}"
                    if [[ ${status} = 0 ]]; then
                        _kill_job "${pid}"
                    else
                        { [[ ${status} = 1 ]] && _remove_job "${pid}"; } || :
                        printf "No job running with given PID ( %s ).\n" "${pid}" 1>&2
                    fi
                fi
            done
            if [[ ${JOB_TYPE} =~ (INFO|SHOW_LOGS|KILL) ]]; then
                exit
            fi
            ;;
    esac
}

###################################################
# Process all arguments given to the script
# Globals: 1 variable, 4 functions
#   Variable - HOME
#   Functions - _kill_jobs, _show_jobs, _get_job_info, _remove_array_duplicates
# Arguments: Many
#   ${@} = Flags with arguments
# Result: On
#   Success - Set all the variables
#   Error   - Print error message and exit
###################################################
_setup_arguments() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare -g SYNC_TIME_TO_SLEEP ARGS COMMAND_NAME DEBUG GDRIVE_FOLDER KILL SHOW_LOGS

    INFO_PATH="${HOME}/.google-drive-upload"
    SYNC_DETAIL_DIR="${INFO_PATH}/sync"
    SYNC_LIST="${SYNC_DETAIL_DIR}/sync_list"
    mkdir -p "${SYNC_DETAIL_DIR}" && printf "" >> "${SYNC_LIST}"

    # Grab the first arg and shift, only if ${1} doesn't contain -.
    { ! [[ ${1} = -* ]] && INPUT_ARRAY+=("${1}") && shift; } || :

    _check_longoptions() {
        { [[ -z ${2} ]] &&
            printf '%s: %s: option requires an argument\nTry '"%s -h/--help"' for more information.\n' \
                "${0##*/}" "${1}" "${0##*/}" && exit 1; } || :
    }

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h | --help)
                _usage
                ;;
            -D | --debug)
                DEBUG="true" && export DEBUG
                _check_debug
                ;;
            -d | --directory)
                _check_longoptions "${1}" "${2}"
                GDRIVE_FOLDER="${2}" && shift
                ;;
            -j | --jobs)
                { [[ ${2} = v* ]] && SHOW_JOBS_VERBOSE="true" && shift; } || :
                JOB=(SHOW_JOBS)
                ;;
            -p | --pid)
                _check_longoptions "${1}" "${2}"
                if [[ ${2} =~ ^([0-9]+)+$ ]]; then
                    ALL_PIDS+=("${2}") && shift
                    JOB+=(PIDS)
                else
                    printf "-p/--pid only takes postive integer as arguments.\n"
                    exit 1
                fi
                ;;
            -i | --info)
                JOB_TYPE+="INFO"
                INFO="true"
                ;;
            -k | --kill)
                JOB_TYPE+="KILL"
                KILL="true"
                if [[ ${2} = all ]]; then
                    JOB=(KILL_ALL) && shift
                fi
                ;;
            -l | --logs)
                JOB_TYPE+="SHOW_LOGS"
                SHOW_LOGS="true"
                ;;
            -t | --time)
                _check_longoptions "${1}" "${2}"
                if [[ ${2} =~ ^([0-9]+)+$ ]]; then
                    { [[ ${2} = default* ]] && UPDATE_DEFAULT_TIME_TO_SLEEP="_update_config"; } || :
                    TO_SLEEP="${2/default=/}" && shift
                else
                    printf "-t/--time only takes positive integers as arguments, min = 1, max = infinity.\n"
                    exit 1
                fi
                ;;
            -a | --arguments)
                _check_longoptions "${1}" "${2}"
                { [[ ${2} = default* ]] && UPDATE_DEFAULT_ARGS="_update_config"; } || :
                ARGS+="${2/default=/} " && shift
                ;;
            '')
                shorthelp
                ;;
            *)
                # Check if user meant it to be a flag
                if [[ ${1} = -* ]]; then
                    printf '%s: %s: Unknown option\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${1}" "${0##*/}" && exit 1
                else
                    # If no "-" is detected in 1st arg, it adds to input
                    INPUT_ARRAY+=("${1}")
                fi
                ;;
        esac
        shift
    done

    _do_job

    if [[ -z ${INPUT_ARRAY[0]} ]]; then
        _short_help
    else
        # check if given input exists ( file/folder )
        for array in "${INPUT_ARRAY[@]}"; do
            { [[ -d ${array} ]] && FINAL_INPUT_ARRAY+=("${array[@]}"); } || {
                printf "\nError: Invalid Input ( %s ), no such directory.\n" "${array}"
                exit 1
            }
        done
    fi

    mapfile -t FINAL_INPUT_ARRAY <<< "$(_remove_array_duplicates "${FINAL_INPUT_ARRAY[@]}")"
}

###################################################
# Grab config variables and modify defaults if necessary
# Globals: 5 variables, 2 functions
#   Variables - INFO_PATH, UPDATE_DEFAULT_CONFIG, DEFAULT_ARGS
#               UPDATE_DEFAULT_ARGS, UPDATE_DEFAULT_TIME_TO_SLEEP, TIME_TO_SLEEP
#   Functions - _print_center, _update_config
# Arguments: None
# Result: source .info file, grab COMMAND_NAME and CONFIG
#   source CONFIG, update default values if required
###################################################
_config_variables() {
    if [[ -f "${INFO_PATH}/google-drive-upload.info" ]]; then
        # shellcheck source=/dev/null
        source "${INFO_PATH}/google-drive-upload.info"
    else
        _print_center "justify" "google-drive-upload is not installed system wide." "=" 1>&2
        exit 1
    fi

    # Check if command exist, not necessary but just in case.
    if ! type "${COMMAND_NAME}" &> /dev/null; then
        printf "Error: %s is not installed, use -c/--command to specify.\n" "${COMMAND_NAME}" 1>&2
        exit 1
    fi

    ARGS+=" -q "
    SYNC_TIME_TO_SLEEP="3"
    # Config file is created automatically after first run
    if [[ -r ${CONFIG} ]]; then
        # shellcheck source=/dev/null
        source "${CONFIG}"
        if [[ -n ${UPDATE_DEFAULT_CONFIG} ]]; then
            printf "%s\n" "${CONFIG}" >| "${INFO_PATH}/google-drive-upload.configpath"
        fi
    fi
    SYNC_TIME_TO_SLEEP="${TO_SLEEP:-${SYNC_TIME_TO_SLEEP}}"
    ARGS+=" ${SYNC_DEFAULT_ARGS:-} "
    "${UPDATE_DEFAULT_ARGS:-:}" SYNC_DEFAULT_ARGS " ${ARGS} " "${CONFIG}"
    "${UPDATE_DEFAULT_TIME_TO_SLEEP:-:}" SYNC_TIME_TO_SLEEP "${SYNC_TIME_TO_SLEEP}" "${CONFIG}"
}

###################################################
# Process all the values in "${FINAL_INPUT_ARRAY[@]}"
# Globals: 20 variables, 15 functions
#   Variables - FINAL_INPUT_ARRAY ( array ), GDRIVE_FOLDER, PID_FILE, SHOW_LOGS, LOGS
#   Functions - _setup_loop_variables, _setup_loop_files, _start_new_loop, _check_pid, _kill_job
#               _remove_job, _start_new_loop
# Arguments: None
# Result: Start the sync jobs for given folders, if running already, don't start new.
#   If a pid is detected but not running, remove that job.
###################################################
_process_arguments() {
    declare INPUT status CURRENT_FOLDER
    for INPUT in "${FINAL_INPUT_ARRAY[@]}"; do
        CURRENT_FOLDER="$(pwd)"
        FOLDER="$(cd "${INPUT}" && pwd)" || exit 1
        GDRIVE_FOLDER="${GDRIVE_FOLDER:-${FOLDER##*/}}"
        cd "${FOLDER}" || exit 1
        _check_existing_loop
        status="$?"
        case "${status}" in
            0 | 2)
                _start_new_loop
                ;;
            1)
                printf "%b\n" "Job is already running.."
                if [[ -n ${INFO} ]]; then
                    _get_job_info "${PID}" more "PID: ${PID}|:_//_:|${FOLDER}|:_//_:|${GDRIVE_FOLDER}"
                else
                    printf "%b\n" "Local Folder: ${INPUT}\nDrive Folder: ${GDRIVE_FOLDER}"
                    printf "%s\n" "PID: ${PID}"
                fi
                if [[ -n ${KILL} ]]; then
                    _kill_job "${PID}"
                    exit
                fi
                { [[ -n ${SHOW_LOGS} ]] && tail -f "${LOGS}"; } || :
                ;;
        esac
        cd "${CURRENT_FOLDER}" || exit 1
    done
}

main() {
    [[ $# = 0 ]] && _short_help

    UTILS_FILE="${UTILS_FILE:-./utils.sh}"
    if [[ -r ${UTILS_FILE} ]]; then
        # shellcheck source=/dev/null
        source "${UTILS_FILE}" || { printf "Error: Unable to source utils file ( %s ) .\n" "${UTILS_FILE}" 1>&2 && exit 1; }
    else
        printf "Error: Utils file ( %s ) not found\n" "${UTILS_FILE}" 1>&2
        exit 1
    fi

    _setup_arguments "${@}"
    _config_variables
    _process_arguments
}

main "${@}"
