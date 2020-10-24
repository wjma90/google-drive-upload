#!/usr/bin/env bash
# Upload a file to Google Drive
# shellcheck source=/dev/null

_usage() {
    printf "%b" "
The script can be used to upload file/directory to google drive.\n
Usage:\n ${0##*/} [options.. ] <filename> <foldername>\n
Foldername argument is optional. If not provided, the file will be uploaded to preconfigured google drive.\n
File name argument is optional if create directory option is used.\n
Options:\n
  -c | -C | --create-dir <foldername> - option to create directory. Will provide folder id. Can be used to provide input folder, see README.\n
  -r | --root-dir <google_folderid> or <google_folder_url> - google folder ID/URL to which the file/directory is going to upload.
      If you want to change the default value, then use this format, -r/--root-dir default=root_folder_id/root_folder_url\n
  -s | --skip-subdirs - Skip creation of sub folders and upload all files inside the INPUT folder/sub-folders in the INPUT folder, use this along with -p/--parallel option to speed up the uploads.\n
  -p | --parallel <no_of_files_to_parallely_upload> - Upload multiple files in parallel, Max value = 10.\n
  -f | --[file|folder] - Specify files and folders explicitly in one command, use multiple times for multiple folder/files. See README for more use of this command.\n
  -cl | --clone - Upload a gdrive file without downloading, require accessible gdrive link or id as argument.\n
  -o | --overwrite - Overwrite the files with the same name, if present in the root folder/input folder, also works with recursive folders.\n
  -d | --skip-duplicates - Do not upload the files with the same name, if already present in the root folder/input folder, also works with recursive folders.\n
  -S | --share <optional_email_address>- Share the uploaded input file/folder, grant reader permission to provided email address or to everyone with the shareable link.\n
  --speed 'speed' - Limit the download speed, supported formats: 1K, 1M and 1G.\n
  -i | --save-info <file_to_save_info> - Save uploaded files info to the given filename.\n
  -z | --config <config_path> - Override default config file with custom config file.\nIf you want to change default value, then use this format -z/--config default=default=your_config_file_path.\n
  -q | --quiet - Supress the normal output, only show success/error upload messages for files, and one extra line at the beginning for folder showing no. of files and sub folders.\n
  -R | --retry 'num of retries' - Retry the file upload if it fails, postive integer as argument. Currently only for file uploads.\n
  -in | --include 'pattern' - Only include the files with the given pattern to upload - Applicable for folder uploads.\n
      e.g: ${0##*/} local_folder --include "*1*", will only include with files with pattern '1' in the name.\n
  -ex | --exclude 'pattern' - Exclude the files with the given pattern from uploading. - Applicable for folder uploads.\n
      e.g: ${0##*/} local_folder --exclude "*1*", will exclude all the files pattern '1' in the name.\n
  --hide - This flag will prevent the script to print sensitive information like root folder id or drivelink.\n
  -v | --verbose - Display detailed message (only for non-parallel uploads).\n
  -V | --verbose-progress - Display detailed message and detailed upload progress(only for non-parallel uploads).\n
  --skip-internet-check - Do not check for internet connection, recommended to use in sync jobs.\n
  -u | --update - Update the installed script in your system.\n
  --info - Show detailed info, only if script is installed system wide.\n
  -U | --uninstall - Uninstall script, remove related files.\n
  -D | --debug - Display script command trace.\n
  -h | --help - Display this message.\n"
    exit 0
}

_short_help() {
    printf "No valid arguments provided, use -h/--help flag to see usage.\n"
    exit 0
}

###################################################
# Automatic updater, only update if script is installed system wide.
# Globals: 5 variables, 2 functions
#   COMMAND_NAME, REPO, INSTALL_PATH, TYPE, TYPE_VALUE | _update, _update_value
# Arguments: None
# Result: On
#   Update if AUTO_UPDATE_INTERVAL + LAST_UPDATE_TIME less than printf "%(%s)T\\n" "-1"
###################################################
_auto_update() {
    export REPO
    (
        _REPO="${REPO}"
        command -v "${COMMAND_NAME}" 1> /dev/null &&
            if [[ -n "${_REPO:+${COMMAND_NAME:+${INSTALL_PATH:+${TYPE:+${TYPE_VALUE}}}}}" ]]; then
                current_time="$(printf "%(%s)T\\n" "-1")"
                [[ $((LAST_UPDATE_TIME + AUTO_UPDATE_INTERVAL)) -lt ${current_time} ]] && _update
                _update_value LAST_UPDATE_TIME "${current_time}"
            fi
    ) 2>| /dev/null 1>&2 &
    return 0
}

###################################################
# Install/Update/uninstall the script.
# Globals: 4 variables
#   Varibles - HOME, REPO, TYPE_VALUE, GLOBAL_INSTALL
# Arguments: 1
#   ${1} = uninstall or update
# Result: On
#   ${1} = nothing - Update the script if installed, otherwise install.
#   ${1} = uninstall - uninstall the script
###################################################
_update() {
    declare job="${1:-update}"
    [[ ${GLOBAL_INSTALL} = true ]] && ! [[ $(id -u) = 0 ]] && printf "%s\n" "Error: Need root access to update." && return 0
    [[ ${job} =~ uninstall ]] && job_uninstall="--uninstall"
    _print_center "justify" "Fetching ${job} script.." "-"
    declare repo="${REPO:-labbots/google-drive-upload}" type_value="${TYPE_VALUE:-latest}" cmd="${COMMAND_NAME:-gupload}" path="${INSTALL_PATH:-${HOME}/.google-drive-upload/bin}"
    { [[ ${TYPE:-} != branch ]] && type_value="$(_get_latest_sha release "${type_value}" "${repo}")"; } || :
    if script="$(curl --compressed -Ls "https://github.com/${repo}/raw/${type_value}/install.sh")"; then
        _clear_line 1
        printf "%s\n" "${script}" | bash -s -- ${job_uninstall:-} --skip-internet-check --cmd "${cmd}" --path "${path}"
        current_time="$(printf "%(%s)T\\n" "-1")"
        [[ -z ${job_uninstall} ]] && _update_value LAST_UPDATE_TIME "${current_time}" &
    else
        _clear_line 1
        "${QUIET:-_print_center}" "justify" "Error: Cannot download ${job} script." "=" 1>&2
        return 1
    fi
    return 0
}

###################################################
# Update in-script values
###################################################
_update_value() {
    declare command_path="${INSTALL_PATH:?}/${COMMAND_NAME}" \
        value_name="${1:-}" value="${2:-}" script_without_value_and_shebang
    script_without_value_and_shebang="$(grep -v "${value_name}=\".*\".* # added values" "${command_path}" | sed 1d)"
    new_script="$(
        sed -n 1p "${command_path}"
        printf "%s\n" "${value_name}=\"${value}\" # added values"
        printf "%s\n" "${script_without_value_and_shebang}"
    )"
    chmod +w "${command_path}" && printf "%s\n" "${new_script}" >| "${command_path}" && chmod -w "${command_path}"
    return 0
}

###################################################
# Print info if installed
# Globals: 7 variable
#   COMMAND_NAME REPO INSTALL_PATH INSTALLATION TYPE TYPE_VALUE LATEST_INSTALLED_SHA
# Arguments: None
# Result: read description
###################################################
_version_info() {
    if command -v "${COMMAND_NAME}" 1> /dev/null && [[ -n "${REPO:+${COMMAND_NAME:+${INSTALL_PATH:+${TYPE:+${TYPE_VALUE}}}}}" ]]; then
        for i in REPO INSTALL_PATH INSTALLATION TYPE TYPE_VALUE LATEST_INSTALLED_SHA CONFIG; do
            printf "%s\n" "${i}=\"${!i}\""
        done | sed -e "s/=/: /g"
    else
        printf "%s\n" "google-drive-upload is not installed system wide."
    fi
    exit 0
}

###################################################
# Process all arguments given to the script
# Globals: 2 variable, 1 function
#   Variable - HOME, CONFIG
#   Functions - _short_help
# Arguments: Many
#   ${@} = Flags with argument and file/folder input
# Result: On
#   Success - Set all the variables
#   Error   - Print error message and exit
# Reference:
#   Email Regex - https://stackoverflow.com/a/57295993
###################################################
_setup_arguments() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    # Internal variables
    # De-initialize if any variables set already.
    unset FIRST_INPUT FOLDER_INPUT FOLDERNAME LOCAL_INPUT_ARRAY ID_INPUT_ARRAY
    unset PARALLEL NO_OF_PARALLEL_JOBS SHARE SHARE_EMAIL OVERWRITE SKIP_DUPLICATES SKIP_SUBDIRS ROOTDIR QUIET
    unset VERBOSE VERBOSE_PROGRESS DEBUG LOG_FILE_ID CURL_SPEED RETRY
    CURL_PROGRESS="-s" EXTRA_LOG=":" CURL_PROGRESS_EXTRA="-s"
    INFO_PATH="${HOME}/.google-drive-upload" CONFIG_INFO="${INFO_PATH}/google-drive-upload.configpath"
    [[ -f ${CONFIG_INFO} ]] && . "${CONFIG_INFO}"
    CONFIG="${CONFIG:-${HOME}/.googledrive.conf}"

    # Configuration variables # Remote gDrive variables
    unset ROOT_FOLDER CLIENT_ID CLIENT_SECRET REFRESH_TOKEN ACCESS_TOKEN
    API_URL="https://www.googleapis.com"
    API_VERSION="v3"
    SCOPE="${API_URL}/auth/drive"
    REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"
    TOKEN_URL="https://accounts.google.com/o/oauth2/token"

    _check_config() {
        [[ ${1} = default* ]] && export UPDATE_DEFAULT_CONFIG="_update_config"
        { [[ -r ${2} ]] && CONFIG="${2}"; } || {
            printf "Error: Given config file (%s) doesn't exist/not readable,..\n" "${1}" 1>&2 && exit 1
        }
        return 0
    }

    _check_longoptions() {
        [[ -z ${2} ]] &&
            printf '%s: %s: option requires an argument\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${1}" "${0##*/}" &&
            exit 1
        return 0
    }

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h | --help) _usage ;;
            -D | --debug) DEBUG="true" && export DEBUG ;;
            -u | --update) _check_debug && _update && exit "${?}" ;;
            --uninstall) _check_debug && _update uninstall && exit "${?}" ;;
            --info) _version_info ;;
            -c | -C | --create-dir)
                _check_longoptions "${1}" "${2}"
                FOLDERNAME="${2}" && shift
                ;;
            -r | --root-dir)
                _check_longoptions "${1}" "${2}"
                ROOTDIR="${2/default=/}"
                [[ ${2} = default* ]] && UPDATE_DEFAULT_ROOTDIR="_update_config"
                shift
                ;;
            -z | --config)
                _check_longoptions "${1}" "${2}"
                _check_config "${2}" "${2/default=/}"
                shift
                ;;
            -i | --save-info)
                _check_longoptions "${1}" "${2}"
                LOG_FILE_ID="${2}" && shift
                ;;
            -s | --skip-subdirs) SKIP_SUBDIRS="true" ;;
            -p | --parallel)
                _check_longoptions "${1}" "${2}"
                NO_OF_PARALLEL_JOBS="${2}"
                if [[ ${2} -gt 0 ]]; then
                    NO_OF_PARALLEL_JOBS="$((NO_OF_PARALLEL_JOBS > 10 ? 10 : NO_OF_PARALLEL_JOBS))"
                else
                    printf "\nError: -p/--parallel value ranges between 1 to 10.\n"
                    exit 1
                fi
                PARALLEL_UPLOAD="parallel" && shift
                ;;
            -o | --overwrite) OVERWRITE="Overwrite" && UPLOAD_MODE="update" ;;
            -d | --skip-duplicates) SKIP_DUPLICATES="Skip Existing" && UPLOAD_MODE="update" ;;
            -f | --file | --folder)
                _check_longoptions "${1}" "${2}"
                LOCAL_INPUT_ARRAY+=("${2}") && shift
                ;;
            -cl | --clone)
                _check_longoptions "${1}" "${2}"
                FINAL_ID_INPUT_ARRAY+=("$(_extract_id "${2}")") && shift
                ;;
            -S | --share)
                SHARE="_share_id"
                EMAIL_REGEX="^([A-Za-z]+[A-Za-z0-9]*\+?((\.|\-|\_)?[A-Za-z]+[A-Za-z0-9]*)*)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"
                [[ -n ${1} && ! ${1} = -* ]] && SHARE_EMAIL="${2}" && {
                    ! [[ ${SHARE_EMAIL} =~ ${EMAIL_REGEX} ]] && printf "\nError: Provided email address for share option is invalid.\n" && exit 1
                    shift
                }
                ;;
            --speed)
                _check_longoptions "${1}" "${2}"
                regex='^([0-9]+)([k,K]|[m,M]|[g,G])+$'
                if [[ ${2} =~ ${regex} ]]; then
                    CURL_SPEED="--limit-rate ${2}" && shift
                else
                    printf "Error: Wrong speed limit format, supported formats: 1K , 1M and 1G\n" 1>&2
                    exit 1
                fi
                ;;
            -R | --retry)
                _check_longoptions "${1}" "${2}"
                if [[ ${2} -gt 0 ]]; then
                    RETRY="${2}" && shift
                else
                    printf "Error: -R/--retry only takes positive integers as arguments, min = 1, max = infinity.\n"
                    exit 1
                fi
                ;;
            -in | --include)
                _check_longoptions "${1}" "${2}"
                INCLUDE_FILES="${INCLUDE_FILES} -name '${2}' " && shift
                ;;
            -ex | --exclude)
                _check_longoptions "${1}" "${2}"
                EXCLUDE_FILES="${EXCLUDE_FILES} ! -name '${2}' " && shift
                ;;
            --hide) HIDE_INFO=":" ;;
            -q | --quiet) QUIET="_print_center_quiet" ;;
            -v | --verbose) VERBOSE="true" ;;
            -V | --verbose-progress) VERBOSE_PROGRESS="true" ;;
            --skip-internet-check) SKIP_INTERNET_CHECK=":" ;;
            '') shorthelp ;;
            *) # Check if user meant it to be a flag
                if [[ ${1} = -* ]]; then
                    printf '%s: %s: Unknown option\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${1}" "${0##*/}" && exit 1
                else
                    if [[ ${1} =~ (drive.google.com|docs.google.com) ]]; then
                        FINAL_ID_INPUT_ARRAY+=("$(_extract_id "${1}")")
                    else
                        # If no "-" is detected in 1st arg, it adds to input
                        LOCAL_INPUT_ARRAY+=("${1}")
                    fi
                fi
                ;;
        esac
        shift
    done

    _check_debug

    [[ -n ${VERBOSE_PROGRESS} ]] && unset VERBOSE && CURL_PROGRESS=""
    [[ -n ${QUIET} ]] && CURL_PROGRESS="-s"

    # Get foldername, prioritise the input given by -C/--create-dir option.
    FOLDERNAME="$(_extract_id "${FOLDERNAME:-${FOLDER_INPUT}}")"

    unset Aseen && declare -A Aseen
    for input in "${LOCAL_INPUT_ARRAY[@]}"; do
        { [[ ${Aseen[${input}]} ]] && continue; } || Aseen[${input}]=x
        { [[ -r ${input} ]] && FINAL_LOCAL_INPUT_ARRAY+=("${input}"); } || {
            { "${QUIET:-_print_center}" 'normal' "[ Error: Invalid Input - ${input} ]" "=" && printf "\n"; } 1>&2
            continue
        }
    done

    # If no input, then check if -C option was used or not.
    [[ -z ${FINAL_LOCAL_INPUT_ARRAY[*]:-${FINAL_ID_INPUT_ARRAY[*]:-${FOLDERNAME}}} ]] && _short_help

    # create info path folder, can be missing if gupload was not installed with install.sh
    mkdir -p "${INFO_PATH}"

    return 0
}

