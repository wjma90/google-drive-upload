**Google drive upload**
-------------------
Google drive upload is a Bash scripts based on v2 google APIs to upload files/directories into google drive. This is a minimalistic shell script which utilizes google OAuth2.0 device flow to generate access tokens to authorize application to upload files to your google drive.

Further usage documentation can be found at my blog page [Labbots.com](https://labbots.com/google-drive-upload-bash-script/ "Labbots.com").

**Dependencies**
----------------
This script does not have very many dependencies. Most of the dependencies are available by default in most linux platforms. This script requires the following packages

 - Curl
 - sed (Stream editor)
 - find command
 - awk
 - getopt

**Usage**
-----
When the script is executed for the first time. It asks for few configuration variables interactively to connect with google APIs. The script requires Client Id and Client secret to access the APIs which can be generated at [google console]. 
Script also asks for root folder to be set to which the script uploads documents by default. The default folder will be the root of your google drive. If you want to upload documents to any specific directory by default then provide the google folder id of that folder which root folder id is requested. The google folder id can be found from the URL of the google drive folder.

For example 
>https://drive.google.com/drive/folders/8ZzWiO_pMAtBrLpARBZJNV09TVmM 

In the above URL. The folder id is ***8ZzWiO_pMAtBrLpARBZJNV09TVmM***

The default configurations of the script are store under **$HOME/.googledrive.conf**

The script can be used in the following way

    ./upload.sh <filepath> <foldername>
Above command will create a folder under the pre-configured root directory and upload the specified file under the folder name. If the folder already exists then the file is uploaded under the folder.

Other Options available are

    -C | --create-dir <foldername> - option to create directory. Will provide folder id.
	-r | --root-dir <google_folderid> - google folder id to which the file/directory to upload.
	-v | --verbose - Display detailed message.
	-h | --help - Display usage instructions.
	-z | --config - Override default config file with custom config file.

To create a folder:

    ./upload.sh -C <foldername> -r <optional-root-dir-id> 
This will give the folder id of the newly created folder which can be used to upload files to specific directory in google drive.

To Upload file to specific google folder

    ./upload.sh -v -r <google-folder-id> <file/directory-path>

The script also allows to upload directories. If directory path is provided as argument to the script then the script recursively uploads all the files in the folder to google drive.


**Inspired By**
----
* [github-bashutils] - soulseekah/bash-utils
* [deanet-gist] - Uploading File into Google Drive

**License**
----
MIT


[github-bashutils]: <https://github.com/soulseekah/bash-utils>
[deanet-gist]:<https://gist.github.com/deanet/3427090>
[google console]:<https://console.developers.google.com>
