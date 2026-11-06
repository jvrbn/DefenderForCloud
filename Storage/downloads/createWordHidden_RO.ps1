Import-Module PSWriteWord

# Define file path
$FilePath = "C:\BRDS_IT\SecretDocument.docx"

# 1. Create the Word Document
$WordDocument = New-WordDocument -FilePath $FilePath

# Add some content
Add-WordText -WordDocument $WordDocument -Text "This document is hidden and read-only." -FontSize 12

# Save the document
Save-WordDocument -WordDocument $WordDocument

# 2. Set File Attributes to Hidden and Read-Only
# We use Set-ItemProperty to modify the file system attributes
Set-ItemProperty -Path $FilePath -Name "Attributes" -Value ([System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::ReadOnly)

Write-Host "Document created at $FilePath with Hidden and Read-Only attributes." -ForegroundColor Green   