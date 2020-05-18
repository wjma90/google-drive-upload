#!/usr/bin/env bash
# Install, Update or Uninstall google-drive-upload

usage() {
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

shortHelp() {
    printf "No valid arguments provided, use -h/--help flag to see usage.\n\n"
    exit 0
}

# Exit if bash present on system is older than 4.x
checkBashVersion() {
    { ! [[ ${BASH_VERSINFO:-0} -ge 4 ]] && printf "Bash version lower than 4.x not supported.\n" && exit 1; } || :
}

# Check if we are running in a terminal.
isTerminal() {
    [[ -t 1 || -z ${TERM} ]] && return 0 || return 1
}

# Get fullpath of a file or folder
# Usage: fullpath file/folder
fullPath() {
    case "${1?${FUNCNAME[0]}: Missing arguments}" in
        /*) printf "%s\n" "${1}" ;;
        *) printf "%s\n" "${PWD}/${1}" ;;
    esac
}

# Remove array duplicates, maintain the order as original.
# Usage: removeArrayDuplicates "${somearray[@]}"
# https://stackoverflow.com/a/37962595
removeArrayDuplicates() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare -A Aseen
    Aunique=()
    for i in "$@"; do
        { [[ -z ${i} || ${Aseen[${i}]} ]]; } && continue
        Aunique+=("${i}") && Aseen[${i}]=x
    done
    printf '%s\n' "${Aunique[@]}"
}

# Update Config. Incase of old value, update, for new value add.
# Usage: updateConfig valuename value configpath
updateConfig() {
    [[ $# -lt 3 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare VALUE_NAME="${1}" VALUE="${2}" CONFIG_PATH="${3}" FINAL=()
    printf "" >> "${CONFIG_PATH}" # If config file doesn't exist.
    mapfile -t VALUES < "${CONFIG_PATH}" && VALUES+=("${VALUE_NAME}=\"${VALUE}\"")
    for i in "${VALUES[@]}"; do
        [[ ${i} =~ ${VALUE_NAME}\= ]] && FINAL+=("${VALUE_NAME}=\"${VALUE}\"") || FINAL+=("${i}")
    done
    removeArrayDuplicates "${FINAL[@]}" >| "${CONFIG_PATH}"
}

# Detect profile file
# Support bash and zsh
detectProfile() {
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

# Method to extract data from json response.
# Usage: jsonValue key < json ( or use with a pipe output ).
jsonValue() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare LC_ALL=C num="${2:-1}"
    grep -o "\"""${1}""\"\:.*" | sed -e "s/.*\"""${1}""\": //" -e 's/[",]*$//' -e 's/["]*$//' -e 's/[,]*$//' -e "s/\"//" -n -e "${num}"p
}

# Use github rest api v3
# Usage: getLatestSHA branch/release branchname/releasename reponame
getLatestSHA() {
    declare LATEST_SHA
    case "${1:-${TYPE}}" in
        branch)
            LATEST_SHA="$(curl --compressed -s https://api.github.com/repos/"${3:-${REPO}}"/commits/"${2:-${TYPE_VALUE}}" | jsonValue sha)"
            ;;
        release)
            LATEST_SHA="$(curl --compressed -s https://api.github.com/repos/"${3:-${REPO}}"/releases/"${2:-${TYPE_VALUE}}" | jsonValue tag_name)"
            ;;
    esac
    echo "${LATEST_SHA}"
}

# Move cursor to nth no. of line and clear it to the begining.
clearLine() {
    if isTerminal; then
        printf "\033[%sA\033[2K" "${1}"
    fi
}

# Initialize default variables.
variables() {
    REPO="labbots/google-drive-upload"
    COMMAND_NAME="gupload"
    INFO_PATH="${HOME}/.google-drive-upload"
    INSTALL_PATH="${HOME}/.google-drive-upload/bin"
    CONFIG="${HOME}/.googledrive.conf"
    TYPE="release"
    TYPE_VALUE="latest"
    SHELL_RC="$(detectProfile)"
    # shellcheck source=/dev/null
    if [[ -r ${INFO_PATH}/google-drive-upload.info ]]; then
        source "${INFO_PATH}"/google-drive-upload.info
    fi
    __VALUES_ARRAY=(REPO COMMAND_NAME INSTALL_PATH CONFIG TYPE TYPE_VALUE SHELL_RC)
}

# Start a interactive session, asks for all the varibles, exit if running in a non-tty
startInteractive() {
    printf "Interactive Mode\n"
    printf "%s\n" "Press return for default values.."
    for i in "${__VALUES_ARRAY[@]}"; do
        j="${!i}" && k="${i}"
        read -r -p "${i} [ Default: ${j} ]: " "${i?}"
        if [[ -z ${!i} ]]; then
            read -r "${k?}" <<< "${j}"
        fi
    done
    for _ in "${__VALUES_ARRAY[@]}"; do clearLine 1; done
    for _ in {1..3}; do clearLine 1; done
    for i in "${__VALUES_ARRAY[@]}"; do
        if [[ -n ${i} ]]; then
            printf "%s\n" "${i}: ${!i}"
        fi
    done
}

# Install the script
install() {
    mkdir -p "${INSTALL_PATH}"
    printf 'Installing google-drive-upload..\n'
    printf "Fetching latest sha..\n"
    LATEST_CURRENT_SHA="$(getLatestSHA "${TYPE}" "${TYPE_VALUE}" "${REPO}")"
    clearLine 1
    printf "Latest sha fetched\n" && printf "Downloading script..\n"
    if curl -Ls --compressed "https://raw.githubusercontent.com/${REPO}/${LATEST_CURRENT_SHA}/upload.sh" -o "${INSTALL_PATH}/${COMMAND_NAME}"; then
        chmod +x "${INSTALL_PATH}/${COMMAND_NAME}"
        for i in "${__VALUES_ARRAY[@]}"; do
            updateConfig "${i}" "${!i}" "${INFO_PATH}"/google-drive-upload.info
        done
        updateConfig LATEST_INSTALLED_SHA "${LATEST_CURRENT_SHA}" "${INFO_PATH}"/google-drive-upload.info
        updateConfig PATH "${INSTALL_PATH}:${PATH}" "${INFO_PATH}"/google-drive-upload.binpath
        printf "%s\n" "${CONFIG}" >| "${INFO_PATH}"/google-drive-upload.configpath
        if ! grep "source ${INFO_PATH}/google-drive-upload.binpath" "${SHELL_RC}" &> /dev/null; then
            printf "\nsource %s/google-drive-upload.binpath" "${INFO_PATH}" >> "${SHELL_RC}"
        fi
        clearLine 1
        printf "Installed Successfully, Command name: %s\n" "${COMMAND_NAME}"
        printf "To use the command, do\n"
        printf "source %s or restart your terminal.\n" "${SHELL_RC}"
        printf "To update the script in future, just run upload -u/--update.\n"
    else
        clearLine 1
        printf "Cannot download the script.\n"
        exit 1
    fi
}

# Update the script
update() {
    printf "Fetching latest version info..\n"
    LATEST_CURRENT_SHA="$(getLatestSHA "${TYPE}" "${TYPE_VALUE}" "${REPO}")"
    if [[ -z "${LATEST_CURRENT_SHA}" ]]; then
        printf "Cannot fetch remote latest version.\n"
        exit 1
    fi
    clearLine 1
    if [[ ${LATEST_CURRENT_SHA} = "${LATEST_INSTALLED_SHA}" ]]; then
        printf "Latest google-drive-upload already installed.\n"
    else
        printf "Updating...\n"
        curl --compressed -Ls "https://raw.githubusercontent.com/${REPO}/${LATEST_CURRENT_SHA}/upload.sh" -o "${INSTALL_PATH}/${COMMAND_NAME}"
        updateConfig LATEST_INSTALLED_SHA "${LATEST_CURRENT_SHA}" "${INFO_PATH}"/google-drive-upload.info
        updateConfig PATH "${INSTALL_PATH}:${PATH}" "${INFO_PATH}"/google-drive-upload.binpath
        printf "%s\n" "${CONFIG}" >| "${INFO_PATH}"/google-drive-upload.configpath
        if ! grep "source ${INFO_PATH}/google-drive-upload.binpath" "${SHELL_RC}" &> /dev/null; then
            printf "\nsource %s/google-drive-upload.binpath" "${INFO_PATH}" >> "${SHELL_RC}"
        fi
        clearLine 1
        for i in "${__VALUES_ARRAY[@]}"; do
            updateConfig "${i}" "${!i}" "${INFO_PATH}"/google-drive-upload.info
        done
        printf 'Successfully Updated.\n'
    fi
}

# Uninstall the script
uninstall() {
    printf "Uninstalling..\n"
    __bak="source ${INFO_PATH}/google-drive-upload.binpath"
    if sed -i "s|${__bak}||g" "${SHELL_RC}"; then
        rm -f "${INSTALL_PATH}/${COMMAND_NAME}"
        rm -f "${INFO_PATH}/google-drive-upload.info"
        rm -f "${INFO_PATH}/google-drive-upload.binpath"
        clearLine 1
        printf "Uninstall complete.\n"
    else
        printf 'Error: Uninstall failed.\n'
    fi
}

# Setup the varibles and process getopts flags.
setupArguments() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    SHORTOPTS=":Dhip:r:c:RB:Us:-:"
    while getopts "${SHORTOPTS}" OPTION; do
        case "${OPTION}" in
            # Parse longoptions # https://stackoverflow.com/questions/402377/using-getopts-to-process-long-and-short-command-line-options/28466267#28466267
            -)
                checkLongoptions() { { [[ -n ${!OPTIND} ]] && printf '%s: --%s: option requires an argument\nTry '"%s -h/--help"' for more information.\n' "${0##*/}" "${OPTARG}" "${0##*/}" && exit 1; } || :; }
                case "${OPTARG}" in
                    help)
                        usage
                        ;;
                    interactive)
                        if isTerminal; then
                            INTERACTIVE="true"
                            return 0
                        else
                            printf "Cannot start interactive mode in an non tty environment\n"
                            exit 1
                        fi
                        ;;
                    path)
                        checkLongoptions
                        INSTALL_PATH="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        ;;
                    repo)
                        checkLongoptions
                        REPO="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        ;;
                    cmd)
                        checkLongoptions
                        COMMAND_NAME="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        ;;
                    branch)
                        checkLongoptions
                        TYPE_VALUE="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        TYPE=branch
                        ;;
                    release)
                        checkLongoptions
                        TYPE_VALUE="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        TYPE=release
                        ;;
                    shell-rc)
                        checkLongoptions
                        SHELL_RC="${!OPTIND}" && OPTIND=$((OPTIND + 1))
                        ;;
                    config)
                        checkLongoptions
                        if [[ -d "${!OPTIND}" ]]; then
                            printf "Error: -z/--config only takes filename as argument, given input ( %s ) is a directory." "${!OPTIND}" 1>&2 && exit 1
                        elif [[ -f "${!OPTIND}" ]]; then
                            if [[ -r "${!OPTIND}" ]]; then
                                CONFIG="$(fullPath "${!OPTIND}")" && OPTIND=$((OPTIND + 1))
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
                usage
                ;;
            i)
                if isTerminal; then
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
                        CONFIG="$(fullPath "${!OPTIND}")" && OPTIND=$((OPTIND + 1))
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

