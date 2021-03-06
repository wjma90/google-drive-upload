#!/usr/bin/env sh
# auth utils for Google Drive
# shellcheck source=/dev/null

###################################################
# Check if account exists
# Globals: 1 function
#   _set_value
# Arguments: 1
#   "${1}" = Account name
# Result: read description and return 1 or 0
###################################################
_account_exists() {
    name="${1:?Error: Give account name}" client_id="" client_secret="" refresh_token=""
    _set_value indirect client_id "ACCOUNT_${name}_CLIENT_ID"
    _set_value indirect client_secret "ACCOUNT_${name}_CLIENT_SECRET"
    _set_value indirect refresh_token "ACCOUNT_${name}_REFRESH_TOKEN"
    [ -z "${client_id:+${client_secret:+${refresh_token}}}" ] && return 1
    return 0
}

###################################################
# Show all accounts configured in config file
# Globals: 2 variables, 3 functions
#   Variable - CONFIG, QUIET
#   Functions - _account_exists, _set_value, _print_center
# Arguments: None
# Result: SHOW all accounts, export COUNT and ACC_${count}_ACC dynamic variables
#         or print "No accounts configured yet."
###################################################
_all_accounts() {
    COUNT=0
    while read -r account <&4 && [ -n "${account}" ]; do
        _account_exists "${account}" &&
            { [ "${COUNT}" = 0 ] && "${QUIET:-_print_center}" "normal" " All available accounts. " "=" || :; } &&
            printf "%b" "$((COUNT += 1)). ${account} \n" &&
            _set_value direct "ACC_${COUNT}_ACC" "${account}"
    done 4<< 'EOF'
$(grep -oE '^ACCOUNT_.*_CLIENT_ID' "${CONFIG}" | sed -e "s/ACCOUNT_//g" -e "s/_CLIENT_ID//g")
EOF
    { [ "${COUNT}" -le 0 ] && "${QUIET:-_print_center}" "normal" " No accounts configured yet. " "=" 1>&2; } || printf '\n'
    return 0
}

###################################################
# Set account name for new account configuration
# If given account name is configured already, then ask for name
# Globals: 2 variables, 3 functions
#   Variables - QUIET, ACCOUNT_NAME_REGEX
#   Functions - _print_center, _account_exists, _clear_line
# Arguments: 1
#   "${1}" = Account name ( optional )
# Result: read description and export CREATE_ACCOUNT_NAME
###################################################
_set_account_name() {
    export ACCOUNT_NAME_REGEX='^([A-Za-z0-9_])+$'
    new_account_name="${1:-}" && unset name_valid
    [ -z "${new_account_name}" ] && {
        _all_accounts 2>| /dev/null
        "${QUIET:-_print_center}" "normal" " New account name: " "="
        "${QUIET:-_print_center}" "normal" "Info: Account names can only contain alphabets / numbers / dashes." " " && printf '\n'
    }
    until [ -n "${new_account_name}" ] && [ -n "${name_valid}" ]; do
        printf -- "-> \e[?7l"
        read -r new_account_name
        printf '\e[?7h'
        [ -n "${new_account_name}" ] && {
            if printf "%s\n" "${new_account_name}" | grep -qE "${ACCOUNT_NAME_REGEX}"; then
                if _account_exists "${new_account_name}"; then
                    "${QUIET:-_print_center}" "normal" " Given account ( ${new_account_name} ) already exists, input different name. " "-" && continue
                else
                    export CREATE_ACCOUNT_NAME="${new_account_name}" ACCOUNT_NAME="${new_account_name}" && name_valid="true" && continue
                fi
            else
                "${QUIET:-_print_center}" "normal" " Given account name ( ${new_account_name} ) invalid, input different name. " "-" && continue
            fi
        }
        _clear_line 1
    done
    return 0
}

###################################################
# Delete a account from config file
# Globals: 2 variables, 2 functions
#   Variables - CONFIG, QUIET
#   Functions - _account_exists, _print_center
# Arguments: None
# Result: check if account exists and delete from config, else print error message
###################################################
_delete_account() {
    account="${1:?Error: give account name}" && unset regex config_without_values
    if _account_exists "${account}"; then
        regex="^ACCOUNT_${account}_(CLIENT_ID=|CLIENT_SECRET=|REFRESH_TOKEN=|ROOT_FOLDER=|ROOT_FOLDER_NAME=|ACCESS_TOKEN=|ACCESS_TOKEN_EXPIRY=)"
        config_without_values="$(grep -vE "${regex}" "${CONFIG}")"
        chmod u+w "${CONFIG}" # change perms to edit
        printf "%s\n" "${config_without_values}" >| "${CONFIG}"
        chmod "a-w-r-x,u+r" "${CONFIG}" # restore perms
        "${QUIET:-_print_center}" "normal" " Successfully deleted account ( ${account} ) from config. " "-"
    else
        "${QUIET:-_print_center}" "normal" " Error: Cannot delete account ( ${account} ) from config. No such account exists " "-" 1>&2
    fi
    return 0
}

