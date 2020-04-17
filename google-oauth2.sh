#!/usr/bin/env bash

# A simple curl OAuth2 authenticator
#
# Usage:
#	./google-oauth2.sh create - authenticates a user
#	./google-oauth2.sh refresh <token> - gets a new token
#
# Set CLIENT_ID and CLIENT_SECRET and SCOPE
# See SCOPES at https://developers.google.com/identity/protocols/oauth2/scopes#docsv1

short_help() {
    echo -e "\nNo valid arguments provided."
    echo -e "Usage:\n"
    echo -e " ./google-oauth2.sh create - authenticates a user."
    echo -e " ./google-oauth2.sh refresh - gets a new access token."
    exit 0
}

[ "$#" = "0" ] && short_help

# Clear nth no. of line to the beginning of the line.
clear_line() {
    echo -en "\033[""$1""A"
    echo -en "\033[2K"
}

[ "$1" = create ] || [ "$1" = refresh ] || short_help

echo "Starting script.."

CLIENT_ID=""
CLIENT_SECRET=""
SCOPE="https://www.googleapis.com/auth/drive"
REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"

# shellcheck source=/dev/null
[ -e "$HOME"/.googledrive.conf ] && source "$HOME"/.googledrive.conf

echo "Checking credentials.."

if [ -z "$CLIENT_ID" ]; then
    read -r -p "Client ID: " CLIENT_ID
    unset token
    echo "CLIENT_ID=$CLIENT_ID" >> "$HOME"/.googledrive.conf
fi

if [ -z "$CLIENT_SECRET" ]; then
    read -r -p "Client Secret: " CLIENT_SECRET
    unset token
    echo "CLIENT_SECRET=$CLIENT_SECRET" >> "$HOME"/.googledrive.conf
fi

sleep 1
clear_line 1
clear_line 1
echo "Required credentials set."
sleep 1

# Method to extract data from json response
jsonValue() {
    num="$2"
    grep \""$1"\" | sed "s/\:/\n/" | grep -v \""$1"\" | sed -e "s/\"\,//g" -e 's/["]*$//' -e 's/[,]*$//' -e 's/^[ \t]*//' -e s/\"// | sed -n "${num}"p
}

if [ "$1" == "create" ]; then
    echo "\nVisit the below URL, tap on allow and then enter the code obtained:"
    sleep 1
    URL="https://accounts.google.com/o/oauth2/auth?client_id=$CLIENT_ID&redirect_uri=$REDIRECT_URI&scope=$SCOPE&response_type=code&prompt=consent"
    echo -e """$URL""\n"
    read -r -p "Enter the authorization code: " CODE

    CODE="$(echo "$CODE" | tr -d ' ' | tr -d '[:blank:]' | tr -d '[:space:]')"
    if [ -n "$CODE" ]; then
        RESPONSE="$(curl -s --request POST --data "code=$CODE&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&redirect_uri=$REDIRECT_URI&grant_type=authorization_code" https://accounts.google.com/o/oauth2/token)"

        ACCESS_TOKEN="$(echo "$RESPONSE" | jsonValue access_token)"
        REFRESH_TOKEN="$(echo "$RESPONSE" | jsonValue refresh_token)"

        echo "Access Token: $ACCESS_TOKEN"
        echo "Refresh Token: $REFRESH_TOKEN"
    else
        echo -e "\nNo code provided, run the script and try again"
        exit 1
    fi
elif [ "$1" == "refresh" ]; then
    if [ -n "$REFRESH_TOKEN" ]; then
        RESPONSE="$(curl -s --request POST --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token" https://accounts.google.com/o/oauth2/token)"
        ACCESS_TOKEN="$(echo "$RESPONSE" | jsonValue access_token)"
        echo "Access Token: $ACCESS_TOKEN"
    else
        echo "Refresh Token not set, use $0 create to generate one."
    fi
fi