# debug mode.
checkDebug() {
    if [[ -n ${DEBUG} ]]; then
        set -x
    else
        set +x
    fi
}

# If internet connection is not available.
# Probably the fastest way, takes about 1 - 2 KB of data, don't check for more than 10 secs.
# curl -m option is unreliable in some cases.
# https://unix.stackexchange.com/a/18711 to timeout without any external program.
checkInternet() {
    if isTerminal; then
        CHECK_INTERNET="$(sh -ic 'exec 3>&1 2>/dev/null; { curl --compressed -Is google.com 1>&3; kill 0; } | { sleep 10; kill 0; }' || :)"
    else
        CHECK_INTERNET="$(curl --compressed -Is google.com -m 10)"
    fi
    if [[ -z ${CHECK_INTERNET} ]]; then
        printf "Error: Internet connection not available.\n"
        exit 1
    fi
}

main() {
    variables
    if [[ $* ]]; then
        setupArguments "${@}"
    fi

    checkDebug && checkBashVersion && checkInternet

    if [[ -n ${INTERACTIVE} ]]; then
        startInteractive
    fi
    if [[ -n ${UNINSTALL} ]]; then
        if type -a "${COMMAND_NAME}" &> /dev/null; then
            uninstall
        else
            printf "google-drive-upload is not installed\n"
            exit 1
        fi
    else
        if type -a "${COMMAND_NAME}" &> /dev/null; then
            update
        else
            install
        fi
    fi
}

main "${@}"
