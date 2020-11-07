#!/usr/bin/env sh
# shellcheck source=/dev/null

###################################################
# A simple wrapper to check tempfile for access token and make authorized oauth requests to drive api
###################################################
_api_request() {
    . "${TMPFILE}_ACCESS_TOKEN"

    curl --compressed \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${@}"
}

###################################################
# Used in collecting file properties from output json after a file has been uploaded/cloned
# Also handles logging in log file if LOG_FILE_ID is set
# Globals: 1 variables, 2 functions
#   Variables - LOG_FILE_ID
#   Functions - _error_logging_upload, _json_value
# Arguments: 1
#   ${1} = output jsom
# Result: set fileid and link, save info to log file if required
###################################################
_collect_file_info() {
    json_collect_file_info="${1}" info_collect_file_info=""
    FILE_ID="$(printf "%s\n" "${json_collect_file_info}" | _json_value id 1 1)" || { _error_logging_upload "${2}" "${json_collect_file_info}"; }
    { [ -z "${LOG_FILE_ID}" ] || [ -d "${LOG_FILE_ID}" ]; } && return 0
    info_collect_file_info="Link: https://drive.google.com/open?id=${FILE_ID}
Name: $(printf "%s\n" "${json_collect_file_info}" | _json_value name 1 1 || :)
ID: ${FILE_ID}
Type: $(printf "%s\n" "${json_collect_file_info}" | _json_value mimeType 1 1 || :)"
    printf "%s\n\n" "${info_collect_file_info}" >> "${LOG_FILE_ID}"
    return 0
}

###################################################
# Error logging wrapper
###################################################
_error_logging_upload() {
    log_error_logging_upload="${2}"
    "${QUIET:-_print_center}" "justify" "Upload ERROR" ", ${1:-} not ${STRING:-uploaded}." "=" 1>&2
    case "${log_error_logging_upload}" in
        # https://github.com/rclone/rclone/issues/3857#issuecomment-573413789
        *'"message": "User rate limit exceeded."'*)
            printf "%s\n\n%s\n" "${log_error_logging_upload}" \
                "Today's upload limit reached for this account. Use another account to upload or wait for tomorrow." 1>&2
            # Never retry if upload limit reached
            export RETRY=0
            ;;
        '' | *) printf "%s\n" "${log_error_logging_upload}" 1>&2 ;;
    esac
    printf "\n\n\n" 1>&2
    return 1
}

###################################################
# Generate rs256 jwt just with cli commands and shell
# Specifically for gdrive service accounts usage
# Globals: 1
#  SCOPE ( optional )
# Arguments: 2
#   ${1} = service account json file
#   ${2} = SCOPE for gdrive
# Result: print jwt
# Refrences:
#   https://stackoverflow.com/questions/46657001/how-do-you-create-an-rs256-jwt-assertion-with-bash-shell-scripting
#   Inspired by implementation by Will Haley at:
#     http://willhaley.com/blog/generate-jwt-with-bash/
###################################################
_generate_jwt() {
    json_file_generate_jwt="${1:?Error: Give service json file name}"
    scope_generate_jwt="${2:-${SCOPE:?Error: Missing scope}}"
    aud_generate_jwt="https://oauth2.googleapis.com/token"
    header_generate_jwt='{"alg":"RS256","typ":"JWT"}'
    algo_generate_jwt="256"
    unset payload_data_generate_jwt iss_generate_jwt exp_generate_jwt iat_generate_jwt rsa_secret_generate_jwt \
        signed_content_generate_jwt sign_generate_jwt

    if iss_generate_jwt="$(_json_value client_email 1 1 < "${json_file_generate_jwt}")" &&
        rsa_secret_generate_jwt="$(_json_value private_key 1 1 < "${json_file_generate_jwt}")"; then
        rsa_secret_generate_jwt="$(printf "%b\n" "${rsa_secret_generate_jwt}")"
    else
        "${QUIET:-_print_center}" 'normal' "Error: Invalid service account file." "=" && return 1
    fi

    iat_generate_jwt="$(date +"%s")" exp_generate_jwt="$((iat_generate_jwt + 3400))"

    b64enc() { openssl enc -base64 -A | sed -e "s|+|-|g" -e "s|/|_|g" -e "s|=||g"; }

    payload_data_generate_jwt='{"iss":"'${iss_generate_jwt}'","scope":"'${scope_generate_jwt}'","aud":"'${aud_generate_jwt}'","exp":'${exp_generate_jwt}',"iat":'${iat_generate_jwt}'}'

    {
        signed_content_generate_jwt="$(printf "%s\n" "${header_generate_jwt}" | b64enc).$(printf "%s\n" "${payload_data_generate_jwt}" | b64enc)"
        # Open file discriptor for rsa_secret
        exec 5<< EOF
$(printf "%s\n" "${rsa_secret_generate_jwt}")
EOF
        sign_generate_jwt="$(printf %s "${signed_content_generate_jwt}" | openssl dgst -binary -sha"${algo_generate_jwt}" -sign /dev/fd/5 | b64enc)"
        # close file discriptor
        exec 5<&-
    } || return 1

    printf '%s.%s\n' "${signed_content_generate_jwt}" "${sign_generate_jwt}"
    return 0
}