###################################################
# Check Oauth credentials and create/update config file
# Client ID, Client Secret, Refesh Token and Access Token
# Globals: 10 variables, 3 functions
#   Variables - API_URL, API_VERSION, TOKEN URL,
#               CONFIG, UPDATE_DEFAULT_CONFIG, INFO_PATH,
#               CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN and ACCESS_TOKEN
#   Functions - _update_config, _update_value, _json_value and _print_center
# Arguments: None
# Result: read description
###################################################
_check_credentials() {
    # Config file is created automatically after first run
    [[ -r ${CONFIG} ]] && . "${CONFIG}"
    "${UPDATE_DEFAULT_CONFIG:-:}" CONFIG "${CONFIG}" "${CONFIG_INFO}"

    ! [[ -t 1 ]] && [[ -z ${CLIENT_ID:+${CLIENT_SECRET:+${REFRESH_TOKEN}}} ]] && {
        printf "%s\n" "Error: Script is not running in a terminal, cannot ask for credentials."
        printf "%s\n" "Add in config manually if terminal is not accessible. CLIENT_ID, CLIENT_SECRET and REFRESH_TOKEN is required." && return 1
    }

    until [[ -n ${CLIENT_ID} ]]; do
        [[ -n ${client_id} ]] && for _ in 1 2 3; do _clear_line 1; done
        printf "\n" && "${QUIET:-_print_center}" "normal" " Client ID " "-" && printf -- "-> "
        read -r CLIENT_ID && client_id=1
    done && [[ -n ${client_id} ]] && _update_config CLIENT_ID "${CLIENT_ID}" "${CONFIG}"

    until [[ -n ${CLIENT_SECRET} ]]; do
        [[ -n ${client_secret} ]] && for _ in 1 2 3; do _clear_line 1; done
        printf "\n" && "${QUIET:-_print_center}" "normal" " Client Secret " "-" && printf -- "-> "
        read -r CLIENT_SECRET && client_secret=1
    done && [[ -n ${client_secret} ]] && _update_config CLIENT_SECRET "${CLIENT_SECRET}" "${CONFIG}"

    # Method to obtain refresh_token.
    # Requirements: client_id, client_secret and authorization code.
    [[ -z ${REFRESH_TOKEN} ]] && {
        printf "\n" && "${QUIET:-_print_center}" "normal" "If you have a refresh token generated, then type the token, else leave blank and press return key.." " "
        printf "\n" && "${QUIET:-_print_center}" "normal" " Refresh Token " "-" && printf -- "-> "
        read -r REFRESH_TOKEN
        if [[ -n ${REFRESH_TOKEN} ]]; then
            printf "\n\n" && _get_access_token_and_update && _update_config REFRESH_TOKEN "${REFRESH_TOKEN}" "${CONFIG}"
        else
            for _ in 1 2; do _clear_line 1; done
            "${QUIET:-_print_center}" "normal" "Visit the below URL, tap on allow and then enter the code obtained" " "
            URL="https://accounts.google.com/o/oauth2/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPE}&response_type=code&prompt=consent"
            printf "\n%s\n" "${URL}"
            until [[ -n ${CODE} ]]; do
                [[ -n ${code} ]] && for _ in 1 2 3; do _clear_line 1; done
                printf "\n" && "${QUIET:-_print_center}" "normal" "Enter the authorization code" "-" && printf -- "-> "
                read -r CODE && code=1
            done
            RESPONSE="$(curl --compressed "${CURL_PROGRESS_EXTRA}" -X POST \
                --data "code=${CODE}&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&redirect_uri=${REDIRECT_URI}&grant_type=authorization_code" "${TOKEN_URL}")" || :
            _clear_line 1 1>&2

            REFRESH_TOKEN="$(_json_value refresh_token 1 1 <<< "${RESPONSE}" || :)"
            { _get_access_token_and_update "${RESPONSE}" && _update_config REFRESH_TOKEN "${REFRESH_TOKEN}" "${CONFIG}"; } || return 1
        fi
    }

    [[ -z ${ACCESS_TOKEN} || ${ACCESS_TOKEN_EXPIRY:-0} -lt "$(printf "%(%s)T\\n" "-1")" ]] && { _get_access_token_and_update || return 1; }

    # launch a background service to check access token and update it
    # checks ACCESS_TOKEN_EXPIRY, try to update before 5 mins of expiry, a fresh token gets 60 mins
    # process will be killed when script exits
    {
        while :; do
            # print access token to tmpfile so every function can source it and get access_token value
            printf "%s\n" "export ACCESS_TOKEN=\"${ACCESS_TOKEN}\"" >| "${TMPFILE}_ACCESS_TOKEN"
            CURRENT_TIME="$(printf "%(%s)T\\n" "-1")"
            REMAINING_TOKEN_TIME="$((ACCESS_TOKEN_EXPIRY - CURRENT_TIME))"
            if [[ ${REMAINING_TOKEN_TIME} -le 300 ]]; then
                # timeout after 30 seconds, it shouldn't take too long anyway
                _timeout 30 _get_access_token_and_update || :
            else
                TOKEN_PROCESS_TIME_TO_SLEEP="$(if [[ ${REMAINING_TOKEN_TIME} -le 301 ]]; then
                    printf "0\n"
                else
                    printf "%s\n" "$((REMAINING_TOKEN_TIME - 300))"
                fi)"
                sleep "${TOKEN_PROCESS_TIME_TO_SLEEP}"
            fi
            sleep 1
        done
    } &
    ACCESS_TOKEN_SERVICE_PID="${!}"

    return 0
}