###################################################
# Check Oauth credentials and create/update config file
# Account name, Client ID, Client Secret, Refesh Token and Access Token
# Globals: 10 variables, 6 functions
#   Variables - CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN, ACCESS_TOKEN, ROOT_FOLDER, ROOT_FOLDER_NAME ( same vars with ACCOUNT_${ACCOUNT_NAME} prefix too )
#               CONFIG, ACCOUNT_NAME, CUSTOM_ACCOUNT_NAME, QUIET
#   Functions - _set_value, _account_exists, _check_client, _check_refresh_token, _check_access_token, _token_bg_service
# Arguments: None
# Result: read description and start access token check in bg
###################################################
_check_credentials() {
    # set account which will be used, priority CREATE_ACCOUNT_NAME > CUSTOM_ACCOUNT_NAME > DEFAULT_ACCOUNT.
    ACCOUNT_NAME="${CREATE_ACCOUNT_NAME:-${CUSTOM_ACCOUNT_NAME:-${DEFAULT_ACCOUNT}}}"

    # code to handle legacy config
    # this will be triggered only if old config is present, convert to new format
    # new account will be created with "default" name, if default already taken, then add a number as suffix
    export CLIENT_ID CLIENT_SECRET REFRESH_TOKEN
    [ -n "${CLIENT_ID:+${CLIENT_SECRET:+${REFRESH_TOKEN}}}" ] && {
        account_name="default"
        until ! _account_exists "${account_name}"; do
            account_name="${account_name}$((count += 1))"
        done
        regex="^(CLIENT_ID=|CLIENT_SECRET=|REFRESH_TOKEN=|ROOT_FOLDER=|ROOT_FOLDER_NAME=|ACCESS_TOKEN=|ACCESS_TOKEN_EXPIRY=)"
        config_without_values="$(grep -vE "${regex}" "${CONFIG}")"
        chmod u+w "${CONFIG}" # change perms to edit
        printf "%s\n%s\n%s\n%s\n%s\n%s\n" \
            "ACCOUNT_${account_name}_CLIENT_ID=\"${CLIENT_ID}\"" \
            "ACCOUNT_${account_name}_CLIENT_SECRET=\"${CLIENT_SECRET}\"" \
            "ACCOUNT_${account_name}_REFRESH_TOKEN=\"${REFRESH_TOKEN}\"" \
            "ACCOUNT_${account_name}_ROOT_FOLDER=\"${ROOT_FOLDER}\"" \
            "ACCOUNT_${account_name}_ROOT_FOLDER_NAME=\"${ROOT_FOLDER_NAME}\"" \
            "${config_without_values}" >| "${CONFIG}"
        # set default account name if not set
        [ -z "${DEFAULT_ACCOUNT}" ] && printf "%s\n" "DEFAULT_ACCOUNT=\"${account_name}\"" >> "${CONFIG}"

        chmod "a-w-r-x,u+r" "${CONFIG}" # restore perms

        # reload config file
        [ -r "${CONFIG}" ] && . "${CONFIG}"
        ACCOUNT_NAME="${ACCOUNT_NAME:-${DEFAULT_ACCOUNT}}"
    }

    # in case no account existed
    [ -z "${ACCOUNT_NAME}" ] && {
        # if accounts are configured but default account is not set
        if _all_accounts 2>| /dev/null && [ "${COUNT}" -gt 0 ]; then
            "${QUIET:-_print_center}" "normal" " Above accounts are configured, but default one not set. " "="
            if [ -t 1 ]; then
                "${QUIET:-_print_center}" "normal" " Choose default account: " "-"
                until [ -n "${DEFAULT_ACCOUNT}" ]; do
                    printf -- "-> \e[?7l"
                    read -r account_name
                    printf '\e[?7h'
                    if [ "${account_name}" -gt 0 ] && [ "${account_name}" -le "${COUNT}" ]; then
                        _set_value indirect DEFAULT_ACCOUNT "ACC_${COUNT}_ACC"
                    else
                        _clear_line 1
                    fi
                done
            else
                # if not running in a terminal then choose 1st one as default
                printf "%s\n" "Warning: Script is not running in a terminal, choosing first account as default."
                _set_value direct DEFAULT_ACCOUNT "ACC_1_ACC"
            fi
            ACCOUNT_NAME="${DEFAULT_ACCOUNT}" # finally set account name
        else
            _set_account_name ""
        fi
        UPDATE_DEFAULT_ACCOUNT="true" # update default account as it's not set already
    }

    _set_value indirect CLIENT_ID_VALUE "ACCOUNT_${ACCOUNT_NAME}_CLIENT_ID"
    _set_value indirect CLIENT_SECRET_VALUE "ACCOUNT_${ACCOUNT_NAME}_CLIENT_SECRET"
    _set_value indirect REFRESH_TOKEN_VALUE "ACCOUNT_${ACCOUNT_NAME}_REFRESH_TOKEN"
    [ -z "${CLIENT_ID_VALUE:+${CLIENT_SECRET_VALUE:+${REFRESH_TOKEN_VALUE}}}" ] && {
        if [ -t 1 ]; then
            [ -n "${CUSTOM_ACCOUNT_NAME}" ] && "${QUIET:-_print_center}" "normal" " Error: No such account ( ${CUSTOM_ACCOUNT_NAME} ) exists. " "-" && return 1
        else
            printf "%s\n" "Error: Script is not running in a terminal, cannot ask for credentials."
            printf "%s\n" "Add in config manually if terminal is not accessible. CLIENT_ID, CLIENT_SECRET and REFRESH_TOKEN is required. Check README for more info." && return 1
        fi
    }

    {
        _check_client ID "${ACCOUNT_NAME}" &&
            _check_client SECRET "${ACCOUNT_NAME}" &&
            _check_refresh_token "${ACCOUNT_NAME}" &&
            _check_access_token "${ACCOUNT_NAME}" check
    } || return 1

    [ -n "${UPDATE_DEFAULT_ACCOUNT}" ] && _update_config DEFAULT_ACCOUNT "${ACCOUNT_NAME}" "${CONFIG}"

    _token_bg_service # launch token bg service
    return 0
}

