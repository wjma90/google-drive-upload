#!/usr/bin/env bash
# Upload a file to Google Drive
# Usage: upload.sh <file> <folder_name>

usage() {
    echo -e "\nThe script can be used to upload file/directory to google drive."
    echo -e "\nUsage:\n $0 [options..] <filename> <foldername> \n"
    echo -e "Foldername argument is optional. If not provided, the file will be uploaded to preconfigured google drive. \n"
    echo -e "File name argument is optional if create directory option is used. \n"
    echo -e "Options:\n"
    echo -e "  -C | --create-dir <foldername> - option to create directory. Will provide folder id.\n"
    echo -e "  -r | --root-dir <google_folderid> or <google_folder_url> - google folder ID/URL to which the file/directory is going to upload.\n"
    echo -e "  -s | --skip-subdirs - Skip creation of sub folders and upload all files inside the INPUT folder/sub-folders in the INPUT folder, use this along with -p/--parallel option to speed up the uploads.\n"
    echo -e "  -p | --parallel <no_of_files_to_parallely_upload> - Upload multiple files in parallel, only works along with --skip-subdirs/-s option, Max value = 10\n"
    echo -e "  -i | --save-info <file_to_save_info> - Save uploaded files info to the given filename.\n"
    echo -e "  -z | --config <config_path> - Override default config file with custom config file.\n"
    echo -e "  -v | --verbose - Display detailed message.\n"
    echo -e "  -V | --verbose-progress - Display detailed message and detailed upload progress.\n"
    echo -e "  -D | --debug - Display script command trace.\n"
    echo -e "  -h | --help - Display usage instructions.\n"
    exit 0
}

shortHelp() {
    echo -e "\nNo valid arguments provided, use -h/--help flag to see usage."
    exit 0
}

# Print short help
[ "$#" = "0" ] && shortHelp

# allow a command to fail with !’s side effect on errexit
# use return value from ${PIPESTATUS[0]}, because ! hosed $?
getopt --test > /dev/null && exit 1
if [ "${PIPESTATUS[0]}" -ne 4 ]; then
    echo 'getopt --test failed in this environment, cannot run the script.'
    exit 1
fi

PROGNAME=${0##*/}
SHORTOPTS="v,V,i:,s,p:,hr:C:D,z:"
LONGOPTS="verbose,verbose-progress,save-info:,help,create-dir:,root-dir:,debug,config:"

if ! OPTS=$(getopt -q --options "$SHORTOPTS" --longoptions "$LONGOPTS" --name "$PROGNAME" -- "$@"); then
    shortHelp
    exit 1
fi

set -o errexit -o noclobber -o pipefail # -o nounset

eval set -- "$OPTS"

#Configuration variables
ROOT_FOLDER=""
CLIENT_ID=""
CLIENT_SECRET=""
REFRESH_TOKEN=""
SCOPE="https://www.googleapis.com/auth/drive"
REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"

# shellcheck source=/dev/null
# Config file is created automatically after first run
[ -e "$HOME"/.googledrive.conf ] && source "$HOME"/.googledrive.conf

#Internal variable
ACCESS_TOKEN=""
INPUT=""
FOLDERNAME=""
CURL_ARGS="-#"
DIR="$(pwd)"
STRING="$RANDOM"
VERBOSE=""
VERBOSE_PROGRESS=""
DEBUG=""
CONFIG=""
ROOTDIR=""
LOG_FILE_ID=""
SKIP_SUBDIRS=""
PARALLEL=""
NO_OF_PARALLEL_JOBS=""

while true; do
    case "${1}" in
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
        -i | --save-info)
            LOG_FILE_ID="$2"
            shift 2
            ;;
        -s | --skip-subdirs)
            SKIP_SUBDIRS=true
            shift
            ;;
        -p | --parallel)
            PARALLEL=true
            NO_OF_PARALLEL_JOBS="$2"
            shift 2
            ;;
        -v | --verbose)
            VERBOSE=true
            shift
            ;;
        -V | --verbose-progress)
            VERBOSE_PROGRESS=true
            CURL_ARGS=""
            shift
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