###################################################
# Setup root directory where all file/folders will be uploaded/updated
# Globals: 5 variables, 5 functions
#   Variables - ROOTDIR, ROOT_FOLDER, UPDATE_DEFAULT_ROOTDIR, CONFIG, QUIET
#   Functions - _print_center, _drive_info, _extract_id, _update_config, _json_value
# Arguments: 1
#   ${1} = Positive integer ( amount of time in seconds to sleep )
# Result: read description
#   If root id not found then pribt message and exit
#   Update config with root id and root id name if specified
# Reference:
#   https://github.com/dylanaraps/pure-bash-bible#use-read-as-an-alternative-to-the-sleep-command
###################################################
_setup_root_dir() {
    _check_root_id() {
        declare json rootid
        json="$(_drive_info "$(_extract_id "${ROOT_FOLDER}")" "id")"
        if ! rootid="$(_json_value id 1 1 <<< "${json}")"; then
            { [[ ${json} =~ "File not found" ]] && "${QUIET:-_print_center}" "justify" "Given root folder" " ID/URL invalid." "=" 1>&2; } || {
                printf "%s\n" "${json}" 1>&2
            }
            return 1
        fi
        ROOT_FOLDER="${rootid}"
        "${1:-:}" ROOT_FOLDER "${ROOT_FOLDER}" "${CONFIG}"
        return 0
    }
    _check_root_id_name() {
        ROOT_FOLDER_NAME="$(_drive_info "$(_extract_id "${ROOT_FOLDER}")" "name" | _json_value name || :)"
        "${1:-:}" ROOT_FOLDER_NAME "${ROOT_FOLDER_NAME}" "${CONFIG}"
        return 0
    }

    if [[ -n ${ROOTDIR:-} ]]; then
        ROOT_FOLDER="${ROOTDIR}" && { _check_root_id "${UPDATE_DEFAULT_ROOTDIR}" || return 1; } && unset ROOT_FOLDER_NAME
    elif [[ -z ${ROOT_FOLDER} ]]; then
        { [[ -t 1 ]] && "${QUIET:-_print_center}" "normal" "Enter root folder ID or URL, press enter for default ( root )" " " && printf -- "-> " &&
            read -r ROOT_FOLDER && [[ -n ${ROOT_FOLDER} ]] && { _check_root_id _update_config || return 1; }; } || {
            ROOT_FOLDER="root"
            _update_config ROOT_FOLDER "${ROOT_FOLDER}" "${CONFIG}"
        }
    fi

    [[ -z ${ROOT_FOLDER_NAME} ]] && _check_root_id_name "${UPDATE_DEFAULT_ROOTDIR}"

    return 0
}