###################################################
# Check client id or secret and ask if required
# Globals: 4 variables, 3 functions
#   Variables - CONFIG, CLIENT_ID_REGEX, CLIENT_SECRET_REGEX, QUIET
#   Functions - _print_center, _update_config, _set_value
# Arguments: 2
#   "${1}" = ID or SECRET
#   "${2}" = Account name
# Result: read description and export ACCOUNT_name_CLIENT_[ID|SECRET] CLIENT_[ID|SECRET]
###################################################
_check_client() {
    export CLIENT_ID_REGEX='[0-9]+-[0-9A-Za-z_]{32}\.apps\.googleusercontent\.com' \
        CLIENT_SECRET_REGEX='[0-9A-Za-z_-]+'
    type="CLIENT_${1:?Error: ID or SECRET}" account_name="${2:?Error: Missing account name}"
    type_value="" type_regex="" && unset type_name valid client message
    type_name="ACCOUNT_${account_name}_${type}"

    _set_value indirect type_value "${type_name}"
    _set_value indirect type_regex "${type}_REGEX"

    until [ -n "${type_value}" ] && [ -n "${valid}" ]; do
        [ -n "${type_value}" ] && {
            if printf "%s\n" "${type_value}" | grep -qE "${type_regex}"; then
                [ -n "${client}" ] && _update_config "${type_name}" "${type_value}" "${CONFIG}"
                valid="true" && continue
            else
                { [ -n "${client}" ] && message="- Try again"; } || message="in config ( ${CONFIG} )"
                "${QUIET:-_print_center}" "normal" " Invalid Client ${1} ${message} " "-" && unset "${type_name}" client
            fi
        }
        [ -z "${client}" ] && printf "\n" && "${QUIET:-_print_center}" "normal" " Enter Client ${1} " "-"
        [ -n "${client}" ] && _clear_line 1
        printf -- "-> "
        read -r "${type_name?}" && client=1
        _set_value indirect type_value "${type_name}"
    done

    # export ACCOUNT_name_CLIENT_[ID|SECRET]
    _set_value direct "${type_name}" "${type_value}"
    # export CLIENT_[ID|SECRET]
    _set_value direct "${type}" "${type_value}"

    return 0
}

