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
    echo -e "\nNo valid arguments provided."
    echo -e "Usage:\n"
    echo -e " ./google-oauth2.sh create - authenticates a user."
    echo -e " ./google-oauth2.sh refresh - gets a new access token."
    exit 0
}

[[ $1 = create ]] || [[ $1 = refresh ]] || shortHelp

# Move cursor to nth no. of line and clear it to the begining.
clearLine() {
    printf "\033[%sA\033[2K" "$1"
}

# Method to extract data from json response
jsonValue() {
    [[ $# = 0 ]] && echo """${FUNCNAME[0]}"": Missing arguments" && return 1
    num="$2"
    grep -o "\"""$1""\"\:.*" | sed -e "s/\"""$1""\": //" -e 's/[",]*$//' -e 's/["]*$//' -e 's/[,]*$//' -e "s/\"//" -n -e "${num}"p
}

# Update Config. Incase of old value, update, for new value add.
# Usage: updateConfig valuename value configpath
updateConfig() {
    [[ $# -lt 3 ]] && echo """${FUNCNAME[0]}"": Missing arguments" && return 1
    declare VALUE_NAME="$1" VALUE="$2" CONFIG_PATH="$3" FINAL=() Aunique=()
    declare -A Aseen
    >> "$CONFIG_PATH" # If config file doesn't exist.
    mapfile -t VALUES < "$CONFIG_PATH" && VALUES+=("$VALUE_NAME=$VALUE")
    for i in "${VALUES[@]}"; do
        [[ $i =~ $VALUE_NAME\= ]] && FINAL+=("$VALUE_NAME=$VALUE") || FINAL+=("$i")
    done
    for i in "${FINAL[@]}"; do
        [[ ${Aseen[$i]} ]] && continue
        printf "%s\n" "$i" && Aseen[$i]=x
    done >| "$CONFIG_PATH"
}

echo "Starting script.."

CLIENT_ID=""
CLIENT_SECRET=""
SCOPE="https://www.googleapis.com/auth/drive"
REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"
TOKEN_URL="https://accounts.google.com/o/oauth2/token"

# shellcheck source=/dev/null
[[ -f $HOME/.googledrive.conf ]] && source "$HOME"/.googledrive.conf

echo "Checking credentials.."

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
echo "Required credentials set."

if [[ $1 = create ]]; then
    echo -e "Visit the below URL, tap on allow and then enter the code obtained:"
    URL="https://accounts.google.com/o/oauth2/auth?client_id=$CLIENT_ID&redirect_uri=$REDIRECT_URI&scope=$SCOPE&response_type=code&prompt=consent"
    echo -e """$URL""\n"
    read -r -p "Enter the authorization code: " CODE

    CODE="${CODE//[[:space:]]/}"
    if [[ -n $CODE ]]; then
        RESPONSE="$(curl --compressed -s -X POST --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token" $TOKEN_URL)"

        ACCESS_TOKEN="$(echo "$RESPONSE" | jsonValue access_token)"
        REFRESH_TOKEN="$(echo "$RESPONSE" | jsonValue refresh_token)"

        echo "Access Token: $ACCESS_TOKEN"
        echo "Refresh Token: $REFRESH_TOKEN"
    else
        echo -e "\nNo code provided, run the script and try again"
        exit 1
    fi
elif [[ $1 = refresh ]]; then
    if [[ -n $REFRESH_TOKEN ]]; then
        RESPONSE="$(curl --compressed -s -X POST --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token" $TOKEN_URL)"
        ACCESS_TOKEN="$(echo "$RESPONSE" | jsonValue access_token)"
        echo "Access Token: $ACCESS_TOKEN"
    else
        echo "Refresh Token not set, use $0 create to generate one."
    fi
fi
