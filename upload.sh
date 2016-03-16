#!/bin/bash

# Upload a file to Google Drive
# Usage: upload.sh <file> <folder_name>

#!/bin/bashset -e

#TODO
# 1. Create directory option
# 2. Upload entire directory
# 3. Resume failed upload

#Simple validation to check whether the given folder exists
if [ ! -f $1 ]
then
        echo "please provide a file in arg"
        exit -1
fi


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FILE=$1
#Configuration variables
ROOT_FOLDER=""
CLIENT_ID=""
CLIENT_SECRET=""
REFRESH_TOKEN=""
SCOPE=${SCOPE:-"https://docs.google.com/feeds"}

# Method to extract data from json response
function jsonValue() {
KEY=$1
num=$2
awk -F"[,:}][^:\/\/]" '{for(i=1;i<=NF;i++){if($i~/\042'$KEY'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[,]*$//'
}

if [ -e $HOME/.googledrive.conf ]
then
    . $HOME/.googledrive.conf
fi

old_umask=`umask`
umask 0077

if [ -z "$ROOT_FOLDER" ]
then
    read -p "Root Folder ID (Default: root): " ROOT_FOLDER
    if [ -z "$ROOT_FOLDER"] || [ `echo $ROOT_FOLDER | tr [:upper:] [:lower:]` = `echo "root" | tr [:upper:] [:lower:]` ]
    	then
    		ROOT_FOLDER="root"
    		echo "ROOT_FOLDER=$ROOT_FOLDER" >> $HOME/.googledrive.conf
    	else
		    if expr "$ROOT_FOLDER" : '^[A-Za-z0-9_]\{28\}$' > /dev/null
		    then
				echo "ROOT_FOLDER=$ROOT_FOLDER" >> $HOME/.googledrive.conf
			else
				echo "Invalid root folder id"
				exit -1
			fi
		fi
fi

if [ -z "$CLIENT_ID" ]
then
    read -p "Client ID: " CLIENT_ID
    echo "CLIENT_ID=$CLIENT_ID" >> $HOME/.googledrive.conf
fi

if [ -z "$CLIENT_SECRET" ]
then
    read -p "Client Secret: " CLIENT_SECRET
    echo "CLIENT_SECRET=$CLIENT_SECRET" >> $HOME/.googledrive.conf
fi

if [ -z "$REFRESH_TOKEN" ]
then
    RESPONSE=`curl --silent "https://accounts.google.com/o/oauth2/device/code" --data "client_id=$CLIENT_ID&scope=$SCOPE"`
	DEVICE_CODE=`echo "$RESPONSE" | jsonValue "device_code"`
	USER_CODE=`echo "$RESPONSE" | jsonValue "user_code"`
	URL=`echo "$RESPONSE" | jsonValue "verification_url"`

	echo -n "Go to $URL and enter $USER_CODE to grant access to this application. Hit enter when done..."
	read

	RESPONSE=`curl --silent "https://accounts.google.com/o/oauth2/token" --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&code=$DEVICE_CODE&grant_type=http://oauth.net/grant_type/device/1.0"`

	ACCESS_TOKEN=`echo "$RESPONSE" | jsonValue access_token`
	REFRESH_TOKEN=`echo "$RESPONSE" | jsonValue refresh_token`

    echo "REFRESH_TOKEN=$REFRESH_TOKEN" >> $HOME/.googledrive.conf
fi

if [ -z "$ACCESS_TOKEN" ]
	then
	# Access token generation
	RESPONSE=`curl --silent "https://accounts.google.com/o/oauth2/token" --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token"`
	ACCESS_TOKEN=`echo $RESPONSE | jsonValue access_token`
fi
# Check to find whether the folder exists in google drive. If not then the folder is created in google drive under the configured root folder
if [ -z "$2" ] || [ `echo $2 | tr [:upper:] [:lower:]` = `echo "root" | tr [:upper:] [:lower:]` ]
	then
	if [ `echo $2 | tr [:upper:] [:lower:]` = `echo "root" | tr [:upper:] [:lower:]` ]
	then
		ROOT_FOLDER="root"
	fi
    FOLDER_ID=$ROOT_FOLDER
else
        FOLDERNAME="$2"
        QUERY="mimeType='application/vnd.google-apps.folder' and title='$FOLDERNAME'"
        QUERY=$(echo $QUERY | sed -f ${DIR}/url_escape.sed)
		SEARCH_RESPONSE=`/usr/bin/curl \
						--silent \
						-XGET \
						-H "Authorization: Bearer ${ACCESS_TOKEN}" \
						 "https://www.googleapis.com/drive/v2/files/${ROOT_FOLDER}/children?orderBy=title&q=${QUERY}&fields=items%2Fid"`
		FOLDER_ID=`echo $SEARCH_RESPONSE | jsonValue id`
		if [ -z "$FOLDER_ID" ]
		then
			CREATE_FOLDER_POST_DATA="{\"mimeType\": \"application/vnd.google-apps.folder\",\"title\": \"$FOLDERNAME\",\"parents\": [{\"id\": \"$ROOT_FOLDER\"}]}"
			CREATE_FOLDER_RESPONSE=`/usr/bin/curl \
									--silent  \
									-X POST \
									-H "Authorization: Bearer ${ACCESS_TOKEN}" \
									-H "Content-Type: application/json; charset=UTF-8" \
									-d "$CREATE_FOLDER_POST_DATA" \
									"https://www.googleapis.com/drive/v2/files?fields=id" `
			FOLDER_ID=`echo $CREATE_FOLDER_RESPONSE | jsonValue id`
		fi
						 
fi
FOLDER_ID="$(echo $FOLDER_ID | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
BOUNDARY=`cat /dev/urandom | head -c 16 | xxd -ps`
MIME_TYPE=`file --brief --mime-type "$FILE"`
SLUG=`basename "$FILE"`
FILESIZE=$(stat -c%s "$FILE")

# JSON post data to specify the file name and folder under while the file to be created
postData="{\"mimeType\": \"$MIME_TYPE\",\"title\": \"$SLUG\",\"parents\": [{\"id\": \"$FOLDER_ID\"}]}"
postDataSize=$(echo $postData | wc -c)

# Curl command to initiate resumable upload session and grab the location URL
echo "Generating upload link..."
uploadlink=`/usr/bin/curl \
			--silent \
			-X POST \
			-H "Host: www.googleapis.com" \
			-H "Authorization: Bearer ${ACCESS_TOKEN}" \
			-H "Content-Type: application/json; charset=UTF-8" \
			-H "X-Upload-Content-Type: $MIME_TYPE" \
			-H "X-Upload-Content-Length: $FILESIZE" \
			-d "$postData" \
			"https://www.googleapis.com/upload/drive/v2/files?uploadType=resumable" \
			--dump-header - | sed -ne s/"Location: "//p | tr -d '\r\n'`

# Curl command to push the file to google drive.
# If the file size is large then the content can be split to chunks and uploaded.
# In that case content range needs to be specified.
echo "Uploading file to google drive..."
curl \
-X PUT \
-H "Authorization: Bearer ${ACCESS_TOKEN}" \
-H "Content-Type: $MIME_TYPE" \
-H "Content-Length: $FILESIZE" \
-H "Slug: $SLUG" \
--data-binary "@$FILE" \
--output /dev/null \
--progress-bar \
"$uploadlink"