###################################################
# Check refresh token and ask if required
# Globals: 8 variables, 4 functions
#   Variables -  CLIENT_ID, CLIENT_SECRET, REDIRECT_URI, TOKEN_URL, CONFIG, REFRESH_TOKEN_REGEX, AUTHORIZATION_CODE, QUIET
#   Functions - _set_value, _print_center, _update_config, _check_access_token
# Arguments: 1
#   "${1}" = Account name ( can be empty )
# Result: read description & export REFRESH_TOKEN ACCOUNT_${account_name}_REFRESH_TOKEN
###################################################
_check_refresh_token() {
    export REFRESH_TOKEN_REGEX='[0-9]//[0-9A-Za-z_-]+' \
        AUTHORIZATION_CODE_REGEX='[0-9]/[0-9A-Za-z_-]+'
    account_name="${1:-}"
    refresh_token_name="ACCOUNT_${account_name}_REFRESH_TOKEN"

    _set_value indirect refresh_token_value "${refresh_token_name}"

    [ -n "${refresh_token_value}" ] && {
        ! printf "%s\n" "${refresh_token_value}" | grep -qE "${REFRESH_TOKEN_REGEX}" &&
            "${QUIET:-_print_center}" "normal" " Error: Invalid Refresh token in config file, follow below steps.. " "-" && unset "${refresh_token_name}"
    }

    [ -z "${refresh_token_value}" ] && {
        printf "\n" && "${QUIET:-_print_center}" "normal" "If you have a refresh token generated, then type the token, else leave blank and press return key.." " "
        printf "\n" && "${QUIET:-_print_center}" "normal" " Refresh Token " "-" && printf -- "-> "
        read -r "${refresh_token_name?}" && _set_value indirect refresh_token_value "${refresh_token_name}"
        if [ -n "${refresh_token_value}" ]; then
            "${QUIET:-_print_center}" "normal" " Checking refresh token.. " "-"
            if printf "%s\n" "${refresh_token_value}" | grep -qE "${REFRESH_TOKEN_REGEX}"; then
                _set_value direct REFRESH_TOKEN "${refresh_token_value}"
                { _check_access_token "${account_name}" skip_check &&
                    _update_config "${refresh_token_name}" "${refresh_token_value}" "${CONFIG}"; } || check_error=true
            else
                check_error=true
            fi
            [ -n "${check_error}" ] && "${QUIET:-_print_center}" "normal" " Error: Invalid Refresh token given, follow below steps to generate.. " "-" && unset "${refresh_token_name}"
        else
            "${QUIET:-_print_center}" "normal" " No Refresh token given, follow below steps to generate.. " "-" && unset "${refresh_token_name}"
        fi

        [ -z "${refresh_token_value}" ] && {
            printf "\n" && "${QUIET:-_print_center}" "normal" "Visit the below URL, tap on allow and then enter the code obtained" " "
            URL="https://accounts.google.com/o/oauth2/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&scope=${SCOPE}&response_type=code&prompt=consent"
            printf "\n%s\n" "${URL}"
            unset AUTHORIZATION_CODE authorization_code AUTHORIZATION_CODE_VALID response
            until [ -n "${AUTHORIZATION_CODE}" ] && [ -n "${AUTHORIZATION_CODE_VALID}" ]; do
                [ -n "${AUTHORIZATION_CODE}" ] && {
                    if printf "%s\n" "${AUTHORIZATION_CODE}" | grep -qE "${AUTHORIZATION_CODE_REGEX}"; then
                        AUTHORIZATION_CODE_VALID="true" && continue
                    else
                        "${QUIET:-_print_center}" "normal" " Invalid CODE given, try again.. " "-" && unset AUTHORIZATION_CODE authorization_code
                    fi
                }
                { [ -z "${authorization_code}" ] && printf "\n" && "${QUIET:-_print_center}" "normal" " Enter the authorization code " "-"; } || _clear_line 1
                printf -- "-> \e[?7l"
                read -r AUTHORIZATION_CODE && authorization_code=1
                printf '\e[?7h'
            done
            response="$(curl --compressed "${CURL_PROGRESS}" -X POST \
                --data "code=${AUTHORIZATION_CODE}&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&redirect_uri=${REDIRECT_URI}&grant_type=authorization_code" "${TOKEN_URL}")" || :
            _clear_line 1 1>&2

            refresh_token_value="$(printf "%s\n" "${response}" | _json_value refresh_token 1 1 || :)"
            _set_value direct REFRESH_TOKEN "${refresh_token_value}"
            { _check_access_token "${account_name}" skip_check "${response}" &&
                _update_config "${refresh_token_name}" "${refresh_token_value}" "${CONFIG}"; } || return 1
        }
        printf "\n"
    }

    # export ACCOUNT_name_REFRESH_TOKEN
    _set_value direct "${refresh_token_name}" "${refresh_token_value}"
    # export REFRESH_TOKEN
    _set_value direct REFRESH_TOKEN "${refresh_token_value}"

    return 0
}

