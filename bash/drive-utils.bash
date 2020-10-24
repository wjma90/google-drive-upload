#!/usr/bin/env bash
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
# Method to regenerate access_token ( also updates in config ).
# Make a request on https://www.googleapis.com/oauth2/""${API_VERSION}""/tokeninfo?access_token=${ACCESS_TOKEN} url and check if the given token is valid, if not generate one.
# Globals: 8 variables, 2 functions
#   Variables - CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN, TOKEN_URL, CONFIG, API_URL, API_VERSION and QUIET
#   Functions - _update_config and _print_center
# Result: Update access_token and expiry else print error
###################################################
_get_access_token_and_update() {
    RESPONSE="${1:-$(curl --compressed -s -X POST --data "client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&refresh_token=${REFRESH_TOKEN}&grant_type=refresh_token" "${TOKEN_URL}")}" || :
    if ACCESS_TOKEN="$(_json_value access_token 1 1 <<< "${RESPONSE}")"; then
        _update_config ACCESS_TOKEN "${ACCESS_TOKEN}" "${CONFIG}"
        _update_config ACCESS_TOKEN_EXPIRY "$(($(printf "%(%s)T\\n" "-1") + $(_json_value expires_in 1 1 <<< "${RESPONSE}") - 1))" "${CONFIG}"
    else
        "${QUIET:-_print_center}" "justify" "Error: Something went wrong" ", printing error." 1>&2
        printf "%s\n" "${RESPONSE}" 1>&2
        return 1
    fi
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
    declare file="${1:?Error: give filename}" __rootdir __temp
    __rootdir="$(_dirname "${file}")"
    __temp="$(grep -F "|:_//_:|${__rootdir}|:_//_:|" <<< "${DIRIDS:?Error: DIRIDS Missing}" || :)"
    printf "%s\n" "${__temp%%"|:_//_:|${__rootdir}|:_//_:|"}"
    return 0
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
    declare json="${1}" info
    FILE_ID="$(_json_value id 1 1 <<< "${json}")" || { _error_logging_upload "${2}" "${json}" && return 1; }
    [[ -z ${LOG_FILE_ID} || -d ${LOG_FILE_ID} ]] && return 0
    info="$(
        printf "%s\n" "Link: https://drive.google.com/open?id=${FILE_ID}"
        printf "%s\n" "Name: $(_json_value name 1 1 <<< "${json}" || :)"
        printf "%s\n" "ID: ${FILE_ID}"
        printf "%s\n" "Type: $(_json_value mimeType 1 1 <<< "${json}" || :)"
    )"
    printf "%s\n\n" "${info}" >> "${LOG_FILE_ID}"
    return 0
}

###################################################
# Error logging wrapper
###################################################
_error_logging_upload() {
    "${QUIET:-_print_center}" "justify" "Upload ERROR" ", ${1:-} not ${STRING:-uploaded}." "=" 1>&2
    printf "%b" "${2:+${2}\n}" 1>&2
    printf "\n\n\n" 1>&2
}