###################################################
# Setup Workspace folder
# Check if the given folder exists in google drive.
# If not then the folder is created in google drive under the configured root folder.
# Globals: 2 variables, 3 functions
#   Variables - FOLDERNAME, ROOT_FOLDER
#   Functions - _create_directory, _drive_info, _json_value
# Arguments: None
# Result: Read Description
###################################################
_setup_workspace() {
    if [[ -z ${FOLDERNAME} ]]; then
        WORKSPACE_FOLDER_ID="${ROOT_FOLDER}"
        WORKSPACE_FOLDER_NAME="${ROOT_FOLDER_NAME}"
    else
        WORKSPACE_FOLDER_ID="$(_create_directory "${FOLDERNAME}" "${ROOT_FOLDER}")" ||
            { printf "%s\n" "${WORKSPACE_FOLDER_ID}" 1>&2 && return 1; }
        WORKSPACE_FOLDER_NAME="$(_drive_info "${WORKSPACE_FOLDER_ID}" name | _json_value name 1 1)" ||
            { printf "%s\n" "${WORKSPACE_FOLDER_NAME}" 1>&2 && return 1; }
    fi
    return 0
}

###################################################
# Process all the values in "${FINAL_LOCAL_INPUT_ARRAY[@]}" & "${FINAL_ID_INPUT_ARRAY[@]}"
# Globals: 22 variables, 17 functions
#   Variables - FINAL_LOCAL_INPUT_ARRAY ( array ), ACCESS_TOKEN, VERBOSE, VERBOSE_PROGRESS
#               WORKSPACE_FOLDER_ID, UPLOAD_MODE, SKIP_DUPLICATES, OVERWRITE, SHARE,
#               UPLOAD_STATUS, COLUMNS, API_URL, API_VERSION, TOKEN_URL, LOG_FILE_ID
#               FILE_ID, FILE_LINK, FINAL_ID_INPUT_ARRAY ( array )
#               PARALLEL_UPLOAD, QUIET, NO_OF_PARALLEL_JOBS, TMPFILE
#   Functions - _print_center, _clear_line, _newline, _support_ansi_escapes, _print_center_quiet
#               _upload_file, _share_id, _is_terminal, _dirname,
#               _create_directory, _json_value, _url_encode, _check_existing_file, _bytes_to_human
#               _clone_file, _get_access_token_and_update, _get_rootdir_id
# Arguments: None
# Result: Upload/Clone all the input files/folders, if a folder is empty, print Error message.
###################################################
_process_arguments() {
    export API_URL API_VERSION TOKEN_URL ACCESS_TOKEN \
        LOG_FILE_ID OVERWRITE UPLOAD_MODE SKIP_DUPLICATES CURL_SPEED RETRY UTILS_FOLDER TMPFILE \
        QUIET VERBOSE VERBOSE_PROGRESS CURL_PROGRESS CURL_PROGRESS_EXTRA CURL_PROGRESS_EXTRA_CLEAR COLUMNS EXTRA_LOG PARALLEL_UPLOAD

    export -f _bytes_to_human _dirname _json_value _url_encode _support_ansi_escapes _newline _print_center_quiet _print_center _clear_line \
        _api_request _get_access_token_and_update _check_existing_file _upload_file _upload_file_main _clone_file _collect_file_info _generate_upload_link _upload_file_from_uri _full_upload \
        _normal_logging_upload _error_logging_upload _log_upload_session _remove_upload_session _upload_folder _share_id _get_rootdir_id

    # on successful uploads
    _share_and_print_link() {
        "${SHARE:-:}" "${1:-}" "${SHARE_EMAIL}"
        [[ -z ${HIDE_INFO} ]] && {
            _print_center "justify" "DriveLink" "${SHARE:+ (SHARED)}" "-"
            _support_ansi_escapes && [[ ${COLUMNS} -gt 45 ]] && _print_center "normal" "↓ ↓ ↓" ' '
            _print_center "normal" "https://drive.google.com/open?id=${1:-}" " "
        }
        return 0
    }

    for input in "${FINAL_LOCAL_INPUT_ARRAY[@]}"; do
        # Check if the argument is a file or a directory.
        if [[ -f ${input} ]]; then
            _print_center "justify" "Given Input" ": FILE" "="
            _print_center "justify" "Upload Method" ": ${SKIP_DUPLICATES:-${OVERWRITE:-Create}}" "=" && _newline "\n"
            _upload_file_main noparse "${input}" "${WORKSPACE_FOLDER_ID}"
            if [[ ${RETURN_STATUS} = 1 ]]; then
                _share_and_print_link "${FILE_ID}"
                printf "\n"
            else
                for _ in 1 2; do _clear_line 1; done && continue
            fi
        elif [[ -d ${input} ]]; then
            input="$(cd "${input}" && pwd)" # to handle _dirname when current directory (.) is given as input.
            unset EMPTY                     # Used when input folder is empty

            _print_center "justify" "Given Input" ": FOLDER" "-"
            _print_center "justify" "Upload Method" ": ${SKIP_DUPLICATES:-${OVERWRITE:-Create}}" "=" && _newline "\n"
            FOLDER_NAME="${input##*/}" && "${EXTRA_LOG}" "justify" "Folder: ${FOLDER_NAME}" "="

            NEXTROOTDIRID="${WORKSPACE_FOLDER_ID}"

            "${EXTRA_LOG}" "justify" "Processing folder.." "-"

            [[ -z ${SKIP_SUBDIRS} ]] && "${EXTRA_LOG}" "justify" "Indexing subfolders.." "-"
            # Do not create empty folders during a recursive upload. Use of find in this section is important.
            mapfile -t DIRNAMES <<< "$(find "${input}" -type d -not -empty)"
            NO_OF_FOLDERS="${#DIRNAMES[@]}" && NO_OF_SUB_FOLDERS="$((NO_OF_FOLDERS - 1))"
            [[ -z ${SKIP_SUBDIRS} ]] && _clear_line 1
            [[ ${NO_OF_SUB_FOLDERS} = 0 ]] && SKIP_SUBDIRS="true"

            "${EXTRA_LOG}" "justify" "Indexing files.." "-"
            mapfile -t FILENAMES <<< "$(_tmp='find "'${input}'" -type f -name "*" '${INCLUDE_FILES}' '${EXCLUDE_FILES}'' && eval "${_tmp}")"
            _clear_line 1

            ERROR_STATUS=0 SUCCESS_STATUS=0

            # Skip the sub folders and find recursively all the files and upload them.
            if [[ -n ${SKIP_SUBDIRS} ]]; then
                if [[ -n ${FILENAMES[0]} ]]; then
                    for _ in 1 2; do _clear_line 1; done
                    NO_OF_FILES="${#FILENAMES[@]}"

                    "${QUIET:-_print_center}" "justify" "Folder: ${FOLDER_NAME} " "| ${NO_OF_FILES} File(s)" "=" && printf "\n"
                    "${EXTRA_LOG}" "justify" "Creating folder.." "-"
                    { ID="$(_create_directory "${input}" "${NEXTROOTDIRID}")" && export ID; } ||
                        { "${QUIET:-_print_center}" "normal" "Folder creation failed" "-" && printf "%s\n\n\n" "${ID}" 1>&2 && continue; }
                    _clear_line 1 && DIRIDS="${ID}"

                    [[ -z ${PARALLEL_UPLOAD:-${VERBOSE:-${VERBOSE_PROGRESS}}} ]] && _newline "\n"
                    _upload_folder "${PARALLEL_UPLOAD:-normal}" noparse "$(printf "%s\n" "${FILENAMES[@]}")" "${ID}"
                    [[ -n ${PARALLEL_UPLOAD:+${VERBOSE:-${VERBOSE_PROGRESS}}} ]] && _newline "\n\n"
                else
                    for _ in 1 2; do _clear_line 1; done && EMPTY=1
                fi
            else
                if [[ -n ${FILENAMES[0]} ]]; then
                    for _ in 1 2; do _clear_line 1; done
                    NO_OF_FILES="${#FILENAMES[@]}"
                    "${QUIET:-_print_center}" "justify" "${FOLDER_NAME} " "| ${NO_OF_FILES} File(s) | ${NO_OF_SUB_FOLDERS} Sub-folders" "="

                    _newline "\n" && "${EXTRA_LOG}" "justify" "Creating Folder(s).." "-" && _newline "\n"
                    unset status DIRIDS
                    for dir in "${DIRNAMES[@]}"; do
                        [[ -n ${status} ]] && __dir="$(_dirname "${dir}")" &&
                            __temp="$(printf "%s\n" "${DIRIDS}" | grep -F "|:_//_:|${__dir}|:_//_:|")" &&
                            NEXTROOTDIRID="${__temp%%"|:_//_:|${__dir}|:_//_:|"}"

                        NEWDIR="${dir##*/}" && _print_center "justify" "Name: ${NEWDIR}" "-" 1>&2
                        ID="$(_create_directory "${NEWDIR}" "${NEXTROOTDIRID}")" ||
                            { "${QUIET:-_print_center}" "normal" "Folder creation failed" "-" && printf "%s\n\n\n" "${ID}" 1>&2 && continue; }

                        # Store sub-folder directory IDs and it's path for later use.
                        DIRIDS+="${ID}|:_//_:|${dir}|:_//_:|"$'\n'

                        for _ in 1 2; do _clear_line 1 1>&2; done
                        "${EXTRA_LOG}" "justify" "Status" ": $((status += 1)) / ${NO_OF_FOLDERS}" "=" 1>&2
                    done && export DIRIDS

                    _clear_line 1

                    _upload_folder "${PARALLEL_UPLOAD:-normal}" parse "$(printf "%s\n" "${FILENAMES[@]}")"
                    [[ -n ${PARALLEL_UPLOAD:+${VERBOSE:-${VERBOSE_PROGRESS}}} ]] && _newline "\n\n"
                else
                    for _ in 1 2 3; do _clear_line 1; done && EMPTY=1
                fi
            fi
            if [[ ${EMPTY} != 1 ]]; then
                [[ -z ${VERBOSE:-${VERBOSE_PROGRESS}} ]] && for _ in 1 2; do _clear_line 1; done

                [[ ${SUCCESS_STATUS} -gt 0 ]] &&
                    FOLDER_ID="$(: "${DIRIDS%%$'\n'*}" && printf "%s\n" "${_/"|:_//_:|"*/}")" &&
                    _share_and_print_link "${FOLDER_ID}"

                _newline "\n"
                [[ ${SUCCESS_STATUS} -gt 0 ]] && "${QUIET:-_print_center}" "justify" "Total Files " "Uploaded: ${SUCCESS_STATUS}" "="
                [[ ${ERROR_STATUS} -gt 0 ]] && "${QUIET:-_print_center}" "justify" "Total Files " "Failed: ${ERROR_STATUS}" "="
                printf "\n"
            else
                for _ in 1 2 3; do _clear_line 1; done
                "${QUIET:-_print_center}" 'justify' "Empty Folder" ": ${FOLDER_NAME}" "=" 1>&2
                printf "\n"
            fi
        fi
    done

    unset Aseen && declare -A Aseen
    for gdrive_id in "${FINAL_ID_INPUT_ARRAY[@]}"; do
        { [[ ${Aseen[${gdrive_id}]} ]] && continue; } || Aseen[${gdrive_id}]=x
        _print_center "justify" "Given Input" ": ID" "="
        "${EXTRA_LOG}" "justify" "Checking if id exists.." "-"
        json="$(_drive_info "${gdrive_id}" "name,mimeType,size" || :)"
        if ! _json_value code 1 1 <<< "${json}" 2>| /dev/null 1>&2; then
            type="$(_json_value mimeType 1 1 <<< "${json}" || :)"
            name="$(_json_value name 1 1 <<< "${json}" || :)"
            size="$(_json_value size 1 1 <<< "${json}" || :)"
            for _ in 1 2; do _clear_line 1; done
            if [[ ${type} =~ folder ]]; then
                "${QUIET:-_print_center}" "justify" "Folder not supported." "=" 1>&2 && _newline "\n" 1>&2 && continue
                ## TODO: Add support to clone folders
            else
                _print_center "justify" "Given Input" ": File ID" "="
                _print_center "justify" "Upload Method" ": ${SKIP_DUPLICATES:-${OVERWRITE:-Create}}" "=" && _newline "\n"
                _clone_file "${UPLOAD_MODE:-create}" "${gdrive_id}" "${WORKSPACE_FOLDER_ID}" "${name}" "${size}" ||
                    { for _ in 1 2; do _clear_line 1; done && continue; }
            fi
            _share_and_print_link "${FILE_ID}"
            printf "\n"
        else
            _clear_line 1
            "${QUIET:-_print_center}" "justify" "File ID (${HIDE_INFO:-gdrive_id})" " invalid." "=" 1>&2
            printf "\n"
        fi
    done
    return 0
}

