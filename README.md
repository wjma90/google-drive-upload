# Google drive upload

Google drive upload is a Bash script based on v3 google APIs to upload files/directories into google drive. This is a minimalistic shell script which utilizes google OAuth2.0 device flow to generate access tokens to authorize application to upload files to your google drive.

Further usage documentation can be found at my blog page [Labbots.com](https://labbots.com/google-drive-upload-bash-script/ "Labbots.com").

## Dependencies

This script does not have very many dependencies. Most of the dependencies are available by default in most linux platforms. This script requires the following packages

- Curl
- sed (Stream editor)
- find command
- awk
- getopts ( bash builtin )
- xargs

## Features

- No dependencies at all.
- Upload files and folders.
- Upload files in parallel.
- Upload sub-folders and content inside it hierarchically.
- Config file support ( easy to use script on multiple machines ).
- Uses latest gdrive v3 api.
- Share files after uploading.
- Pretty Logging.

## Usage

When the script is executed for the first time. It asks for few configuration variables interactively to connect with google APIs. The script requires Client ID and Client secret to access the APIs which can be generated at [google console].
Script also asks for root folder to be set to which the script uploads documents by default. The default folder will be the root of your google drive. If you want to upload documents to any specific directory by default then provide the google folder ID or URL of that folder when root folder ID/URL is requested.

For example
`https://drive.google.com/drive/folders/8ZzWiO_pMAtBrLpARBZJNV09TVmM`

In the above URL. The folder id is ***8ZzWiO_pMAtBrLpARBZJNV09TVmM***

Note: You can input either URL or ID.

The default configurations of the script are store under **$HOME/.googledrive.conf**

The script can be used in the following way

    ./upload.sh <filepath/folderpath> <foldername>
Above command will create a folder under the pre-configured root directory and upload the specified file under the folder name. If the folder already exists then the file is uploaded under the folder.

Other Options available are

    -C | --create-dir <foldername> - option to create directory. Will provide folder id.
    -r | --root-dir <google_folderid> - google folder id to which the file/directory to upload.
    -s | --skip-subdirs - Skip creation of sub folders and upload all files inside the INPUT folder/sub-folders in the INPUT folder, use this along with -p/--parallel option to speed up the uploads.
    -p | --parallel <no_of_files_to_parallely_upload> - Upload multiple files in parallel, only works along with --skip-subdirs/-s option, Max value = 10, low value are recommended.
    -S | --share - Share the uploaded input file/folder, grant reader permission to the everyone with the link.
    -v | --verbose - Display detailed message.
    -V | --verbose-progress - Display detailed message and detailed upload progress( curl normal progress info ).
    -i | --save-info <file_to_save_info> - Save uploaded files info to the given filename."
    -h | --help - Display usage instructions.
    -z | --config - Override default config file with custom config file.
    -D | --debug - Display script command trace."

To create a folder:

    ./upload.sh -C <foldername> -r <optional-root-dir-id> 
This will give the folder id of the newly created folder which can be used to upload files to specific directory in google drive.

To Upload file to specific google folder

    ./upload.sh -r <google-folder-id> <file/directory-path>

The script also allows to upload directories. If directory path is provided as argument to the script then the script recursively uploads all the sub-folder and files present in the heirarchial way as it is present on the local machine.

## Inspired By

- [github-bashutils] - soulseekah/bash-utils
- [deanet-gist] - Uploading File into Google Drive

## License

MIT

[github-bashutils]: <https://github.com/soulseekah/bash-utils>
[deanet-gist]:<https://gist.github.com/deanet/3427090>
[google console]:<https://console.developers.google.com>