###################################################
# Check access token and create/update if required
# Also update in config
# Globals: 9 variables, 3 functions
#   Variables - CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN, TOKEN_URL, CONFIG, API_URL, API_VERSION, QUIET, ACCESS_TOKEN_REGEX
#   Functions - _print_center, _update_config, _set_value
# Arguments: 2
#   "${1}" = Account name
#   "${2}" = if skip_check, then force create access token, else check with regex and expiry
#   "${3}" = json response ( optional )
# Result: read description & export ACCESS_TOKEN ACCESS_TOKEN_EXPIRY
###################################################
_check_access_token() {
    export ACCESS_TOKEN_REGEX='ya29\.[0-9A-Za-z_-]+'
    account_name="${1:?Error: Missing account name}" no_check="${2:-false}" response_json="${3:-}"
    unset token_name token_expiry_name token_value token_expiry_value response
    token_name="ACCOUNT_${account_name}_ACCESS_TOKEN"
    token_expiry_name="${token_name}_EXPIRY"

    _set_value indirect token_value "${token_name}"
    _set_value indirect token_expiry_value "${token_expiry_name}"

    [ "${no_check}" = skip_check ] || [ -z "${token_value}" ] || [ "${token_expiry_value:-0}" -lt "$(date +"%s")" ] || ! printf "%s\n" "${token_value}" | grep -qE "${ACCESS_TOKEN_REGEX}" && {
        response="${response_json:-$(curl --compressed -s -X POST --data "client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&refresh_token=${REFRESH_TOKEN}&grant_type=refresh_token" "${TOKEN_URL}")}" || :
        if token_value="$(printf "%s\n" "${response}" | _json_value access_token 1 1)"; then
            token_expiry_value="$(($(date +"%s") + $(printf "%s\n" "${response}" | _json_value expires_in 1 1) - 1))"
            _update_config "${token_name}" "${token_value}" "${CONFIG}"
            _update_config "${token_expiry_name}" "${token_expiry_value}" "${CONFIG}"
        else
            "${QUIET:-_print_center}" "justify" "Error: Something went wrong" ", printing error." "=" 1>&2
            printf "%s\n" "${response}" 1>&2
            return 1
        fi
    }

    # export ACCESS_TOKEN and ACCESS_TOKEN_EXPIRY
    _set_value direct ACCESS_TOKEN "${token_value}"
    _set_value direct ACCESS_TOKEN_EXPIRY "${token_expiry_value}"

    # export INITIAL_ACCESS_TOKEN which is used on script cleanup
    _set_value INITIAL_ACCESS_TOKEN "${token_value}"
    return 0
}

###################################################
# launch a background service to check access token and update it
# checks ACCESS_TOKEN_EXPIRY, try to update before 5 mins of expiry, a fresh token gets 60 mins
# process will be killed when script exits or "${MAIN_PID}" is killed
# Globals: 4 variables, 1 function
#   Variables - ACCESS_TOKEN, ACCESS_TOKEN_EXPIRY, MAIN_PID, TMPFILE
#   Functions - _check_access_token
# Arguments: None
# Result: read description & export ACCESS_TOKEN_SERVICE_PID
###################################################
_token_bg_service() {
    [ -z "${MAIN_PID}" ] && return 0 # don't start if MAIN_PID is empty
    printf "%b\n" "ACCESS_TOKEN=\"${ACCESS_TOKEN}\"\nACCESS_TOKEN_EXPIRY=\"${ACCESS_TOKEN_EXPIRY}\"" >| "${TMPFILE}_ACCESS_TOKEN"
    {
        until ! kill -0 "${MAIN_PID}" 2>| /dev/null 1>&2; do
            . "${TMPFILE}_ACCESS_TOKEN"
            CURRENT_TIME="$(date +"%s")"
            REMAINING_TOKEN_TIME="$((ACCESS_TOKEN_EXPIRY - CURRENT_TIME))"
            if [ "${REMAINING_TOKEN_TIME}" -le 300 ]; then
                # timeout after 30 seconds, it shouldn't take too long anyway, and update tmp config
                CONFIG="${TMPFILE}_ACCESS_TOKEN" _timeout 30 _check_access_token "" skip_check || :
            else
                TOKEN_PROCESS_TIME_TO_SLEEP="$(if [ "${REMAINING_TOKEN_TIME}" -le 301 ]; then
                    printf "0\n"
                else
                    printf "%s\n" "$((REMAINING_TOKEN_TIME - 300))"
                fi)"
                sleep "${TOKEN_PROCESS_TIME_TO_SLEEP}"
            fi
            sleep 1
        done
    } &
    export ACCESS_TOKEN_SERVICE_PID="${!}"
    return 0
}
