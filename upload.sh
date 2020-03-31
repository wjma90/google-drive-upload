#!/usr/bin/env bash
# Upload a file to Google Drive
# Usage: upload.sh <file> <folder_name>

function usage() {
    echo -e "\nThe script can be used to upload file/directory to google drive."
    echo -e "\nUsage:\n $0 [options..] <filename> <foldername> \n"
    echo -e "Foldername argument is optional. If not provided, the file will be uploaded to preconfigured google drive. \n"
    echo -e "File name argument is optional if create directory option is used. \n"
    echo -e "Options:\n"
    echo -e "-C | --create-dir <foldername> - option to create directory. Will provide folder id."
    echo -e "-r | --root-dir <google_folderid> or <google_folder_url> - google folder ID/URL to which the file/directory is going to upload."
    echo -e "-v | --verbose - Display detailed message."
    echo -e "-V | --verbose-progress - Display detailed message and detailed upload progress."
    echo -e "-z | --config <config_path> - Override default config file with custom config file."
    echo -e "-D | --debug - Display script command trace."
    echo -e "-h | --help - Display usage instructions.\n"
    exit 0
}

function short_help() {
    echo -e "\nNo valid arguments provided, use -h/--help flag to see usage."
    exit 0
}

#Configuration variables
ROOT_FOLDER=""
CLIENT_ID=""
CLIENT_SECRET=""
REFRESH_TOKEN=""
SCOPE="https://www.googleapis.com/auth/drive"
REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"

#Internal variable
ACCESS_TOKEN=""
INPUT=""
FOLDERNAME=""
curl_args="-#"

DIR="$(pwd)"
STRING="$RANDOM"

# shellcheck source=/dev/null
# Config file is created automatically after first run
if [ -e "$HOME"/.googledrive.conf ]; then
    source "$HOME"/.googledrive.conf
fi

PROGNAME=${0##*/}
SHORTOPTS="v,V,hr:C:D,z:"
LONGOPTS="verbose,verbose-progress,progress-bar,help,create-dir:,root-dir:,debug,config:"

set -o errexit -o noclobber -o pipefail #-o nounset
OPTS=$(getopt -s bash --options $SHORTOPTS --longoptions $LONGOPTS --name "$PROGNAME" -- "$@")

# script to parse the input arguments
#if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

eval set -- "$OPTS"

VERBOSE=false
VERBOSE_PROGRESS=false
DEBUG=false
CONFIG=""
ROOTDIR=""

while true; do
    case "$1" in
        -v | --verbose)
            VERBOSE=true
            shift
            ;;
        -V | --verbose-progress)
            VERBOSE_PROGRESS=true
            curl_args=""
            shift
            ;;
        -h | --help)
            usage
            shift
            ;;
        -C | --create-dir)
            FOLDERNAME="$2"
            shift 2
            ;;
        -r | --root-dir)
            ROOTDIR="$2"
            shift 2
            ;;
        -z | --config)
            CONFIG="$2"
            shift 2
            ;;
        -D | --debug)
            DEBUG=true
            shift
            ;;
        --)
            shift
            break
            ;;
        *) break ;;
    esac
done

if [ "$DEBUG" = true ]; then
    set -xe
fi

# shellcheck source=/dev/null
if [ -n "$CONFIG" ]; then
    if [ -e "$CONFIG" ]; then
        source "$CONFIG"
    fi

fi

if [ -n "$1" ]; then
    input="$1"
fi

if [ -n "$2" ] && [ -z "$FOLDERNAME" ]; then
    FOLDERNAME="$2"
fi

if [ "$#" = "0" ] && [ -z "$FOLDERNAME" ]; then
    short_help
    exit 0
fi

echo "Starting script.."

if [ -n "$VERBOSE_PROGRESS" ]; then
    if [ -n "$VERBOSE" ]; then
        unset "$VERBOSE"
    fi
fi

# Extract file/folder ID from the given input in case of gdrive URL.
extractID() {
    ID="$1"
    case "$ID" in
        'http'*'://'*'drive.google.com'*'id='*) ID=$(echo "$ID" | sed -e 's/^.*id=//' -e 's|&|\n|' | head -1) ;;
        'http'*'drive.google.com'*'file/d/'* | 'http'*'docs.google.com/file/d/'*) ID=$(echo "$ID" | sed -e's/^.*\/d\///' -e 's/\/.*//') ;;
        'http'*'drive.google.com'*'drive'*'folders'*) ID=$(echo "$ID" | sed -e 's/^.*\/folders\///' -e "s/&.*//" -e -r 's/(.*)\/.*/\1 /') ;;
    esac
    echo "$ID"
}