if [ -n "$1" ]; then
    INPUT="$1"
    if [[ ! -f $INPUT ]] && [[ ! -d $INPUT ]]; then
        echo -e "\nError: Invalid Input, no such  or directory.\n"
        exit 1
    fi
elif [ -z "$FOLDERNAME" ]; then
    shortHelp
fi

if [ -n "$PARALLEL" ]; then
    if [ -d "$INPUT" ]; then
        if [ "$SKIP_SUBDIRS" != true ]; then
            echo -e "\nError: -p/--parallel option can be only used if -s/--skip-dirs option is used."
            exit 0
        fi
        case "$NO_OF_PARALLEL_JOBS" in
            '' | *[!0-9]*)
                echo -e "\nError: -p/--parallel values range between 1 to 10."
                exit 0
                ;;
            *)
                [ "$NO_OF_PARALLEL_JOBS" -gt 10 ] && NO_OF_PARALLEL_JOBS=10
                ;;
        esac
    elif [ -f "$INPUT" ]; then
        unset PARALLEL
    fi
fi

if [ -n "$DEBUG" ]; then
    set -xe
    # To avoid spamming in debug mode.
    printCenter() {
        echo -e "${1}"
    }
    printCenterJustify() {
        echo -e "${1}"
    }
else
    # https://gist.github.com/TrinityCoder/911059c83e5f7a351b785921cf7ecdaa
    printCenter() {
        # This refreshes the interactive shell so we can use the $COLUMNS variable.
        cat /dev/null

        [[ $# == 0 ]] && return 1
        declare -i TERM_COLS="$COLUMNS"

        out="$1"

        declare -i str_len=${#out}
        [[ $str_len -ge $TERM_COLS ]] && {
            echo "$out"
            return 0
        }

        declare -i filler_len="$(((TERM_COLS - str_len) / 2))"
        [[ $# -ge 2 ]] && ch="${2:0:1}" || ch=" "
        filler=""
        for ((i = 0; i < filler_len; i++)); do
            filler="${filler}${ch}"
        done

        printf "%s%s%s" "$filler" "$out" "$filler"
        [[ $(((TERM_COLS - str_len) % 2)) -ne 0 ]] && printf "%s" "${ch}"
        printf "\n"

        return 0
    }
    # To avoid entering a new line, and maintaining the output flow.
    printCenterJustify() {
        # This refreshes the interactive shell so we can use the $COLUMNS variable.
        cat /dev/null

        [[ $# == 0 ]] && return 1
        declare -i TERM_COLS="$COLUMNS"

        out="$1"

        TO_PRINT="$((TERM_COLS * 98 / 100))"
        if [ "${#1}" -gt "$TO_PRINT" ]; then
            out="${1:0:TO_PRINT}.."
        fi

        declare -i str_len=${#out}
        [[ $str_len -ge $TERM_COLS ]] && {
            echo "$out"
            return 0
        }

        declare -i filler_len="$(((TERM_COLS - str_len) / 2))"
        [[ $# -ge 2 ]] && ch="${2:0:1}" || ch=" "
        filler=""
        for ((i = 0; i < filler_len; i++)); do
            filler="${filler}${ch}"
        done

        printf "%s%s%s" "$filler" "$out" "$filler"
        [[ $(((TERM_COLS - str_len) % 2)) -ne 0 ]] && printf "%s" "${ch}"
        printf "\n"

        return 0
    }
fi

# Check if skip subdirs creation option was enabled or not.
# Then, check for the max value of parallel downloads.

# shellcheck source=/dev/null
[ -n "$CONFIG" ] && [ -e "$CONFIG" ] && source "$CONFIG"

[ -n "${2}" ] && [ -z "$FOLDERNAME" ] && FOLDERNAME="${2}"

printCenter "[ Starting script ]" "="

[ -n "$VERBOSE_PROGRESS" ] && [ -n "$VERBOSE" ] && unset "$VERBOSE"

# Extract file/folder ID from the given INPUT in case of gdrive URL.
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
clearLine() {
    echo -en "\033[""$1""A"
    echo -en "\033[2K"
}

# Method to extract data from json response
jsonValue() {
    num="$2"
    grep \""$1"\" | sed "s/\:/\n/" | grep -v \""$1"\" | sed -e "s/\"\,//g" -e 's/["]*$//' -e 's/[,]*$//' -e 's/^[ \t]*//' -e s/\"// | sed -n "${num}"p
}

# Usage: urlEncode "string"
urlEncode() {
    local LC_ALL=C
    for ((i = 0; i < ${#1}; i++)); do
        : "${1:i:1}"
        case "$_" in
            [a-zA-Z0-9.~_-])
                printf '%s' "$_"
                ;;
            *)
                printf '%%%02X' "'$_"
                ;;
        esac
    done
    printf '\n'
}

# Method to get information for a gdrive folder/file.
# Requirements: Given file/folder ID, query, and access_token.
driveInfo() {
    local FOLDER_ID
    FOLDER_ID="$1"
    local FETCH
    FETCH="$2"
    local ACCESS_TOKEN
    ACCESS_TOKEN="$3"
    local SEARCH_RESPONSE
    SEARCH_RESPONSE="$(curl \
        --silent \
        -XGET \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "https://www.googleapis.com/drive/v3/files/""$FOLDER_ID""?fields=""$FETCH""")"
    FETCHED_DATA="$(echo "$SEARCH_RESPONSE" | jsonValue "$FETCH" 1)"
    echo "$FETCHED_DATA"
}

# Method to create directory in google drive.
# Requirements: Foldername, Root folder ID ( the folder in which the new folder will be created ) and access_token.
# First check if a folder exist in given parent directory, if not the case then make the folder.
# Atlast print folder ID ( existing or new one ).
createDirectory() {
    local DIRNAME
    DIRNAME="$1"
    local ROOTDIR
    ROOTDIR="$2"
    local ACCESS_TOKEN
    ACCESS_TOKEN="$3"
    local FOLDER_ID
    FOLDER_ID=""
    local QUERY
    QUERY="$(urlEncode "mimeType='application/vnd.google-apps.folder' and name='$DIRNAME' and trashed=false and '$ROOTDIR' in parents")"

    local SEARCH_RESPONSE
    SEARCH_RESPONSE="$(curl \
        --silent \
        -XGET \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "https://www.googleapis.com/drive/v3/files?q=${QUERY}&fields=files(id)")"
    local FOLDER_ID
    FOLDER_ID="$(echo "$SEARCH_RESPONSE" | jsonValue id 1)"
    if [ -z "$FOLDER_ID" ]; then
        local CREATE_FOLDER_POST_DATA
        CREATE_FOLDER_POST_DATA="{\"mimeType\": \"application/vnd.google-apps.folder\",\"name\": \"$DIRNAME\",\"parents\": [\"$ROOTDIR\"]}"
        local CREATE_FOLDER_RESPONSE
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
uploadFile() {
    local INPUT
    INPUT="$1"
    local FOLDER_ID
    FOLDER_ID="$2"
    local ACCESS_TOKEN
    ACCESS_TOKEN="$3"
    local SLUG
    SLUG="$(basename "$INPUT")"
    local INPUTNAME
    INPUTNAME="${SLUG%.*}"
    local EXTENSION
    EXTENSION="${SLUG##*.}"
    local INPUTSIZE
    INPUTSIZE="$(stat -c%s "$INPUT")"
    local READABLE_SIZE
    READABLE_SIZE="$(du -sh "$INPUT" | awk '{print $1;}')"
    [ -z "$PARALLEL" ] && printCenterJustify "[ ""$(basename "$INPUT")"" | ""$READABLE_SIZE"" ]" "="

    if [[ $INPUTNAME == "$EXTENSION" ]]; then
        if command -v mimetype > /dev/null 2>&1; then
            local MIME_TYPE
            MIME_TYPE="$(mimetype --output-format %m "$INPUT")"
        elif command -v file > /dev/null 2>&1; then
            local MIME_TYPE
            MIME_TYPE="$(file --brief --mime-type "$INPUT")"
        else
            echo -e "\nError: file or mimetype command not found."
            exit 1
        fi
    fi

    # JSON post data to specify the file name and folder under while the file to be created
    local POSTDATA
    POSTDATA="{\"mimeType\": \"$MIME_TYPE\",\"name\": \"$SLUG\",\"parents\": [\"$FOLDER_ID\"]}"

    # Curl command to initiate resumable upload session and grab the location URL
    [ -z "$PARALLEL" ] && printCenter "[ Generating upload link... ]" "="
    local UPLOADLINK
    UPLOADLINK="$(curl \
        --silent \
        -X POST \
        -H "Host: www.googleapis.com" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json; charset=UTF-8" \
        -H "X-Upload-Content-Type: $MIME_TYPE" \
        -H "X-Upload-Content-Length: $INPUTSIZE" \
        -d "$POSTDATA" \
        "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true&supportsTeamDrives=true" \
        --dump-header - | sed -ne s/"Location: "//pi | tr -d '\r\n')"

    if [ -n "$UPLOADLINK" ]; then
        # Curl command to push the file to google drive.
        # If the file size is large then the content can be split to chunks and uploaded.
        # In that case content range needs to be specified.
        [ -z "$PARALLEL" ] && clearLine 1 && printCenter "[ Uploading... ]" "="
        if [ -n "$CURL_ARGS" ]; then
            local UPLOAD_BODY
            UPLOAD_BODY="$(curl \
                -X PUT \
                -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                -H "Content-Type: $MIME_TYPE" \
                -H "Content-Length: $INPUTSIZE" \
                -H "Slug: $SLUG" \
                -T "$INPUT" \
                -o- \
                --url "$UPLOADLINK" \
                "$CURL_ARGS")"
        else
            local UPLOAD_BODY
            UPLOAD_BODY="$(curl \
                -X PUT \
                -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                -H "Content-Type: $MIME_TYPE" \
                -H "Content-Length: $INPUTSIZE" \
                -H "Slug: $SLUG" \
                -T "$INPUT" \
                -o- \
                --url "$UPLOADLINK")"
        fi

        FILE_LINK="$(echo "$UPLOAD_BODY" | jsonValue id | sed 's|^|https://drive.google.com/open?id=|')"
        # Log to the filename provided with -i/--save-id flag.
        if [ -n "$LOG_FILE_ID" ]; then
            if ! [ -d "$LOG_FILE_ID" ]; then
                if [ -n "$UPLOAD_BODY" ]; then
                    # shellcheck disable=SC2129
                    # https://github.com/koalaman/shellcheck/issues/1202#issuecomment-608239163
                    echo "$FILE_LINK" >> "$LOG_FILE_ID"
                    echo "$UPLOAD_BODY" | jsonValue name | sed "s/^/Name\: /" >> "$LOG_FILE_ID"
                    echo "$UPLOAD_BODY" | jsonValue id | sed "s/^/ID\: /" >> "$LOG_FILE_ID"
                    echo "$UPLOAD_BODY" | jsonValue mimeType | sed "s/^/Type\: /" >> "$LOG_FILE_ID"
                    printf '\n' >> "$LOG_FILE_ID"
                fi
            fi
        fi

        if [ -n "$VERBOSE_PROGRESS" ]; then
            printCenterJustify "[ $SLUG | $READABLE_SIZE | Uploaded ]" "="
        else
            if [ -z "$PARALLEL" ]; then
                clearLine 1
                clearLine 1
                clearLine 1
            fi
            printCenterJustify "[ $SLUG | $READABLE_SIZE | Uploaded ]" "="
        fi
    else
        printCenter "[ Upload link generation ERROR, $SLUG not uploaded. ]" "="
        echo -e "\n\n"
        UPLOAD_STATUS=ERROR
        export UPLOAD_STATUS
    fi
}

printCenter "[ Checking credentials... ]" "="
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
            echo
            printCenter "No code provided, run the script and try again" "="
            exit 0
        fi
    fi
fi

# Method to regenerate access_token.
# Make a request on https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$ACCESS_TOKEN url and check if the given token is valid, if not generate one.
# Requirements: Refresh Token
if [ -z "$ACCESS_TOKEN" ]; then
    RESPONSE="$(curl -s --request POST --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token" https://accounts.google.com/o/oauth2/token)"
    ACCESS_TOKEN="$(echo "$RESPONSE" | jsonValue access_token)"
elif curl -s "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$ACCESS_TOKEN" | jsonValue ERROR > /dev/null 2>&1; then
    RESPONSE="$(curl -s --request POST --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token" https://accounts.google.com/o/oauth2/token)"
    ACCESS_TOKEN="$(echo "$RESPONSE" | jsonValue access_token)"
fi

clearLine 1
clearLine 1
printCenter "[ Required credentials available ]" "="
printCenter "[ Checking root dir and workspace folder.. ]" "="
# Setup root directory where all file/folders will be uploaded.
if [ -n "$ROOTDIR" ]; then
    ROOT_FOLDER="$(echo "$ROOTDIR" | tr -d ' ' | tr -d '[:blank:]' | tr -d '[:space:]')"
    if [ -n "$ROOT_FOLDER" ]; then
        ROOT_FOLDER="$(driveInfo "$(extractID "$ROOT_FOLDER")" "id" "$ACCESS_TOKEN")"
        if [ -n "$ROOT_FOLDER" ]; then
            ROOT_FOLDER="$ROOT_FOLDER"
            echo "ROOT_FOLDER=$ROOT_FOLDER" >> "$HOME"/.googledrive.conf
        else
            printCenter "[ Given root folder ID/URL invalid. ]" "="
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
            printCenter "[ Given root folder ID/URL invalid. ]" "="
            exit 1
        fi
    else
        ROOT_FOLDER="root"
        echo "ROOT_FOLDER=$ROOT_FOLDER" >> "$HOME"/.googledrive.conf
    fi
fi

clearLine 1
clearLine 1
printCenter "[ Root dir properly configured ]" "="
# Check to find whether the folder exists in google drive. If not then the folder is created in google drive under the configured root folder.
if [ -z "$FOLDERNAME" ]; then
    ROOT_FOLDER_ID=$ROOT_FOLDER
else
    ROOT_FOLDER_ID="$(createDirectory "$FOLDERNAME" "$ROOT_FOLDER" "$ACCESS_TOKEN")"
fi
ROOT_FOLDER_NAME="$(driveInfo """$ROOT_FOLDER_ID""" name """$ACCESS_TOKEN""")"
clearLine 1
printCenter "[ Workspace Folder: ""$ROOT_FOLDER_NAME"" | ""$ROOT_FOLDER_ID"" ]" "="
START=$(date +"%s")

# To cleanup the TEMP files.
trap '[ -f "$STRING"DIRIDS ] && rm "$STRING"DIRIDS
      [ -f "$STRING"DIRNAMES ] && rm "$STRING"DIRNAMES
      [ -f "$STRING"SUCCESS ] && rm "$STRING"SUCCESS
[ -f "$STRING"ERROR ] && rm "$STRING"ERROR' EXIT

# Check if the argument is a file or a directory.
# In case of file, just upload it.
# In case of folder, do a recursive upload in the same hierarchical manner present.
if [ -n "$INPUT" ]; then
    if [ -f "$INPUT" ]; then
        printCenter "[ Given Input: FILE ]" "="
        echo
        uploadFile "$INPUT" "$ROOT_FOLDER_ID" "$ACCESS_TOKEN"
        printCenter "[ DriveLink ]" "="
        printCenter "$(echo -e "\xe2\x86\x93 \xe2\x86\x93 \xe2\x86\x93")"
        printCenter "$FILE_LINK"
        echo
    elif [ -d "$INPUT" ]; then
        FOLDER_NAME="$(basename "$INPUT")"
        printCenter "[ Given Input: FOLDER ]" "="
        echo
        printCenter "[ Folder: $FOLDER_NAME ]" "="
        NEXTROOTDIRID="$ROOT_FOLDER_ID"

        if [ -n "$SKIP_SUBDIRS" ]; then
            printCenter "[ Indexing files recursively... ]" "="
            FILENAMES="$(find "$INPUT" -type f)"
            NO_OF_FILES="$(wc -l <<< "$FILENAMES")"
            clearLine 1
            clearLine 1
            printCenterJustify "[ Folder: $FOLDER_NAME | ""$NO_OF_FILES"" File(s) ]" "="
            echo

            ID="$(createDirectory "$INPUT" "$NEXTROOTDIRID" "$ACCESS_TOKEN")"
            echo "$ID" >> "$STRING"DIRIDS
            if [ -n "$PARALLEL" ]; then

                export ID
                export CURL_ARGS="-s"
                export PARALLEL
                export ACCESS_TOKEN
                export STRING
                export -f uploadFile
                export -f printCenter
                export -f printCenterJustify
                export -f clearLine
                export -f jsonValue

                # shellcheck disable=SC2016
                echo "$FILENAMES" | xargs -n1 -P"$NO_OF_PARALLEL_JOBS" -i bash -c '
            uploadFile "{}" "$ID" "$ACCESS_TOKEN"
            if [ "$UPLOAD_STATUS" = ERROR ]; then
                echo 1 >> "$STRING"ERROR
                else
                echo 1 >> "$STRING"SUCCESS
                fi
                '
                [ -f "$STRING"SUCCESS ] && SUCESS_STATUS="$(wc -l < "$STRING"SUCCESS)"
                [ -f "$STRING"ERROR ] && ERROR_STATUS="$(wc -l < "$STRING"ERROR)"
                if [ -z "$VERBOSE" ] && [ -z "$VERBOSE_PROGRESS" ]; then
                    echo -e "\n\n"
                else
                    echo
                fi
            else
                if [ -z "$VERBOSE" ] && [ -z "$VERBOSE_PROGRESS" ]; then
                    echo
                fi

                while IFS= read -r -u 4 file; do
                    DIRTOUPLOAD="$ID"
                    uploadFile "$file" "$DIRTOUPLOAD" "$ACCESS_TOKEN"
                    [ "$UPLOAD_STATUS" = ERROR ] && ERROR+="\n1" || SUCESS+="\n1"
                    SUCESS_STATUS="$(echo -e "$SUCESS" | sed 1d | wc -l)"
                    ERROR_STATUS="$(echo -e "$ERROR" | sed 1d | wc -l)"
                    if [ "$VERBOSE" = true ] || [ "$VERBOSE_PROGRESS" = true ]; then
                        printCenter "[ Status: ""$SUCESS_STATUS"" UPLOADED | ""$ERROR_STATUS"" FAILED ]" "="
                        echo
                    else
                        clearLine 1
                        clearLine 1
                        printCenter "[ Status: ""$SUCESS_STATUS"" UPLOADED | ""$ERROR_STATUS"" FAILED ]" "="
                    fi
                done 4<<< "$FILENAMES"
            fi
        else
            # Do not create empty folders during a recursive upload.
            # The use of find in this section is important.
            # If below command is used, it lists the folder in stair structure,
            # which we later assume while creating sub folders( if applicable ) and uploading files.
            find "$INPUT" -type d -not -empty | sed "s|$INPUT|$DIR/$INPUT|" > "$STRING"DIRNAMES
            NO_OF_SUB_FOLDERS="$(sed '1d' "$STRING"DIRNAMES | wc -l)"
            # Create a loop and make folders according to list made above.
            if [ -n "$NO_OF_SUB_FOLDERS" ]; then
                printCenter "[ ""$NO_OF_SUB_FOLDERS"" Sub-folders found ]" "="
                printCenter "[ Creating sub-folders...]" "="
                echo
            fi

            while IFS= read -r -u 4 dir; do
                NEWDIR="$(basename "$dir")"
                [ -n "$NO_OF_SUB_FOLDERS" ] && printCenterJustify " Name: ""$NEWDIR"" " "=" 1>&2
                ID="$(createDirectory "$NEWDIR" "$NEXTROOTDIRID" "$ACCESS_TOKEN")"
                # Store sub-folder directory IDs and it's path for later use.
                echo "$ID '$dir'"
                NEXTROOTDIRID=$ID
                TEMP+="\n""$NEXTROOTDIRID"""
                status="$(echo -e "$TEMP" | sed '/^$/d' | wc -l)"
                if [ -n "$NO_OF_SUB_FOLDERS" ]; then
                    clearLine 1 1>&2
                    clearLine 1 1>&2
                    printCenter " Status: ""$status"" / ""$NO_OF_SUB_FOLDERS"" " "=" 1>&2
                fi
            done 4< "$STRING"DIRNAMES >> "$STRING"DIRIDS

            if [ -n "$NO_OF_SUB_FOLDERS" ]; then
                clearLine 1
                clearLine 1
                clearLine 1
                printCenter "[ ""$NO_OF_SUB_FOLDERS"" Sub-folders created ]" "="
            fi

            printCenter "[ Indexing files recursively... ]" "="
            FILENAMES="$(find "$INPUT" -type f | sed "s|$INPUT|$DIR/$INPUT|")"
            NO_OF_FILES="$(wc -l <<< "$FILENAMES")"
            if [ -n "$NO_OF_SUB_FOLDERS" ]; then
                clearLine 1
                clearLine 1
                clearLine 1
                printCenterJustify "[ Folder: $FOLDER_NAME | ""$NO_OF_FILES"" File(s) | ""$NO_OF_SUB_FOLDERS"" Sub-folders ]" "="
            else
                clearLine 1
                clearLine 1
                printCenterJustify "[ Folder: $FOLDER_NAME | ""$NO_OF_FILES"" File(s) | 0 Sub-folders ]" "="
            fi
            if [ -n "$VERBOSE" ] || [ -n "$VERBOSE_PROGRESS" ]; then
                echo
            else
                echo -e "\n"
            fi

            # shellcheck disable=SC2001
            # Match the path with sub-folder directory ID and upload accordingly.
            FILES_ROOTDIR="$(while read -r i; do sed "s/\(.*\)\/$(basename "$i")/\1/" <<< "$i"; done <<< "$FILENAMES")"

            while IFS= read -r -u 4 ROOTDIRPATH && IFS= read -r -u 5 file; do
                DIRTOUPLOAD="$(grep "'$ROOTDIRPATH'" "$STRING"DIRIDS | awk '{print $1;}')"
                uploadFile "$file" "$DIRTOUPLOAD" "$ACCESS_TOKEN"
                [ "$UPLOAD_STATUS" = ERROR ] && ERROR+="\n1" || SUCESS+="\n1"
                SUCESS_STATUS="$(echo -e "$SUCESS" | sed 1d | wc -l)"
                ERROR_STATUS="$(echo -e "$ERROR" | sed 1d | wc -l)"
                if [ -n "$VERBOSE" ] || [ -n "$VERBOSE_PROGRESS" ]; then
                    printCenter "[ Status: ""$SUCESS_STATUS"" UPLOADED | ""$ERROR_STATUS"" FAILED ]" "="
                    echo
                else
                    clearLine 1
                    clearLine 1
                    printCenter "[ Status: ""$SUCESS_STATUS"" UPLOADED | ""$ERROR_STATUS"" FAILED ]" "="
                fi
            done 4<<< "$FILES_ROOTDIR" 5<<< "$FILENAMES"
        fi

        if [ -z "$VERBOSE" ] && [ -z "$VERBOSE_PROGRESS" ]; then
            clearLine 1
            clearLine 1
        fi
        if ! [ "$SUCESS_STATUS" = 0 ]; then
            printCenter "[ FolderLink ]" "="
            printCenter "$(echo -e "\xe2\x86\x93 \xe2\x86\x93 \xe2\x86\x93")"
            printCenter "$(head -n1 "$STRING"DIRIDS | awk '{print $1;}' | sed -e 's|^|https://drive.google.com/open?id=|')"
        fi
        echo
        printCenter "[ Total Files Uploaded: ""$SUCESS_STATUS"" ]" "="
        [ -n "$ERROR_STATUS" ] && [ "$ERROR_STATUS" -gt 0 ] && printCenter "[ Total Files Failed: ""$ERROR_STATUS"" ]" "="
    fi
fi

END="$(date +"%s")"
DIFF="$((END - START))"
printCenter "[ Time Elapsed: ""$((DIFF / 60))"" minute(s) and ""$((DIFF % 60))"" seconds ]" "="

[ -n "$DEBUG" ] && set +xe
