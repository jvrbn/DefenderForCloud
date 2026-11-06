# DefenderForCloud

## Storage
### Get a container SAS URL

[GetStorageContainerUrl.sh](Storage/GetStorageContainerUrl.sh) uses your signed-in
Azure CLI account to generate an HTTPS-only container URL with Read/List (`rl`)
permissions. It expires in one hour and does not require storage account keys.
Requires Azure CLI and Python 3.

```sh
az login
AZURE_STORAGE_CONTAINER_URL="$(sh Storage/GetStorageContainerUrl.sh ACCOUNT CONTAINER)" &&
    export AZURE_STORAGE_CONTAINER_URL &&
    sh Storage/DownloadFilesBlob.sh
```

Replace `ACCOUNT` and `CONTAINER` with the storage account and container names.
To print just the URL, run `sh Storage/GetStorageContainerUrl.sh ACCOUNT CONTAINER`.
The script uses the active Azure cloud's storage endpoint suffix.

Your account needs blob Read/List access on the container and
`Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action`
at storage account, resource group, or subscription scope. For example, use
Storage Blob Data Reader on the container plus Storage Blob Delegator on the
storage account; Storage Blob Data Contributor at storage account scope also
covers these permissions. Container access alone may not allow SAS generation.
Storage firewall/private endpoint restrictions still apply.

Treat the generated SAS URL as a secret: do not commit, share, or log it.

### Abnormal file downloaded
[DownloadFilesBlob.sh](Storage/DownloadFilesBlob.sh) lists and downloads blobs
using `AZURE_STORAGE_CONTAINER_URL`. Downloads go to `./downloads` by default;
set `AZURE_STORAGE_DOWNLOAD_DIR` to override the destination.