# Clear nth no. of line to the beginning of the line.
function clear() {
    echo -en "\033[""$1""A"
    echo -en "\033[2K"
}

# Method to extract data from json response
function jsonValue() {
    num=$2
    grep \""$1"\" | sed "s/\:/\n/" | grep -v \""$1"\" | sed "s/\"\,//g" | sed 's/["]*$//' | sed 's/[,]*$//' | sed 's/^[ \t]*//' | sed s/\"// | sed -n "${num}"p
}

# sed url escaping
function urlEscape() {
    sed 's|%|%25|g' \
        | sed 's| |%20|g' \
        | sed 's|<|%3C|g' \
        | sed 's|>|%3E|g' \
        | sed 's|#|%23|g' \
        | sed 's|{|%7B|g' \
        | sed 's|}|%7D|g' \
        | sed 's|\||%7C|g' \
        | sed 's|\\|%5C|g' \
        | sed 's|\^|%5E|g' \
        | sed 's|~|%7E|g' \
        | sed 's|\[|%5B|g' \
        | sed 's|\]|%5D|g' \
        | sed 's|`|%60|g' \
        | sed 's|;|%3B|g' \
        | sed 's|/|%2F|g' \
        | sed 's|?|%3F|g' \
        | sed 's^|^%3A^g' \
        | sed 's|@|%40|g' \
        | sed 's|=|%3D|g' \
        | sed 's|&|%26|g' \
        | sed 's|\$|%24|g' \
        | sed 's|\!|%21|g' \
        | sed 's|\*|%2A|g'
}

# Method to get information for a gdrive folder/file.
# Requirements: Given file/folder ID, query, and access_token.
function drive_Info() {
    FOLDER_ID="$1"
    FETCH="$2"
    ACCESS_TOKEN="$3"
    SEARCH_RESPONSE="$(curl \
        --silent \
        -XGET \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "https://www.googleapis.com/drive/v3/files/""$FOLDER_ID""?fields=""$FETCH""")"
    FETCHED_DATA="$(echo "$SEARCH_RESPONSE" | jsonValue "$FETCH" | head -1)"
    echo "$FETCHED_DATA"
}

# Method to create directory in google drive.
# Requirements: Foldername, Root folder ID ( the folder in which the new folder will be created ) and access_token.
# First check if a folder exist in given parent directory, if not the case then make the folder.
# Atlast print folder ID ( existing or new one ).
function createDirectory() {
    DIRNAME="$1"
    ROOTDIR="$2"
    ACCESS_TOKEN="$3"
    FOLDER_ID=""
    QUERY="mimeType='application/vnd.google-apps.folder' and name='$DIRNAME' and trashed=false and '$ROOTDIR' in parents"
    QUERY="$(echo "$QUERY" | urlEscape)"

    SEARCH_RESPONSE="$(curl \
        --silent \
        -XGET \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "https://www.googleapis.com/drive/v3/files?q=${QUERY}&fields=files(id)")"
    FOLDER_ID="$(echo "$SEARCH_RESPONSE" | jsonValue id | head -1)"
    if [ -z "$FOLDER_ID" ]; then
        CREATE_FOLDER_POST_DATA="{\"mimeType\": \"application/vnd.google-apps.folder\",\"name\": \"$DIRNAME\",\"parents\": [\"$ROOTDIR\"]}"
        CREATE_FOLDER_RESPONSE="$(curl \
            --silent \
            -X POST \
            -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            -H "Content-Type: application/json; charset=UTF-8" \
            -d "$CREATE_FOLDER_POST_DATA" \
            "https://www.googleapis.com/drive/v3/files?fields=id")"
        FOLDER_ID="$(echo "$CREATE_FOLDER_RESPONSE" | jsonValue id)"
    fi
    echo "$FOLDER_ID"
}