###################################################
# Get information for a gdrive folder/file.
# Globals: 3 variables, 1 function
#   Variables - API_URL, API_VERSION, ACCESS_TOKEN
#   Functions - _json_value
# Arguments: 2
#   ${1} = folder/file gdrive id
#   ${2} = information to fetch, e.g name, id
# Result: On
#   Success - print fetched value
#   Error   - print "message" field from the json
# Reference:
#   https://developers.google.com/drive/api/v3/search-files
###################################################
_drive_info() {
    [[ $# -lt 2 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare folder_id="${1}" fetch="${2}" search_response

    "${EXTRA_LOG}" "justify" "Fetching info.." "-" 1>&2
    search_response="$(_api_request "${CURL_PROGRESS_EXTRA}" \
        "${API_URL}/drive/${API_VERSION}/files/${folder_id}?fields=${fetch}&supportsAllDrives=true&includeItemsFromAllDrives=true" || :)" && _clear_line 1 1>&2
    _clear_line 1 1>&2

    printf "%b" "${search_response:+${search_response}\n}"
    return 0
}

###################################################
# Search for an existing file on gdrive with write permission.
# Globals: 3 variables, 2 functions
#   Variables - API_URL, API_VERSION, ACCESS_TOKEN
#   Functions - _url_encode, _json_value
# Arguments: 2
#   ${1} = file name
#   ${2} = root dir id of file
# Result: print file id else blank
# Reference:
#   https://developers.google.com/drive/api/v3/search-files
###################################################
_check_existing_file() {
    [[ $# -lt 2 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare name="${1##*/}" rootdir="${2}" query search_response id

    "${EXTRA_LOG}" "justify" "Checking if file" " exists on gdrive.." "-" 1>&2
    query="$(_url_encode "name='${name}' and '${rootdir}' in parents and trashed=false")"

    search_response="$(_api_request "${CURL_PROGRESS_EXTRA}" \
        "${API_URL}/drive/${API_VERSION}/files?q=${query}&fields=files(id,name,mimeType)&supportsAllDrives=true&includeItemsFromAllDrives=true" || :)" && _clear_line 1 1>&2
    _clear_line 1 1>&2

    { _json_value id 1 1 <<< "${search_response}" 2>| /dev/null 1>&2 && printf "%s\n" "${search_response}"; } || return 1
    return 0
}

###################################################
# Create/Check directory in google drive.
# Globals: 3 variables, 2 functions
#   Variables - API_URL, API_VERSION, ACCESS_TOKEN
#   Functions - _url_encode, _json_value
# Arguments: 2
#   ${1} = dir name
#   ${2} = root dir id of given dir
# Result: print folder id
# Reference:
#   https://developers.google.com/drive/api/v3/folder
###################################################
_create_directory() {
    [[ $# -lt 2 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare dirname="${1##*/}" rootdir="${2}" query search_response folder_id

    "${EXTRA_LOG}" "justify" "Creating gdrive folder:" " ${dirname}" "-" 1>&2
    query="$(_url_encode "mimeType='application/vnd.google-apps.folder' and name='${dirname}' and trashed=false and '${rootdir}' in parents")"

    search_response="$(_api_request "${CURL_PROGRESS_EXTRA}" \
        "${API_URL}/drive/${API_VERSION}/files?q=${query}&fields=files(id)&supportsAllDrives=true&includeItemsFromAllDrives=true" || :)" && _clear_line 1 1>&2

    if ! folder_id="$(printf "%s\n" "${search_response}" | _json_value id 1 1)"; then
        declare create_folder_post_data create_folder_response
        create_folder_post_data="{\"mimeType\": \"application/vnd.google-apps.folder\",\"name\": \"${dirname}\",\"parents\": [\"${rootdir}\"]}"
        create_folder_response="$(_api_request "${CURL_PROGRESS_EXTRA}" \
            -X POST \
            -H "Content-Type: application/json; charset=UTF-8" \
            -d "${create_folder_post_data}" \
            "${API_URL}/drive/${API_VERSION}/files?fields=id&supportsAllDrives=true&includeItemsFromAllDrives=true" || :)" && _clear_line 1 1>&2
    fi
    _clear_line 1 1>&2

    { folder_id="${folder_id:-$(_json_value id 1 1 <<< "${create_folder_response}")}" && printf "%s\n" "${folder_id}"; } ||
        { printf "%s\n" "${create_folder_response}" 1>&2 && return 1; }
    return 0
}

###################################################
# Sub functions for _upload_file function - Start
# generate resumable upload link
_generate_upload_link() {
    "${EXTRA_LOG}" "justify" "Generating upload link.." "-" 1>&2
    uploadlink="$(_api_request "${CURL_PROGRESS_EXTRA}" \
        -X "${request_method}" \
        -H "Content-Type: application/json; charset=UTF-8" \
        -H "X-Upload-Content-Type: ${mime_type}" \
        -H "X-Upload-Content-Length: ${inputsize}" \
        -d "$postdata" \
        "${url}" \
        -D - || :)" && _clear_line 1 1>&2
    _clear_line 1 1>&2

    uploadlink="$(read -r firstline <<< "${uploadlink/*[L,l]ocation: /}" && printf "%s\n" "${firstline//$'\r'/}")"
    { [[ -n ${uploadlink} ]] && return 0; } || return 1
}

# Curl command to push the file to google drive.
_upload_file_from_uri() {
    _print_center "justify" "Uploading.." "-"
    # shellcheck disable=SC2086 # Because unnecessary to another check because ${CURL_PROGRESS} won't be anything problematic.
    upload_body="$(_api_request ${CURL_PROGRESS} \
        -X PUT \
        -H "Content-Type: ${mime_type}" \
        -H "Content-Length: ${content_length}" \
        -H "Slug: ${slug}" \
        -T "${input}" \
        -o- \
        --url "${uploadlink}" \
        --globoff \
        ${CURL_SPEED} ${resume_args1} ${resume_args2} \
        -H "${resume_args3}" || :)"
    [[ -z ${VERBOSE_PROGRESS} ]] && for _ in 1 2; do _clear_line 1; done && "${1:-:}"
    return 0
}
# logging in case of successful upload
_normal_logging_upload() {
    [[ -z ${VERBOSE_PROGRESS} ]] && _clear_line 1
    "${QUIET:-_print_center}" "justify" "${slug} " "| ${readable_size} | ${STRING}" "="
    return 0
}

# Tempfile Used for resuming interrupted uploads
_log_upload_session() {
    [[ ${inputsize} -gt 1000000 ]] && printf "%s\n" "${uploadlink}" >| "${__file}"
    return 0
}

# remove upload session
_remove_upload_session() {
    rm -f "${__file}"
    return 0
}

# wrapper to fully upload a file from scratch
_full_upload() {
    _generate_upload_link || { _error_logging_upload "${slug}" "${uploadlink}" && return 1; }
    _log_upload_session
    _upload_file_from_uri
    _collect_file_info "${upload_body}" "${slug}" || return 1
    _normal_logging_upload
    _remove_upload_session
    return 0
}
# Sub functions for _upload_file function - End
###################################################

###################################################
# Upload ( Create/Update ) files on gdrive.
# Interrupted uploads can be resumed.
# Globals: 8 variables, 10 functions
#   Variables - API_URL, API_VERSION, QUIET, VERBOSE, VERBOSE_PROGRESS, CURL_PROGRESS, LOG_FILE_ID, ACCESS_TOKEN
#   Functions - _url_encode, _json_value, _print_center, _bytes_to_human
#               _generate_upload_link, _upload_file_from_uri, _log_upload_session, _remove_upload_session
#               _full_upload, _collect_file_info
# Arguments: 3
#   ${1} = update or upload ( upload type )
#   ${2} = file to upload
#   ${3} = root dir id for file
# Result: On
#   Success - Upload/Update file and export FILE_ID
#   Error - return 1
# Reference:
#   https://developers.google.com/drive/api/v3/create-file
#   https://developers.google.com/drive/api/v3/manage-uploads
#   https://developers.google.com/drive/api/v3/reference/files/update
###################################################
_upload_file() {
    [[ $# -lt 3 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare job="${1}" input="${2}" folder_id="${3}" \
        slug inputname extension inputsize readable_size request_method url postdata uploadlink upload_body mime_type resume_args1 resume_args2 resume_args3

    slug="${input##*/}"
    inputname="${slug%.*}"
    extension="${slug##*.}"
    inputsize="$(($(wc -c < "${input}")))" && content_length="${inputsize}"
    readable_size="$(_bytes_to_human "${inputsize}")"

    # Handle extension-less files
    [[ ${inputname} = "${extension}" ]] && declare mime_type && {
        mime_type="$(file --brief --mime-type "${input}" || mimetype --output-format %m "${input}")" 2>| /dev/null || {
            "${QUIET:-_print_center}" "justify" "Error: file or mimetype command not found." "=" && printf "\n"
            exit 1
        }
    }

    _print_center "justify" "${input##*/}" " | ${readable_size}" "="

    # Set proper variables for overwriting files
    [[ ${job} = update ]] && {
        declare file_check_json
        # Check if file actually exists, and create if not.
        if file_check_json="$(_check_existing_file "${slug}" "${folder_id}")"; then
            if [[ -n ${SKIP_DUPLICATES} ]]; then
                # Stop upload if already exists ( -d/--skip-duplicates )
                _collect_file_info "${file_check_json}" "${slug}" || return 1
                _clear_line 1
                "${QUIET:-_print_center}" "justify" "${slug}" " already exists." "=" && return 0
            else
                request_method="PATCH"
                _file_id="$(_json_value id 1 1 <<< "${file_check_json}")" || { _error_logging_upload "${slug}" "${file_check_json}" && return 1; }
                url="${API_URL}/upload/drive/${API_VERSION}/files/${_file_id}?uploadType=resumable&supportsAllDrives=true&includeItemsFromAllDrives=true"
                # JSON post data to specify the file name and folder under while the file to be updated
                postdata="{\"mimeType\": \"${mime_type}\",\"name\": \"${slug}\",\"addParents\": [\"${folder_id}\"]}"
                STRING="Updated"
            fi
        else
            job="create"
        fi
    }

    # Set proper variables for creating files
    [[ ${job} = create ]] && {
        url="${API_URL}/upload/drive/${API_VERSION}/files?uploadType=resumable&supportsAllDrives=true&includeItemsFromAllDrives=true"
        request_method="POST"
        # JSON post data to specify the file name and folder under while the file to be created
        postdata="{\"mimeType\": \"${mime_type}\",\"name\": \"${slug}\",\"parents\": [\"${folder_id}\"]}"
        STRING="Uploaded"
    }

    __file="${HOME}/.google-drive-upload/${slug}__::__${folder_id}__::__${inputsize}"
    # https://developers.google.com/drive/api/v3/manage-uploads
    if [[ -r "${__file}" ]]; then
        uploadlink="$(< "${__file}")"
        http_code="$(curl --compressed -s -X PUT "${uploadlink}" --write-out %"{http_code}")" || :
        case "${http_code}" in
            308) # Active Resumable URI give 308 status
                uploaded_range="$(: "$(curl --compressed -s -X PUT \
                    -H "Content-Range: bytes */${inputsize}" \
                    --url "${uploadlink}" --globoff -D - || :)" &&
                    : "$(printf "%s\n" "${_/*[R,r]ange: bytes=0-/}")" && read -r firstline <<< "$_" && printf "%s\n" "${firstline//$'\r'/}")"
                if [[ ${uploaded_range} -gt 0 ]]; then
                    _print_center "justify" "Resuming interrupted upload.." "-" && _newline "\n"
                    content_range="$(printf "bytes %s-%s/%s\n" "$((uploaded_range + 1))" "$((inputsize - 1))" "${inputsize}")"
                    content_length="$((inputsize - $((uploaded_range + 1))))"
                    # Resuming interrupted uploads needs http1.1
                    resume_args1='-s' resume_args2='--http1.1' resume_args3="Content-Range: ${content_range}"
                    _upload_file_from_uri _clear_line
                    _collect_file_info "${upload_body}" "${slug}" || return 1
                    _normal_logging_upload
                    _remove_upload_session
                else
                    _full_upload || return 1
                fi
                ;;
            40[0-9]) # Dead Resumable URI give 40* status
                _full_upload
                ;;
            201 | 200) # Completed Resumable URI give 20* status
                upload_body="${http_code}"
                _collect_file_info "${upload_body}" "${slug}" || return 1
                _normal_logging_upload
                _remove_upload_session
                ;;
        esac
    else
        _full_upload || return 1
    fi
    return 0
}

###################################################
# A extra wrapper for _upload_file function to properly handle retries
# also handle uploads in case uploading from folder
# Globals: 2 variables, 1 function
#   Variables - RETRY, UPLOAD_MODE
#   Functions - _upload_file
# Arguments: 3
#   ${1} = parse or norparse
#   ${2} = file path
#   ${3} = if ${1} != parse; gdrive folder id to upload; fi
# Result: set SUCCESS var on success
###################################################
_upload_file_main() {
    [[ $# -lt 2 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare file="${2}" dirid
    { [[ ${1} = parse ]] && dirid="$(_get_rootdir_id "${file}")"; } || dirid="${3}"

    retry="${RETRY:-0}" && unset RETURN_STATUS
    until [[ ${retry} -le 0 ]] && [[ -n ${RETURN_STATUS} ]]; do
        if [[ -n ${4} ]]; then
            _upload_file "${UPLOAD_MODE:-create}" "${file}" "${dirid}" 2>| /dev/null 1>&2 && RETURN_STATUS=1 && break
        else
            _upload_file "${UPLOAD_MODE:-create}" "${file}" "${dirid}" && RETURN_STATUS=1 && break
        fi
        RETURN_STATUS=2 retry="$((retry - 1))" && continue
    done
    { [[ ${RETURN_STATUS} = 1 ]] && printf "%b" "${4:+${RETURN_STATUS}\n}"; } || printf "%b" "${4:+${RETURN_STATUS}\n}" 1>&2
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
    [[ $# -lt 3 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare mode="${1}" files="${3}" && PARSE_MODE="${2}" ID="${4:-}" && export PARSE_MODE ID
    case "${mode}" in
        normal)
            [[ ${PARSE_MODE} = parse ]] && _clear_line 1 && _newline "\n"

            while read -u 4 -r file; do
                _upload_file_main "${PARSE_MODE}" "${file}" "${ID}"
                : "$((RETURN_STATUS < 2 ? (SUCCESS_STATUS += 1) : (ERROR_STATUS += 1)))"
                if [[ -n ${VERBOSE:-${VERBOSE_PROGRESS}} ]]; then
                    _print_center "justify" "Status: ${SUCCESS_STATUS} Uploaded" " | ${ERROR_STATUS} Failed" "=" && _newline "\n"
                else
                    for _ in 1 2; do _clear_line 1; done
                    _print_center "justify" "Status: ${SUCCESS_STATUS} Uploaded" " | ${ERROR_STATUS} Failed" "="
                fi
            done 4<<< "${files}"
            ;;
        parallel)
            NO_OF_PARALLEL_JOBS_FINAL="$((NO_OF_PARALLEL_JOBS > NO_OF_FILES ? NO_OF_FILES : NO_OF_PARALLEL_JOBS))"
            [[ -f "${TMPFILE}"SUCCESS ]] && rm "${TMPFILE}"SUCCESS
            [[ -f "${TMPFILE}"ERROR ]] && rm "${TMPFILE}"ERROR

            # shellcheck disable=SC2016
            printf "%s\n" "${files}" | xargs -n1 -P"${NO_OF_PARALLEL_JOBS_FINAL}" -I {} bash -c '
            _upload_file_main "${PARSE_MODE}" "{}" "${ID}" true
            ' 1>| "${TMPFILE}"SUCCESS 2>| "${TMPFILE}"ERROR &
            pid="${!}"

            until [[ -f "${TMPFILE}"SUCCESS ]] || [[ -f "${TMPFILE}"ERORR ]]; do sleep 0.5; done
            [[ ${PARSE_MODE} = parse ]] && _clear_line 1
            _newline "\n"

            until ! kill -0 "${pid}" 2>| /dev/null 1>&2; do
                SUCCESS_STATUS="$(_count < "${TMPFILE}"SUCCESS)"
                ERROR_STATUS="$(_count < "${TMPFILE}"ERROR)"
                sleep 1
                [[ $((SUCCESS_STATUS + ERROR_STATUS)) != "${TOTAL}" ]] &&
                    _clear_line 1 && "${QUIET:-_print_center}" "justify" "Status" ": ${SUCCESS_STATUS} Uploaded | ${ERROR_STATUS} Failed" "="
                TOTAL="$((SUCCESS_STATUS + ERROR_STATUS))"
            done
            SUCCESS_STATUS="$(_count < "${TMPFILE}"SUCCESS)"
            ERROR_STATUS="$(_count < "${TMPFILE}"ERROR)"
            ;;
    esac
    return 0
}

###################################################
# Copy/Clone a public gdrive file/folder from another/same gdrive account
# Globals: 6 variables, 2 functions
#   Variables - API_URL, API_VERSION, CURL_PROGRESS, LOG_FILE_ID, QUIET, ACCESS_TOKEN
#   Functions - _print_center, _check_existing_file, _json_value, _bytes_to_human, _clear_line
# Arguments: 5
#   ${1} = update or upload ( upload type )
#   ${2} = file id to upload
#   ${3} = root dir id for file
#   ${4} = name of file
#   ${5} = size of file
# Result: On
#   Success - Upload/Update file and export FILE_ID
#   Error - return 1
# Reference:
#   https://developers.google.com/drive/api/v2/reference/files/copy
###################################################
_clone_file() {
    [[ $# -lt 5 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare job="${1}" file_id="${2}" file_root_id="${3}" name="${4}" size="${5}"
    declare clone_file_post_data clone_file_response readable_size _file_id && STRING="Cloned"
    clone_file_post_data="{\"parents\": [\"${file_root_id}\"]}"
    readable_size="$(_bytes_to_human "${size}")"

    _print_center "justify" "${name} " "| ${readable_size}" "="

    if [[ ${job} = update ]]; then
        declare file_check_json
        # Check if file actually exists.
        if file_check_json="$(_check_existing_file "${name}" "${file_root_id}")"; then
            if [[ -n ${SKIP_DUPLICATES} ]]; then
                _collect_file_info "${file_check_json}" || return 1
                _clear_line 1
                "${QUIET:-_print_center}" "justify" "${name}" " already exists." "=" && return 0
            else
                _print_center "justify" "Overwriting file.." "-"
                { _file_id="$(_json_value id 1 1 <<< "${file_check_json}")" &&
                    clone_file_post_data="$(_drive_info "${_file_id}" "parents,writersCanShare")"; } ||
                    { _error_logging_upload "${name}" "${post_data:-${file_check_json}}" && return 1; }
                if [[ ${_file_id} != "${file_id}" ]]; then
                    _api_request -s \
                        -X DELETE \
                        "${API_URL}/drive/${API_VERSION}/files/${_file_id}?supportsAllDrives=true&includeItemsFromAllDrives=true" 2>| /dev/null 1>&2 || :
                    STRING="Updated"
                else
                    _collect_file_info "${file_check_json}" || return 1
                fi
            fi
        else
            "${EXTRA_LOG}" "justify" "Cloning file.." "-"
        fi
    else
        "${EXTRA_LOG}" "justify" "Cloning file.." "-"
    fi

    # shellcheck disable=SC2086 # Because unnecessary to another check because ${CURL_PROGRESS} won't be anything problematic.
    clone_file_response="$(_api_request ${CURL_PROGRESS} \
        -X POST \
        -H "Content-Type: application/json; charset=UTF-8" \
        -d "${clone_file_post_data}" \
        "${API_URL}/drive/${API_VERSION}/files/${file_id}/copy?supportsAllDrives=true&includeItemsFromAllDrives=true" || :)"
    for _ in 1 2 3; do _clear_line 1; done
    _collect_file_info "${clone_file_response}" || return 1
    "${QUIET:-_print_center}" "justify" "${name} " "| ${readable_size} | ${STRING}" "="
    return 0
}

###################################################
# Share a gdrive file/folder
# Globals: 3 variables, 4 functions
#   Variables - API_URL, API_VERSION, ACCESS_TOKEN
#   Functions - _url_encode, _json_value, _print_center, _clear_line
# Arguments: 2
#   ${1} = gdrive ID of folder/file
#   ${2} = Email to which file will be shared ( optional )
# Result: read description
# Reference:
#   https://developers.google.com/drive/api/v3/manage-sharing
###################################################
_share_id() {
    [[ $# -lt 2 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare id="${1}" share_email="${2}" role="reader" type="${share_email:+user}"
    declare type share_post_data share_post_data share_response

    "${EXTRA_LOG}" "justify" "Sharing.." "-" 1>&2
    share_post_data="{\"role\":\"${role}\",\"type\":\"${type:-anyone}\"${share_email:+,\\\"emailAddress\\\":\\\"${share_email}\\\"}}"

    share_response="$(_api_request "${CURL_PROGRESS_EXTRA}" \
        -X POST \
        -H "Content-Type: application/json; charset=UTF-8" \
        -d "${share_post_data}" \
        "${API_URL}/drive/${API_VERSION}/files/${id}/permissions?supportsAllDrives=true&includeItemsFromAllDrives=true" || :)" && _clear_line 1 1>&2
    _clear_line 1 1>&2

    { _json_value id 1 1 <<< "${share_response}" 2>| /dev/null 1>&2 && return 0; } ||
        { printf "%s\n" "Error: Cannot Share." 1>&2 && printf "%s\n" "${share_response}" 1>&2 && return 1; }
}
