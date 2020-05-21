#!/usr/bin/env bash

# A simple curl OAuth2 authenticator
#
# Usage:
#	./google-oauth2.sh create - authenticates a user
#	./google-oauth2.sh refresh <token> - gets a new token
#
# Set CLIENT_ID and CLIENT_SECRET and SCOPE
# See SCOPES at https://developers.google.com/identity/protocols/oauth2/scopes#docsv1

_short_help() {
    printf "
No valid arguments provided.
Usage:

 ./%s create - authenticates a user.
 ./%s refresh - gets a new access token.

  Use update as second argument to update the local config with the new REFRESH TOKEN.
  e.g: ./%s create/refresh update\n" "${0##*/}" "${0##*/}" "${0##*/}"
    exit 0
}

[[ ${1} = create ]] || [[ ${1} = refresh ]] || _short_help

[[ ${2} = update ]] && UPDATE="_update_config"

UTILS_FILE="${UTILS_FILE:-./utils.sh}"
if [[ -r ${UTILS_FILE} ]]; then
    # shellcheck source=/dev/null
    source "${UTILS_FILE}" || { printf "Error: Unable to source utils file ( %s ) .\n" "${UTILS_FILE}" && exit 1; }
else
    printf "Error: Utils file ( %s ) not found\n" "${UTILS_FILE}"
    exit 1
fi

if ! _is_terminal; then
    DEBUG="true"
    export DEBUG
fi
_check_debug

_print_center "justify" "Starting script.." "-"

CLIENT_ID=""
CLIENT_SECRET=""
SCOPE="https://www.googleapis.com/auth/drive"
REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"
TOKEN_URL="https://accounts.google.com/o/oauth2/token"

# shellcheck source=/dev/null
[[ -f ${HOME}/.googledrive.conf ]] && source "${HOME}"/.googledrive.conf

_print_center "justify" "Checking credentials.." "-"

# Credentials
if [[ -z ${CLIENT_ID} ]]; then
    read -r -p "Client ID: " CLIENT_ID
    [[ -z ${CLIENT_ID} ]] && printf "Error: No value provided.\n" 1>&2 && exit 1
    _update_config CLIENT_ID "${CLIENT_ID}" "${HOME}"/.googledrive.conf
fi
if [[ -z ${CLIENT_SECRET} ]]; then
    read -r -p "Client Secret: " CLIENT_SECRET
    [[ -z ${CLIENT_SECRET} ]] && printf "Error: No value provided.\n" 1>&2 && exit 1
    _update_config CLIENT_SECRET "${CLIENT_SECRET}" "${HOME}"/.googledrive.conf
fi

for _ in {1..2}; do _clear_line 1; done

if [[ ${1} = create ]]; then
    _print_center "justify" "Required credentials set." "="
    printf "Visit the below URL, tap on allow and then enter the code obtained:\n"
    URL="https://accounts.google.com/o/oauth2/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPE}&response_type=code&prompt=consent"
    printf "%s\n\n" "${URL}"
    read -r -p "Enter the authorization code: " CODE

    CODE="${CODE//[[:space:]]/}"
    if [[ -n ${CODE} ]]; then
        RESPONSE="$(curl --compressed -s -X POST --data "client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&refresh_token=${REFRESH_TOKEN}&grant_type=refresh_token" ${TOKEN_URL})"

        ACCESS_TOKEN="$(_json_value access_token <<< "${RESPONSE}")"
        REFRESH_TOKEN="$(_json_value refresh_token <<< "${RESPONSE}")"

        if [[ -n ${ACCESS_TOKEN} && -n ${REFRESH_TOKEN} ]]; then
            "${UPDATE:-:}" REFRESH_TOKEN "${REFRESH_TOKEN}" "${CONFIG:-${HOME}/.googledrive.conf}"
            "${UPDATE:-:}" ACCESS_TOKEN "${ACCESS_TOKEN}" "${CONFIG:-${HOME}/.googledrive.conf}"

            printf "Access Token: %s\n" "${ACCESS_TOKEN}"
            printf "Refresh Token: %s\n" "${REFRESH_TOKEN}"
        else
            _print_center "normal" "Error: Wrong code given, make sure you copy the exact code." "="
            exit 1
        fi
    else
        _print_center "justify" "No code provided, run the script and try again." "="
        exit 1
    fi
elif [[ ${1} = refresh ]]; then
    # Method to regenerate access_token ( also _updates in config ).
    # Make a request on https://www.googleapis.com/oauth2/""${API_VERSION}""/tokeninfo?access_token=${ACCESS_TOKEN} url and check if the given token is valid, if not generate one.
    # Requirements: Refresh Token
    _get_token_and__update() {
        RESPONSE="$(curl --compressed -s -X POST --data "client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&refresh_token=${REFRESH_TOKEN}&grant_type=refresh_token" "${TOKEN_URL}")"
        ACCESS_TOKEN="$(_json_value access_token <<< "${RESPONSE}")"
        "${UPDATE:-:}" ACCESS_TOKEN "${ACCESS_TOKEN}" "${CONFIG:-${HOME}/.googledrive.conf}"
    }
    if [[ -n ${REFRESH_TOKEN} ]]; then
        _print_center "justify" "Required credentials set." "="
        _get_token_and__update
        _clear_line 1
        printf "Access Token: %s\n" "${ACCESS_TOKEN}"
    else
        _print_center "normal" "Refresh Token not set, use ${0} create to generate one." "="
    fi
fi