# Method to upload files to google drive.
# Requirements: Given file path, Google folder ID and access_token.
function uploadFile() {
    INPUT="$1"
    FOLDER_ID="$2"
    ACCESS_TOKEN="$3"
    SLUG="$(basename "$INPUT")"
    INPUTNAME="${SLUG%.*}"
    EXTENSION="${SLUG##*.}"
    INPUTSIZE="$(stat -c%s "$INPUT")"
    READABLE_SIZE="$(du -sh "$INPUT" | awk '{print $1;}')"
    #info "File: ""${INPUT//$DIR\//}"""
    echo "File: ""$(basename "$INPUT")"" ""$READABLE_SIZE"""
    if [[ "$INPUTNAME" == "$EXTENSION" ]]; then
        if command -v mimetype > /dev/null 2>&1; then
            MIME_TYPE="$(mimetype --output-format %m "$INPUT")"
        elif command -v file > /dev/null 2>&1; then
            MIME_TYPE="$(file --brief --mime-type "$INPUT")"
        else
            echo -e "\nError: file or mimetype command not found."
            exit 1
        fi

    fi

    # JSON post data to specify the file name and folder under while the file to be created
    postData="{\"mimeType\": \"$MIME_TYPE\",\"name\": \"$SLUG\",\"parents\": [\"$FOLDER_ID\"]}"

    # Curl command to initiate resumable upload session and grab the location URL
    echo "Generating upload link..."
    uploadlink="$(curl \
        --silent \
        -X POST \
        -H "Host: www.googleapis.com" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json; charset=UTF-8" \
        -H "X-Upload-Content-Type: $MIME_TYPE" \
        -H "X-Upload-Content-Length: $INPUTSIZE" \
        -d "$postData" \
        "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true&supportsTeamDrives=true" \
        --dump-header - | sed -ne s/"Location: "//pi | tr -d '\r\n')"

    if [ -n "$uploadlink" ]; then
        # Curl command to push the file to google drive.
        # If the file size is large then the content can be split to chunks and uploaded.
        # In that case content range needs to be specified.
        clear 1
        echo "Uploading..."
        if [ -n "$curl_args" ]; then
            curl \
                -X PUT \
                -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                -H "Content-Type: $MIME_TYPE" \
                -H "Content-Length: $INPUTSIZE" \
                -H "Slug: $SLUG" \
                -T "$INPUT" \
                --output /dev/null \
                --url "$uploadlink" \
                "$curl_args"
        else
            curl \
                -X PUT \
                -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                -H "Content-Type: $MIME_TYPE" \
                -H "Content-Length: $INPUTSIZE" \
                -H "Slug: $SLUG" \
                -T "$INPUT" \
                --output /dev/null \
                --url "$uploadlink"
        fi

        if [ "$VERBOSE_PROGRESS" = true ]; then
            echo "File: ""$INPUTNAME"" (""$READABLE_SIZE"") Uploaded"
        else
            clear 1
            clear 1
            clear 1
            echo "File: ""$INPUTNAME"" (""$READABLE_SIZE"") Uploaded"
        fi
    else
        echo "Upload link generation error, file not uploaded."
    fi
}

echo "Checking credentials.."
# Credentials
if [ -z "$CLIENT_ID" ]; then
    read -r -p "Client ID: " CLIENT_ID
    echo "CLIENT_ID=$CLIENT_ID" >> "$HOME"/.googledrive.conf
fi
if [ -z "$CLIENT_SECRET" ]; then
    read -r -p "Client Secret: " CLIENT_SECRET
    echo "CLIENT_SECRET=$CLIENT_SECRET" >> "$HOME"/.googledrive.conf
fi

