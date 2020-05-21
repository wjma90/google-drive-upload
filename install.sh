#!/usr/bin/env bash
# Install, Update or Uninstall google-drive-upload

_usage() {
    printf "
The script can be used to install google-drive-upload script in your system.\n
Usage:\n %s [options.. ]\n

All flags are optional.

Options:\n
  -i | --interactive - Install script interactively, will ask for all the varibles one by one.\nNote: This will disregard all arguments given with below flags.\n
  -p | --path <dir_name> - Custom path where you want to install script.\nDefault Path: %s/.google-drive-upload \n
  -c | --cmd <command_name> - Custom command name, after installation script will be available as the input argument.\nDefault Name: upload \n
  -r | --repo <Username/reponame> - Upload script from your custom repo,e.g --repo labbots/google-drive-upload, make sure your repo file structure is same as official repo.\n
  -R | --release <tag/release_tag> - Specify tag name for the github repo, applies to custom and default repo both.\n
  -B | --branch <branch_name> - Specify branch name for the github repo, applies to custom and default repo both.\n
  -s | --shell-rc <shell_file> - Specify custom rc file, where PATH is appended, by default script detects .zshrc and .bashrc.\n
  -z | --config <fullpath> - Specify fullpath of the config file which will contain the credentials.\nDefault : %s/.googledrive.conf
  -U | --uninstall - Uninstall the script and remove related files.\n
  -D | --debug - Display script command trace.\n
  -h | --help - Display usage instructions.\n\n" "${0##*/}" "${HOME}" "${HOME}"
    exit 0
}

_short_help() {
    printf "No valid arguments provided, use -h/--help flag to see usage.\n"
    exit 0
}

###################################################
# Check for bash version >= 4.x
# Globals: 1 Variable
#   BASH_VERSINFO
# Required Arguments: None
# Result: If
#   SUCEESS: Status 0
#   ERROR: print message and exit 1
###################################################
_check_bash_version() {
    { ! [[ ${BASH_VERSINFO:-0} -ge 4 ]] && printf "Bash version lower than 4.x not supported.\n" && exit 1; } || :
}

###################################################
# Check if debug is enabled and enable command trace
# Globals: 2 variables, 1 function
#   Varibles - DEBUG, QUIET
#   Function - _is_terminal
# Arguments: None
# Result: If DEBUG
#   Present - Enable command trace and change print functions to avoid spamming.
#   Absent  - Disable command trace
#             Check QUIET, then check terminal size and enable print functions accordingly.
###################################################
_check_debug() {
    _print_center_quiet() { { [[ $# = 3 ]] && printf "%s\n" "${2}"; } || { printf "%s%s\n" "${2}" "${3}"; }; }
    if [[ -n ${DEBUG} ]]; then
        set -x
        _print_center() { { [[ $# = 3 ]] && printf "%s\n" "${2}"; } || { printf "%s%s\n" "${2}" "${3}"; }; }
        _clear_line() { :; } && _newline() { :; }
    else
        set +x
        if [[ -z ${QUIET} ]]; then
            if _is_terminal; then
                # This refreshes the interactive shell so we can use the ${COLUMNS} variable in the _print_center function.
                shopt -s checkwinsize && (: && :)
                if [[ ${COLUMNS} -lt 40 ]]; then
                    _print_center() { { [[ $# = 3 ]] && printf "%s\n" "[ ${2} ]"; } || { printf "%s\n" "[ ${2}${3} ]"; }; }
                else
                    trap 'shopt -s checkwinsize; (:;:)' SIGWINCH
                fi
            else
                _print_center() { { [[ $# = 3 ]] && printf "%s\n" "[ ${2} ]"; } || { printf "%s\n" "[ ${2}${3} ]"; }; }
                _clear_line() { :; }
            fi
            _newline() { printf "%b" "${1}"; }
        else
            _print_center() { :; } && _clear_line() { :; } && _newline() { :; }
        fi
    fi
}

###################################################
# Check internet connection.
# Probably the fastest way, takes about 1 - 2 KB of data, don't check for more than 10 secs.
# Use alternate timeout method if possible, as curl -m option is unreliable in some cases.
# Globals: 2 functions
#   _print_center, _clear_line
# Arguments: None
# Result: On
#   Success - Nothing
#   Error   - print message and exit 1
# Reference:
#   Alternative to timeout command: https://unix.stackexchange.com/a/18711
###################################################
_check_internet() {
    _print_center "justify" "Checking Internet Connection.." "-"
    if _is_terminal; then
        CHECK_INTERNET="$(sh -ic 'exec 3>&1 2>/dev/null; { curl --compressed -Is google.com 1>&3; kill 0; } | { sleep 10; kill 0; }' || :)"
    else
        CHECK_INTERNET="$(curl --compressed -Is google.com -m 10)"
    fi
    _clear_line 1
    if [[ -z ${CHECK_INTERNET} ]]; then
        printf "Error: Internet connection not available.\n"
        exit 1
    fi
}

###################################################
# Move cursor to nth no. of line and clear it to the begining.
# Globals: None
# Arguments: 1
#   ${1} = Positive integer ( line number )
# Result: Read description
###################################################
_clear_line() {
    printf "\033[%sA\033[2K" "${1}"
}

###################################################
# Detect profile rc file for zsh and bash.
# Detects for login shell of the user.
# Globals: 2 Variables
#   HOME, SHELL
# Arguments: None
# Result: On
#   Success - print profile file
#   Error   - print error message and exit 1
###################################################
_detect_profile() {
    declare CURRENT_SHELL="${SHELL##*/}"
    case "${CURRENT_SHELL}" in
        'bash') DETECTED_PROFILE="${HOME}/.bashrc" ;;
        'zsh') DETECTED_PROFILE="${HOME}/.zshrc" ;;
        *) if [[ -f "${HOME}/.profile" ]]; then
            DETECTED_PROFILE="${HOME}/.profile"
        else
            printf "No compaitable shell file\n" && exit 1
        fi ;;
    esac
    printf "%s\n" "${DETECTED_PROFILE}"
}

###################################################
# Alternative to dirname command
# Globals: None
# Arguments: 1
#   ${1} = path of file or folder
# Result: read description
# Reference:
#   https://github.com/dylanaraps/pure-bash-bible#get-the-directory-name-of-a-file-path
###################################################
_dirname() {
    declare tmp=${1:-.}

    [[ ${tmp} != *[!/]* ]] && { printf '/\n' && return; }
    tmp="${tmp%%"${tmp##*[!/]}"}"

    [[ ${tmp} != */* ]] && { printf '.\n' && return; }
    tmp=${tmp%/*} && tmp="${tmp%%"${tmp##*[!/]}"}"

    printf '%s\n' "${tmp:-/}"
}

###################################################
# Print full path of a file/folder
# Globals: 1 variable
#   PWD
# Arguments: 1
#   ${1} = name of file/folder
# Result: print full path
###################################################
_full_path() {
    case "${1?${FUNCNAME[0]}: Missing arguments}" in
        /*) printf "%s\n" "${1}" ;;
        *) printf "%s\n" "${PWD}/${1}" ;;
    esac
}

###################################################
# Fetch latest commit sha of release or branch
# Uses github rest api v3
# Globals: None
# Arguments: 3
#   ${1} = "branch" or "release"
#   ${2} = branch name or release name
#   ${3} = repo name e.g labbots/google-drive-upload
# Result: print fetched sha
###################################################
_get_latest_sha() {
    declare LATEST_SHA
    case "${1:-${TYPE}}" in
        branch)
            LATEST_SHA="$(curl --compressed -s https://api.github.com/repos/"${3:-${REPO}}"/commits/"${2:-${TYPE_VALUE}}" | _json_value sha)"
            ;;
        release)
            LATEST_SHA="$(curl --compressed -s https://api.github.com/repos/"${3:-${REPO}}"/releases/"${2:-${TYPE_VALUE}}" | _json_value tag_name)"
            ;;
    esac
    echo "${LATEST_SHA}"
}

###################################################
# Check if script running in a terminal
# Globals: 1 variable
#   TERM
# Arguments: None
# Result: return 1 or 0
###################################################
_is_terminal() {
    [[ -t 1 || -z ${TERM} ]] && return 0 || return 1
}

###################################################
# Method to extract specified field data from json
# Globals: None
# Arguments: 2
#   ${1} - value of field to fetch from json
#   ${2} - Optional, nth number of value from extracted values, default it 1.
# Input: file | here string | pipe
#   _json_value "Arguments" < file
#   _json_value "Arguments <<< "${varibale}"
#   echo something | _json_value "Arguments"
# Result: print extracted value
###################################################
_json_value() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare LC_ALL=C num="${2:-1}"
    grep -o "\"""${1}""\"\:.*" | sed -e "s/.*\"""${1}""\": //" -e 's/[",]*$//' -e 's/["]*$//' -e 's/[,]*$//' -e "s/\"//" -n -e "${num}"p
}

###################################################
# Print a text to center interactively and fill the rest of the line with text specified.
# This function is fine-tuned to this script functionality, so may appear unusual.
# Globals: 1 variable
#   COLUMNS
# Arguments: 4
#   If ${1} = normal
#      ${2} = text to print
#      ${3} = symbol
#   If ${1} = justify
#      If remaining arguments = 2
#         ${2} = text to print
#         ${3} = symbol
#      If remaining arguments = 3
#         ${2}, ${3} = text to print
#         ${4} = symbol
# Result: read description
# Reference:
#   https://gist.github.com/TrinityCoder/911059c83e5f7a351b785921cf7ecda
###################################################
_print_center() {
    [[ $# -lt 3 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare -i TERM_COLS="${COLUMNS}"
    declare type="${1}" filler
    case "${type}" in
        normal)
            declare out="${2}" && symbol="${3}"
            ;;
        justify)
            if [[ $# = 3 ]]; then
                declare input1="${2}" symbol="${3}" TO_PRINT out
                TO_PRINT="$((TERM_COLS * 95 / 100))"
                { [[ ${#input1} -gt ${TO_PRINT} ]] && out="[ ${input1:0:TO_PRINT}.. ]"; } || { out="[ ${input1} ]"; }
            else
                declare input1="${2}" input2="${3}" symbol="${4}" TO_PRINT temp out
                TO_PRINT="$((TERM_COLS * 40 / 100))"
                { [[ ${#input1} -gt ${TO_PRINT} ]] && temp+=" ${input1:0:TO_PRINT}.."; } || { temp+=" ${input1}"; }
                TO_PRINT="$((TERM_COLS * 55 / 100))"
                { [[ ${#input2} -gt ${TO_PRINT} ]] && temp+="${input2:0:TO_PRINT}.. "; } || { temp+="${input2} "; }
                out="[${temp}]"
            fi
            ;;
        *) return 1 ;;
    esac

    declare -i str_len=${#out}
    [[ $str_len -ge $(((TERM_COLS - 1))) ]] && {
        printf "%s\n" "${out}" && return 0
    }

    declare -i filler_len="$(((TERM_COLS - str_len) / 2))"
    [[ $# -ge 2 ]] && ch="${symbol:0:1}" || ch=" "
    for ((i = 0; i < filler_len; i++)); do
        filler="${filler}${ch}"
    done

    printf "%s%s%s" "${filler}" "${out}" "${filler}"
    [[ $(((TERM_COLS - str_len) % 2)) -ne 0 ]] && printf "%s" "${ch}"
    printf "\n"

    return 0
}

###################################################
# Remove duplicates, maintain the order as original.
# Globals: None
# Arguments: 1
#   ${@} = Anything
# Result: read description
# Reference:
#   https://stackoverflow.com/a/37962595
###################################################
_remove_array_duplicates() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare -A Aseen
    Aunique=()
    for i in "$@"; do
        { [[ -z ${i} || ${Aseen[${i}]} ]]; } && continue
        Aunique+=("${i}") && Aseen[${i}]=x
    done
    printf '%s\n' "${Aunique[@]}"
}

###################################################
# Config updater
# Incase of old value, update, for new value add.
# Globals: 1 function
#   _remove_array_duplicates
# Arguments: 3
#   ${1} = value name
#   ${2} = value
#   ${3} = config path
# Result: read description
###################################################
_update_config() {
    [[ $# -lt 3 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare VALUE_NAME="${1}" VALUE="${2}" CONFIG_PATH="${3}" FINAL=()
    printf "" >> "${CONFIG_PATH}" # If config file doesn't exist.
    mapfile -t VALUES < "${CONFIG_PATH}" && VALUES+=("${VALUE_NAME}=\"${VALUE}\"")
    for i in "${VALUES[@]}"; do
        [[ ${i} =~ ${VALUE_NAME}\= ]] && FINAL+=("${VALUE_NAME}=\"${VALUE}\"") || FINAL+=("${i}")
    done
    _remove_array_duplicates "${FINAL[@]}" >| "${CONFIG_PATH}"
}

###################################################
# Initialize default variables
# Globals: 1 variable, 1 function
#   Variable - HOME
#   Function - _detect_profile
# Arguments: None
# Result: read description
###################################################
_variables() {
    REPO="labbots/google-drive-upload"
    COMMAND_NAME="gupload"
    INFO_PATH="${HOME}/.google-drive-upload"
    INSTALL_PATH="${HOME}/.google-drive-upload/bin"
    UTILS_FILE="utils.sh"
    CONFIG="${HOME}/.googledrive.conf"
    TYPE="release"
    TYPE_VALUE="latest"
    SHELL_RC="$(_detect_profile)"
    # shellcheck source=/dev/null
    if [[ -r ${INFO_PATH}/google-drive-upload.info ]]; then
        source "${INFO_PATH}"/google-drive-upload.info
    fi
    __VALUES_ARRAY=(REPO COMMAND_NAME INSTALL_PATH CONFIG TYPE TYPE_VALUE SHELL_RC)
}

###################################################
# Start a interactive session, asks for all the varibles.
# Globals: 1 variable, 1 function
#   Variable - __VALUES_ARRAY ( array )
#   Function - _clear_line
# Arguments: None
# Result: read description
#   If tty absent, then exit
###################################################
_start_interactive() {
    _print_center "justify" "Interactive Mode" "="
    _print_center "justify" "Press return for default values.." "-"
    for i in "${__VALUES_ARRAY[@]}"; do
        j="${!i}" && k="${i}"
        read -r -p "${i} [ Default: ${j} ]: " "${i?}"
        if [[ -z ${!i} ]]; then
            read -r "${k?}" <<< "${j}"
        fi
    done
    for _ in "${__VALUES_ARRAY[@]}"; do _clear_line 1; done
    for _ in {1..3}; do _clear_line 1; done
    for i in "${__VALUES_ARRAY[@]}"; do
        if [[ -n ${i} ]]; then
            printf "%s\n" "${i}: ${!i}"
        fi
    done
}

###################################################
# Install the script
# Globals: 10 variables, 6 functions
#   Variables - INSTALL_PATH, INFO_PATH, UTILS_FILE, COMMAND_NAME, SHELL_RC, CONFIG,
#               TYPE, TYPE_VALUE, REPO, __VALUES_ARRAY ( array )
#   Functions - _print_center, _newline, _clear_line
#               _get_latest_sha, curl --compressed, _update_config
# Arguments: None
# Result: read description
#   If cannot download, then print message and exit
###################################################
_install() {
    mkdir -p "${INSTALL_PATH}"
    _print_center "justify" 'Installing google-drive-upload..' "-"
    _print_center "justify" "Fetching latest sha.." "-"
    LATEST_CURRENT_SHA="$(_get_latest_sha "${TYPE}" "${TYPE_VALUE}" "${REPO}")"
    _clear_line 1
    _print_center "justify" "Latest sha fetched." "=" && _print_center "justify" "Downloading script.." "-"
    if curl --compressed -Ls "https://raw.githubusercontent.com/${REPO}/${LATEST_CURRENT_SHA}/${UTILS_FILE}" -o "${INSTALL_PATH}/${UTILS_FILE}" &&
        curl --compressed -Ls "https://raw.githubusercontent.com/${REPO}/${LATEST_CURRENT_SHA}/upload.sh" -o "${INSTALL_PATH}/${COMMAND_NAME}"; then
        sed -i "2a UTILS_FILE=\"${INSTALL_PATH}/${UTILS_FILE}\"" "${INSTALL_PATH}/${COMMAND_NAME}"
        chmod +x "${INSTALL_PATH}/${COMMAND_NAME}"
        for i in "${__VALUES_ARRAY[@]}"; do
            _update_config "${i}" "${!i}" "${INFO_PATH}"/google-drive-upload.info
        done
        _update_config LATEST_INSTALLED_SHA "${LATEST_CURRENT_SHA}" "${INFO_PATH}"/google-drive-upload.info
        _update_config PATH "${INSTALL_PATH}:${PATH}" "${INFO_PATH}"/google-drive-upload.binpath
        printf "%s\n" "${CONFIG}" >| "${INFO_PATH}"/google-drive-upload.configpath
        if ! grep "source ${INFO_PATH}/google-drive-upload.binpath" "${SHELL_RC}" &> /dev/null; then
            printf "\nsource %s/google-drive-upload.binpath" "${INFO_PATH}" >> "${SHELL_RC}"
        fi
        for _ in {1..3}; do _clear_line 1; done
        _print_center "justify" "Installed Successfully" "="
        _print_center "normal" "[ Command name: ${COMMAND_NAME} ]" "="
        _print_center "justify" "To use the command, do" "-"
        _newline "\n" && _print_center "normal" "source ${SHELL_RC}" " "
        _print_center "normal" "or" " "
        _print_center "normal" "restart your terminal." " "
        _newline "\n" && _print_center "normal" "To update the script in future, just run ${COMMAND_NAME} -u/--update." " "
    else
        _clear_line 1
        _print_center "justify" "Cannot download the script." "="
        exit 1
    fi
}

###################################################
# Update the script
# Globals: 10 variables, 6 functions
#   Variables - INSTALL_PATH, INFO_PATH, UTILS_FILE, COMMAND_NAME, SHELL_RC, CONFIG,
#               TYPE, TYPE_VALUE, REPO, __VALUES_ARRAY ( array )
#   Functions - _print_center, _newline, _clear_line
#               _get_latest_sha, curl --compressed, _update_config
# Arguments: None
# Result: read description
#   If cannot download, then print message and exit
###################################################
_update() {
    _print_center "justify" "Fetching latest version info.." "-"
    LATEST_CURRENT_SHA="$(_get_latest_sha "${TYPE}" "${TYPE_VALUE}" "${REPO}")"
    if [[ -z "${LATEST_CURRENT_SHA}" ]]; then
        _print_center "justify" "Cannot fetch remote latest version." "="
        exit 1
    fi
    _clear_line 1
    if [[ ${LATEST_CURRENT_SHA} = "${LATEST_INSTALLED_SHA}" ]]; then
        _print_center "justify" "Latest google-drive-upload already installed." "="
    else
        _print_center "justify" "Updating.." "-"
        if curl --compressed -Ls "https://raw.githubusercontent.com/${REPO}/${LATEST_CURRENT_SHA}/${UTILS_FILE}" -o "${INSTALL_PATH}/${UTILS_FILE}" &&
            curl --compressed -Ls "https://raw.githubusercontent.com/${REPO}/${LATEST_CURRENT_SHA}/upload.sh" -o "${INSTALL_PATH}/${COMMAND_NAME}"; then
            sed -i "2a UTILS_FILE=\"${INSTALL_PATH}/${UTILS_FILE}\"" "${INSTALL_PATH}/${COMMAND_NAME}"
            chmod +x "${INSTALL_PATH}/${COMMAND_NAME}"
            for i in "${__VALUES_ARRAY[@]}"; do
                _update_config "${i}" "${!i}" "${INFO_PATH}"/google-drive-upload.info
            done
            _update_config LATEST_INSTALLED_SHA "${LATEST_CURRENT_SHA}" "${INFO_PATH}"/google-drive-upload.info
            _update_config PATH "${INSTALL_PATH}:${PATH}" "${INFO_PATH}"/google-drive-upload.binpath
            printf "%s\n" "${CONFIG}" >| "${INFO_PATH}"/google-drive-upload.configpath
            if ! grep "source ${INFO_PATH}/google-drive-upload.binpath" "${SHELL_RC}" &> /dev/null; then
                printf "\nsource %s/google-drive-upload.binpath" "${INFO_PATH}" >> "${SHELL_RC}"
            fi
            _clear_line 1
            for i in "${__VALUES_ARRAY[@]}"; do
                _update_config "${i}" "${!i}" "${INFO_PATH}"/google-drive-upload.info
            done
            _print_center "justify" 'Successfully Updated.' "="
        else
            _clear_line 1
            _print_center "justify" "Cannot download the script." "="
            exit 1
        fi
    fi
}

###################################################
# Uninstall the script
# Globals: 5 variables, 2 functions
#   Variables - INSTALL_PATH, INFO_PATH, UTILS_FILE, COMMAND_NAME, SHELL_RC
#   Functions - _print_center, _clear_line
# Arguments: None
# Result: read description
#   If cannot edit the SHELL_RC, then print message and exit
###################################################
_uninstall() {
    _print_center "justify" "Uninstalling.." "-"
    __bak="source ${INFO_PATH}/google-drive-upload.binpath"
    if sed -i "s|${__bak}||g" "${SHELL_RC}"; then
        rm -f "${INSTALL_PATH}"/{"${COMMAND_NAME}","${UTILS_FILE}"}
        rm -f "${INFO_PATH}"/{google-drive-upload.info,google-drive-upload.binpath,google-drive-upload.configpath}
        _clear_line 1
        _print_center "justify" "Uninstall complete." "="
    else
        _print_center "justify" 'Error: Uninstall failed.' "="
    fi
}

###################################################
# Process getopts flags and variables for the script
# Globals: 1 variable, 2 functions
#   Variable - SHELL_RC
#   Functions - _is_terminal, _full_path
# Arguments: Many
#   ${@} = Flags with arguments
# Result: read description
#   If no shell rc file fount, then print message and exit
# Reference:
#   Parse Longoptions - https://stackoverflow.com/questions/402377/using-getopts-to-process-long-and-short-command-line-options/28466267#28466267
###################################################
_setup_arguments() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    SHORTOPTS=":Dhip:r:c:RB:Us:-:"
    while getopts "${SHORTOPTS}" OPTION; do
        case "${OPTION}" in
            -)
                _check_longoptions() { { [[ -n ${!OPTIND} ]] && printf '%s: --%s: option requires an argument\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${OPTARG}" "${0##*/}" && exit 1; } || :; }
                case "${OPTARG}" in
                    help)
                        _usage
                        ;;
                    interactive)
                        if _is_terminal; then
                            INTERACTIVE="true"
                            return 0
                        else
                            printf "Cannot start interactive mode in an non tty environment\n"
                            exit 1
                        fi
                        ;;
                    path)
                        _check_longoptions
                        INSTALL_PATH="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        ;;
                    repo)
                        _check_longoptions
                        REPO="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        ;;
                    cmd)
                        _check_longoptions
                        COMMAND_NAME="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        ;;
                    branch)
                        _check_longoptions
                        TYPE_VALUE="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        TYPE=branch
                        ;;
                    release)
                        _check_longoptions
                        TYPE_VALUE="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        TYPE=release
                        ;;
                    shell-rc)
                        _check_longoptions
                        SHELL_RC="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        ;;
                    config)
                        _check_longoptions
                        if [[ -d "${!OPTIND}" ]]; then
                            printf "Error: -z/--config only takes filename as argument, given input ( %s ) is a directory." "${!OPTIND}" 1>&2 && exit 1
                        elif [[ -f "${!OPTIND}" ]]; then
                            if [[ -r "${!OPTIND}" ]]; then
                                CONFIG="$(_full_path "${!OPTIND}")" && OPTIND=$((OPTIND + 1))
                            else
                                printf "Error: Current user doesn't have read permission for given config file ( %s ).\n" "${!OPTIND}" 1>&2 && exit 1
                            fi
                        else
                            CONFIG="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        fi
                        ;;
                    uninstall)
                        UNINSTALL="true"
                        ;;
                    debug)
                        DEBUG=true
                        export DEBUG
                        ;;
                    '')
                        shorthelp
                        ;;
                    *)
                        printf '%s: --%s: Unknown option\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${OPTARG}" "${0##*/}" && exit 1
                        ;;
                esac
                ;;
            h)
                _usage
                ;;
            i)
                if _is_terminal; then
                    INTERACTIVE="true"
                    return 0
                else
                    printf "Cannot start interactive mode in an non tty environment.\n"
                    exit 1
                fi
                ;;
            p)
                INSTALL_PATH="${OPTARG}"
                ;;
            r)
                REPO="${OPTARG}"
                ;;
            c)
                COMMAND_NAME="${OPTARG}"
                ;;
            B)
                TYPE=branch
                TYPE_VALUE="${OPTARG}"
                ;;
            R)
                TYPE=release
                TYPE_VALUE="${OPTARG}"
                ;;
            s)
                SHELL_RC="${OPTARG}"
                ;;
            z)
                if [[ -d "${OPTARG}" ]]; then
                    printf "Error: -z/--config only takes filename as argument, given input ( %s ) is a directory." "${OPTARG}" 1>&2 && exit 1
                elif [[ -f "${OPTARG}" ]]; then
                    if [[ -r "${OPTARG}" ]]; then
                        CONFIG="$(_full_path "${!OPTIND}")" && OPTIND=$((OPTIND + 1))
                    else
                        printf "Error: Current user doesn't have read permission for given config file ( %s ).\n" "${OPTARG}" 1>&2 && exit 1
                    fi
                else
                    CONFIG="${OPTARG}" && OPTIND=$((OPTIND + 1))
                fi
                ;;
            U)
                UNINSTALL="true"
                ;;
            D)
                DEBUG=true
                export DEBUG
                ;;
            :)
                printf '%s: -%s: option requires an argument\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${OPTARG}" "${0##*/}" && exit 1
                ;;
            ?)
                printf '%s: -%s: Unknown option\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${OPTARG}" "${0##*/}" && exit 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    if [[ -z ${SHELL_RC} ]]; then
        printf "No default shell file found, use -s/--shell-rc to use custom rc file\n"
        exit 1
    else
        if ! [[ -f ${SHELL_RC} ]]; then
            printf "Given shell file ( %s ) does not exist.\n" "${SHELL_RC}"
            exit 1
        fi
    fi
}

main() {
    _variables
    if [[ $* ]]; then
        _setup_arguments "${@}"
    fi

    _check_debug && _check_bash_version

    if [[ -n ${INTERACTIVE} ]]; then
        _start_interactive
    fi

    if [[ -n ${UNINSTALL} ]]; then
        if type -a "${COMMAND_NAME}" &> /dev/null; then
            _uninstall
        else
            _print_center "justify" "google-drive-upload is not installed." "="
            exit 1
        fi
    else
        _check_internet
        if type -a "${COMMAND_NAME}" &> /dev/null; then
            _update
        else
            _install
        fi
    fi
}

main "${@}"
