#!/usr/bin/env bash

# A simple curl OAuth2 authenticator
#
# Usage:
#	./google-oauth2.sh create - authenticates a user
#	./google-oauth2.sh refresh <token> - gets a new token
#
# Set CLIENT_ID and CLIENT_SECRET and SCOPE
# See SCOPES at https://developers.google.com/identity/protocols/oauth2/scopes#docsv1

shortHelp() {
    printf "
No valid arguments provided.
Usage:

 ./%s create - authenticates a user.
 ./%s refresh - gets a new access token.\n" "$0" "$0"
    exit 0
}

[[ $1 = create ]] || [[ $1 = refresh ]] || shortHelp

# Move cursor to nth no. of line and clear it to the begining.
clearLine() {
    printf "\033[%sA\033[2K" "$1"
}

# Method to extract data from json response.
# Usage: jsonValue key < json ( or use with a pipe output ).
jsonValue() {
    [[ $# = 0 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare LC_ALL=C num="${2:-1}"
    grep -o "\"""$1""\"\:.*" | sed -e "s/.*\"""$1""\": //" -e 's/[",]*$//' -e 's/["]*$//' -e 's/[,]*$//' -e "s/\"//" -n -e "${num}"p
}

# Update Config. Incase of old value, update, for new value add.
# Usage: updateConfig valuename value configpath
updateConfig() {
    [[ $# -lt 3 ]] && printf "%s: Missing arguments\n" "${FUNCNAME[0]}" && return 1
    declare VALUE_NAME="$1" VALUE="$2" CONFIG_PATH="$3" FINAL=()
    declare -A Aseen
    printf "" >> "$CONFIG_PATH" # If config file doesn't exist.
    mapfile -t VALUES < "$CONFIG_PATH" && VALUES+=("$VALUE_NAME=$VALUE")
    for i in "${VALUES[@]}"; do
        [[ $i =~ $VALUE_NAME\= ]] && FINAL+=("$VALUE_NAME=$VALUE") || FINAL+=("$i")
    done
    for i in "${FINAL[@]}"; do
        [[ ${Aseen[$i]} ]] && continue
        printf "%s\n" "$i" && Aseen[$i]=x
    done >| "$CONFIG_PATH"
}

printf "Starting script..\n"

CLIENT_ID=""
CLIENT_SECRET=""
SCOPE="https://www.googleapis.com/auth/drive"
REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"
TOKEN_URL="https://accounts.google.com/o/oauth2/token"

# shellcheck source=/dev/null
[[ -f $HOME/.googledrive.conf ]] && source "$HOME"/.googledrive.conf

printf "Checking credentials..\n"

# Credentials
if [[ -z $CLIENT_ID ]]; then
    read -r -p "Client ID: " CLIENT_ID
    updateConfig CLIENT_ID "$CLIENT_ID" "$HOME"/.googledrive.conf
fi
if [[ -z $CLIENT_SECRET ]]; then
    read -r -p "Client Secret: " CLIENT_SECRET
    updateConfig CLIENT_SECRET "$CLIENT_SECRET" "$HOME"/.googledrive.conf
fi

for _ in {1..2}; do clearLine 1; done
printf "Required credentials set.\n"

if [[ $1 = create ]]; then
    printf "Visit the below URL, tap on allow and then enter the code obtained:\n"
    URL="https://accounts.google.com/o/oauth2/auth?client_id=$CLIENT_ID&redirect_uri=$REDIRECT_URI&scope=$SCOPE&response_type=code&prompt=consent"
    printf "%s\n\n" "$URL"
    read -r -p "Enter the authorization code: " CODE

    CODE="${CODE//[[:space:]]/}"
    if [[ -n $CODE ]]; then
        RESPONSE="$(curl --compressed -s -X POST --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token" $TOKEN_URL)"

        ACCESS_TOKEN="$(jsonValue access_token <<< "$RESPONSE")"
        REFRESH_TOKEN="$(jsonValue refresh_token <<< "$RESPONSE")"

        printf "Access Token: %s\n" "$ACCESS_TOKEN"
        printf "Refresh Token: %s\n" "$REFRESH_TOKEN"
    else
        printf "\nNo code provided, run the script and try again.\n"
        exit 1
    fi
elif [[ $1 = refresh ]]; then
    if [[ -n $REFRESH_TOKEN ]]; then
        RESPONSE="$(curl --compressed -s -X POST --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token" $TOKEN_URL)"
        ACCESS_TOKEN="$(echo "$RESPONSE" | jsonValue access_token)"
        printf "Access Token: %s\n" "$ACCESS_TOKEN"
    else
        printf "Refresh Token not set, use %s create to generate one.\n" "$0"
    fi
fi