# Method to obtain refresh_token.
# Requirements: client_id, client_secret and authorization code.
if [ -z "$REFRESH_TOKEN" ]; then
    read -r -p "If you have a refresh token generated, then type the token, else leave blank and press return key..
    Refresh Token: " REFRESH_TOKEN
    REFRESH_TOKEN="$(echo "$REFRESH_TOKEN" | tr -d ' ' | tr -d '[:blank:]' | tr -d '[:space:]')"
    if [ -n "$REFRESH_TOKEN" ]; then
        echo "REFRESH_TOKEN=$REFRESH_TOKEN" >> "$HOME"/.googledrive.conf
    else
        echo -e "\nVisit the below URL, tap on allow and then enter the code obtained:"
        URL="https://accounts.google.com/o/oauth2/auth?client_id=$CLIENT_ID&redirect_uri=$REDIRECT_URI&scope=$SCOPE&response_type=code&prompt=consent"
        echo -e """$URL""\n"
        read -r -p "Enter the authorization code: " CODE
        CODE="$(echo "$CODE" | tr -d ' ' | tr -d '[:blank:]' | tr -d '[:space:]')"
        if [ -n "$CODE" ]; then
            RESPONSE="$(curl -s --request POST --data "code=$CODE&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&redirect_uri=$REDIRECT_URI&grant_type=authorization_code" https://accounts.google.com/o/oauth2/token)"

            ACCESS_TOKEN="$(echo "$RESPONSE" | jsonValue access_token)"
            REFRESH_TOKEN="$(echo "$RESPONSE" | jsonValue refresh_token)"

            echo "REFRESH_TOKEN=""$REFRESH_TOKEN""" >> "$HOME"/.googledrive.conf
        else
            echo -e "\nNo code provided, run the script and try again"
            exit 1
        fi
    fi
fi

# Method to regenerate access_token.
# Make a request on https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$ACCESS_TOKEN url and check if the given token is valid, if not generate one.
# Requirements: Refresh Token
if [ -z "$ACCESS_TOKEN" ]; then
    RESPONSE="$(curl -s --request POST --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token" https://accounts.google.com/o/oauth2/token)"
    ACCESS_TOKEN="$(echo "$RESPONSE" | jsonValue access_token)"
elif curl -s "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$ACCESS_TOKEN" | jsonValue error > /dev/null 2>&1; then
    RESPONSE="$(curl -s --request POST --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token" https://accounts.google.com/o/oauth2/token)"
    ACCESS_TOKEN="$(echo "$RESPONSE" | jsonValue access_token)"
fi

clear 1
clear 1
echo "Required credentials available."
echo "Checking root dir and workspace folder.."
# Setup root directory where all file/folders will be uploaded.
if [ -n "$ROOTDIR" ]; then
    ROOT_FOLDER="$(echo "$ROOTDIR" | tr -d ' ' | tr -d '[:blank:]' | tr -d '[:space:]')"
    if [ -n "$ROOT_FOLDER" ]; then
        ROOT_FOLDER="$(drive_Info "$(extractID "$ROOT_FOLDER")" "id" "$ACCESS_TOKEN")"
        if [ -n "$ROOT_FOLDER" ]; then
            ROOT_FOLDER="$ROOT_FOLDER"
            echo "ROOT_FOLDER=$ROOT_FOLDER" >> "$HOME"/.googledrive.conf
        else
            echo "Given root folder ID/URL invalid."
            exit 1
        fi
    fi
elif [ -z "$ROOT_FOLDER" ]; then
    read -r -p "Root Folder ID or URL (Default: root): " ROOT_FOLDER
    ROOT_FOLDER="$(echo "$ROOT_FOLDER" | tr -d ' ' | tr -d '[:blank:]' | tr -d '[:space:]')"
    if [ -n "$ROOT_FOLDER" ]; then
        ROOT_FOLDER="$(folderInfo "$(extractID "$ROOT_FOLDER")" "$ACCESS_TOKEN")"
        if [ -n "$ROOT_FOLDER" ]; then
            ROOT_FOLDER="$ROOT_FOLDER"
            echo "ROOT_FOLDER=$ROOT_FOLDER" >> "$HOME"/.googledrive.conf
        else
            echo "Given root folder ID/URL invalid."
            exit 1
        fi
    else
        ROOT_FOLDER="root"
        echo "ROOT_FOLDER=$ROOT_FOLDER" >> "$HOME"/.googledrive.conf
    fi
fi

clear 1
clear 1
echo "Root dir properly configured."
# Check to find whether the folder exists in google drive. If not then the folder is created in google drive under the configured root folder.
if [ -z "$FOLDERNAME" ]; then
    ROOT_FOLDER_ID=$ROOT_FOLDER
else
    ROOT_FOLDER_ID="$(createDirectory "$FOLDERNAME" "$ROOT_FOLDER" "$ACCESS_TOKEN")"