main() {
    [[ $# = 0 ]] && _short_help

    [[ -z ${SELF_SOURCE} ]] && {
        UTILS_FOLDER="${UTILS_FOLDER:-${PWD}}"
        { . "${UTILS_FOLDER}"/common-utils.bash && . "${UTILS_FOLDER}"/drive-utils.bash; } || { printf "Error: Unable to source util files.\n" && exit 1; }
    }

    _check_bash_version && set -o errexit -o noclobber -o pipefail

    _setup_arguments "${@}"
    "${SKIP_INTERNET_CHECK:-_check_internet}"

    # create tempfile
    { command -v mktemp 1>| /dev/null && TMPFILE="$(mktemp -u)"; } || TMPFILE="${PWD}/$(printf "%(%s)T\\n" "-1").LOG"

    _cleanup() {
        {
            rm -f "${TMPFILE:?}"*

            # grab all chidren processes of access token service
            # https://askubuntu.com/a/512872
            token_service_pids="$(ps --ppid="${ACCESS_TOKEN_SERVICE_PID}" -o pid=)"
            # first kill parent id, then children processes
            kill "${ACCESS_TOKEN_SERVICE_PID}"
            for pid in ${token_service_pids}; do
                kill "${pid}"
            done

            # manually kill all script children pids
            script_children_pids="$(ps --ppid="$$" -o pid=)"
            for pid in ${script_children_pids}; do
                kill "${pid}"
            done

            export abnormal_exit && if [[ -n ${abnormal_exit} ]]; then
                printf "\n\n%s\n" "Script exited manually."
                kill -- -$$ &
            else
                _auto_update
            fi
        } 2>| /dev/null || :
        return 0
    }

    trap 'abnormal_exit="1"; exit' INT TERM
    trap '_cleanup' EXIT

    START="$(printf "%(%s)T\\n" "-1")"
    "${EXTRA_LOG}" "justify" "Starting script" "-"

    "${EXTRA_LOG}" "justify" "Checking credentials.." "-"
    { _check_credentials && for _ in 1 2; do _clear_line 1; done; } ||
        { "${QUIET:-_print_center}" "normal" "[ Error: Credentials checking failed ]" "=" && exit 1; }
    _print_center "justify" "Required credentials available." "="

    "${EXTRA_LOG}" "justify" "Checking root dir and workspace folder.." "-"
    { _setup_root_dir && for _ in 1 2; do _clear_line 1; done; } ||
        { "${QUIET:-_print_center}" "normal" "[ Error: Rootdir setup failed ]" "=" && exit 1; }
    _print_center "justify" "Root dir properly configured." "="

    "${EXTRA_LOG}" "justify" "Checking Workspace Folder.." "-"
    { _setup_workspace && for _ in 1 2; do _clear_line 1; done; } ||
        { "${QUIET:-_print_center}" "normal" "[ Error: Workspace setup failed ]" "=" && exit 1; }
    _print_center "justify" "Workspace Folder: ${WORKSPACE_FOLDER_NAME}" "="
    _print_center "normal" " ${WORKSPACE_FOLDER_ID} " "-" && _newline "\n"

    _process_arguments

    END="$(printf "%(%s)T\\n" "-1")"
    DIFF="$((END - START))"
    "${QUIET:-_print_center}" "normal" " Time Elapsed: ""$((DIFF / 60))"" minute(s) and ""$((DIFF % 60))"" seconds " "="
}

{ [[ -z ${SOURCED_GUPLOAD} ]] && main "${@}"; } || :