###################################################
# A small function to get rootdir id for files in sub folder uploads
# Globals: 1 variable, 1 function
#   Variables - DIRIDS
#   Functions - _dirname
# Arguments: 1
#   ${1} = filename
# Result: read discription
###################################################
_get_rootdir_id() {
    file_gen_final_list="${1:?Error: give filename}"
    rootdir_gen_final_list="$(_dirname "${file_gen_final_list}")"
    temp_gen_final_list="$(printf "%s\n" "${DIRIDS:?Error: DIRIDS Missing}" | grep -F "|:_//_:|${rootdir_gen_final_list}|:_//_:|" || :)"
    printf "%s\n" "${temp_gen_final_list%%"|:_//_:|${rootdir_gen_final_list}|:_//_:|"}"
    return 0
}

###################################################
# A extra wrapper for _upload_file function to properly handle retries
# also handle uploads in case uploading from folder
# Globals: 3 variables, 1 function
#   Variables - RETRY, UPLOAD_MODE and ACCESS_TOKEN
#   Functions - _upload_file
# Arguments: 3
#   ${1} = parse or norparse
#   ${2} = file path
#   ${3} = if ${1} != parse; gdrive folder id to upload; fi
# Result: set SUCCESS var on success
###################################################
_upload_file_main() {
    [ $# -lt 2 ] && printf "Missing arguments\n" && return 1
    file_upload_file_main="${2}" sleep_upload_file_main=0
    { [ "${1}" = parse ] && dirid_upload_file_main="$(_get_rootdir_id "${file_upload_file_main}")"; } || dirid_upload_file_main="${3}"

    retry_upload_file_main="${RETRY:-0}" && unset RETURN_STATUS
    until [ "${retry_upload_file_main}" -le 0 ] && [ -n "${RETURN_STATUS}" ]; do
        if [ -n "${4}" ]; then
            { _upload_file "${UPLOAD_MODE:-create}" "${file_upload_file_main}" "${dirid_upload_file_main}" 2>| /dev/null 1>&2 && RETURN_STATUS=1 && break; } || RETURN_STATUS=2
        else
            { _upload_file "${UPLOAD_MODE:-create}" "${file_upload_file_main}" "${dirid_upload_file_main}" && RETURN_STATUS=1 && break; } || RETURN_STATUS=2
        fi
        # decrease retry using -=, skip sleep if all retries done
        [ "$((retry_upload_file_main -= 1))" -gt 1 ] && sleep "$((sleep_upload_file_main += 1))"
        # on every retry, sleep the times of retry it is, e.g for 1st, sleep 1, for 2nd, sleep 2
        continue
    done
    { [ "${RETURN_STATUS}" = 1 ] && printf "%b" "${4:+${RETURN_STATUS}\n}"; } || printf "%b" "${4:+${RETURN_STATUS}\n}" 1>&2
    return 0
}

###################################################
# Upload all files in the given folder, parallelly or non-parallely and show progress
# Globals: 7 variables, 3 functions
#   Variables - VERBOSE, VERBOSE_PROGRESS, NO_OF_PARALLEL_JOBS, NO_OF_FILES, TMPFILE, UTILS_FOLDER and QUIET
#   Functions - _clear_line, _newline, _print_center and _upload_file_main
# Arguments: 4
#   ${1} = parallel or normal
#   ${2} = parse or norparse
#   ${3} = filenames with full path
#   ${4} = if ${2} != parse; then gdrive folder id to upload; fi
# Result: read discription, set SUCCESS_STATUS & ERROR_STATUS
###################################################
_upload_folder() {
    [ $# -lt 3 ] && printf "Missing arguments\n" && return 1
    mode_upload_folder="${1}" PARSE_MODE="${2}" files_upload_folder="${3}" ID="${4:-}" && export PARSE_MODE ID
    case "${mode_upload_folder}" in
        normal)
            [ "${PARSE_MODE}" = parse ] && _clear_line 1 && _newline "\n"

            while read -r file <&4; do
                _upload_file_main "${PARSE_MODE}" "${file}" "${ID}"
                : "$((RETURN_STATUS < 2 ? (SUCCESS_STATUS += 1) : (ERROR_STATUS += 1)))"
                if [ -n "${VERBOSE:-${VERBOSE_PROGRESS}}" ]; then
                    _print_center "justify" "Status: ${SUCCESS_STATUS} Uploaded" " | ${ERROR_STATUS} Failed" "=" && _newline "\n"
                else
                    for _ in 1 2; do _clear_line 1; done
                    _print_center "justify" "Status: ${SUCCESS_STATUS} Uploaded" " | ${ERROR_STATUS} Failed" "="
                fi
            done 4<< EOF
$(printf "%s\n" "${files_upload_folder}")
EOF
            ;;
        parallel)
            NO_OF_PARALLEL_JOBS_FINAL="$((NO_OF_PARALLEL_JOBS > NO_OF_FILES ? NO_OF_FILES : NO_OF_PARALLEL_JOBS))"
            [ -f "${TMPFILE}"SUCCESS ] && rm "${TMPFILE}"SUCCESS
            [ -f "${TMPFILE}"ERROR ] && rm "${TMPFILE}"ERROR

            # shellcheck disable=SC2016
            (printf "%s\n" "${files_upload_folder}" | xargs -n1 -P"${NO_OF_PARALLEL_JOBS_FINAL}" -I {} sh -c '
            eval "${SOURCE_UTILS}"
            _upload_file_main "${PARSE_MODE}" "{}" "${ID}" true
            ' 1>| "${TMPFILE}"SUCCESS 2>| "${TMPFILE}"ERROR) &
            pid="${!}"

            until [ -f "${TMPFILE}"SUCCESS ] || [ -f "${TMPFILE}"ERORR ]; do sleep 0.5; done
            [ "${PARSE_MODE}" = parse ] && _clear_line 1
            _newline "\n"

            until ! kill -0 "${pid}" 2>| /dev/null 1>&2; do
                SUCCESS_STATUS="$(($(wc -l < "${TMPFILE}"SUCCESS)))"
                ERROR_STATUS="$(($(wc -l < "${TMPFILE}"ERROR)))"
                sleep 1
                [ "$((SUCCESS_STATUS + ERROR_STATUS))" != "${TOTAL}" ] &&
                    _clear_line 1 && "${QUIET:-_print_center}" "justify" "Status" ": ${SUCCESS_STATUS} Uploaded | ${ERROR_STATUS} Failed" "="
                TOTAL="$((SUCCESS_STATUS + ERROR_STATUS))"
            done
            SUCCESS_STATUS="$(($(wc -l < "${TMPFILE}"SUCCESS)))"
            ERROR_STATUS="$(($(wc -l < "${TMPFILE}"ERROR)))"
            ;;
    esac
    return 0
}