fi
ROOT_FOLDER_NAME="$(drive_Info """$ROOT_FOLDER_ID""" name """$ACCESS_TOKEN""")"
clear 1
echo "Workspace Folder: $ROOT_FOLDER_NAME ($ROOT_FOLDER_ID)"

START=$(date +"%s")

# Check if the argument is a file or a directory.
# In case of file, just upload it.
# In case of folder, do a recursive upload in the same hierarchical manner present.
if [ -n "$input" ]; then
    if [ -f "$input" ]; then
        echo -e "Given Input: File\n"
        uploadFile "$input" "$ROOT_FOLDER_ID" "$ACCESS_TOKEN"
        echo
    elif [ -d "$input" ]; then
        echo "Given Input: Folder"
        NEXTROOTDIRID="$ROOT_FOLDER_ID"
        # Do not create empty folders during a recursive upload.
        # The use of find in this section is important.
        # If below command is used, it lists the folder in stair structure, which we later assume while creating sub folders and uploading files.
        find "$input" -type d -not -empty | sed "s|$input|$DIR/$input|" > "$STRING"DIRNAMES
        # Create a loop and make folders according to list made above.
        if [ -n "$(sed '1d' "$STRING"DIRNAMES)" ]; then
            echo "Indexing sub-directories..."
        fi

        while IFS= read -r dir; do
            newdir="$(basename "$dir")"
            ID="$(createDirectory "$newdir" "$NEXTROOTDIRID" "$ACCESS_TOKEN")"
            # Store sub-folder directory IDs and it's path for later use.
            echo "$ID '$dir'" >> "$STRING"DIRIDS
            NEXTROOTDIRID=$ID
        done < "$STRING"DIRNAMES

        if [ -n "$(sed '1d' "$STRING"DIRNAMES)" ]; then
            clear 1
            echo -e "No. of sub-directories: ""$(sed '1d' "$STRING"DIRNAMES | wc -l)""\n"
        fi

        if [ -f "$STRING"DIRNAMES ]; then rm "$STRING"DIRNAMES; fi
        echo "Indexing files recursively..."
        find "$input" -type f | sed "s|$input|$DIR/$input|" > "$STRING"FILENAMES
        clear 1
        clear 1
        echo "No. of Files: ""$(grep -c "" "$STRING"FILENAMES)"""
        if [ "$VERBOSE" = true ] || [ "$VERBOSE_PROGRESS" = true ]; then
            echo
        else
            echo -e "\n"
        fi

        # shellcheck disable=SC2001
        # Match the path with sub-folder directory ID and upload accordingly.
        while read -r i; do sed "s/\(.*\)\/$(basename "$i")/\1/" <<< "$i"; done < "$STRING"FILENAMES > "$STRING"FILES_ROOTDIR

        while IFS= read -r -u 4 rootdirpath && IFS= read -r -u 5 file; do
            dirtoupload="$(grep "'$rootdirpath'" "$STRING"DIRIDS | awk '{print $1;}')"
            uploadFile "$file" "$dirtoupload" "$ACCESS_TOKEN"
            echo "$file" >> "$STRING"UPLOADED
            uploaded="$(grep -c "" "$STRING"UPLOADED)"
            if [ "$VERBOSE" = true ] || [ "$VERBOSE_PROGRESS" = true ]; then
                echo -e "Status: $uploaded files uploaded.\n"
            else
                clear 1
                clear 1
                echo "Status: $uploaded files uploaded."
            fi
        done 4< "$STRING"FILES_ROOTDIR 5< "$STRING"FILENAMES

        if [ "$VERBOSE" = true ] || [ "$VERBOSE_PROGRESS" = true ]; then
            echo -e "Total Files Uploaded: ""$(grep -c "" "$STRING"FILENAMES)""\n"
        else
            clear 1
            clear 1
            echo -e "Total Files Uploaded: ""$(grep -c "" "$STRING"FILENAMES)""\n"
        fi

        if [ -f "$STRING"DIRIDS ]; then rm "$STRING"DIRIDS; fi
        if [ -f "$STRING"FILES_ROOTDIR ]; then rm "$STRING"FILES_ROOTDIR; fi
        if [ -f "$STRING"FILENAMES ]; then rm "$STRING"FILENAMES; fi
        if [ -f "$STRING"UPLOADED ]; then rm "$STRING"UPLOADED; fi
    fi
fi

END="$(date +"%s")"
DIFF="$((END - START))"
echo "Total time elapsed: "$((DIFF / 60))" minute(s) and "$((DIFF % 60))" seconds"

if [ "$DEBUG" = true ]; then
    set +xe
fi
