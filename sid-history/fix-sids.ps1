
# Define script parameters
 
param(
 
    [string]$csvFilePath
 
)
 
# Check if the CSV file path is provided
 
if (-not $csvFilePath) {
 
    Write-Host "Please provide the CSV file path as a command-line argument."
 
    exit
 
}
 
# Check if the CSV file exists
 
if (-not (Test-Path $csvFilePath)) {
 
    Write-Host "The specified CSV file does not exist."
 
    exit
 
}


# Import the CSV file
Write-Host "Importing CSV"
 
$csvData = Import-Csv -Path $csvFilePath


# Define the log file path
 
$logFilePath = "NTFS_SID_History_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
 
# Function to log messages
 
function Log-Message {
 
    param (
 
        [string]$message
 
    )
 
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
 
    $logMessage = "$timestamp - $message"
 
    Write-Host $logMessage
 
    Add-Content -Path $logFilePath -Value $logMessage
 
}
 
# Iterate through each row in the CSV file
 
foreach ($row in $csvData) {
 
    $path = $row.Path
 
    $displayName = $row.'Display Name'
 
    $basicPermissions = $row.'Basic Permissions'
 
    $scope = $row.Scope
 
    Write-Host $path
 
    # Convert basic permissions to FileSystemRights
 
    switch ($basicPermissions) {
 
        "Modify" { $fileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify }
 
        "Read" { $fileSystemRights = [System.Security.AccessControl.FileSystemRights]::Read }
 
        #"Write" { $fileSystemRights = [System.Security.AccessControl.FileSystemRights]::Write }
 
        # Add more cases as needed
 
        default { $fileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify }
 
    }



    # Convert scope to InheritanceFlags and PropagationFlags
 
    switch ($scope) {
 
        "This folder, subfolders, and files" {
 
            $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit, [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
 
            $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
 
        }
 
        "This folder and subfolders" {
 
            $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
 
            $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
 
        }
 
        "This folder only" {
 
            $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
 
            $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
 
        }
 
        # Add more cases as needed
 
        default {
 
            $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit, [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
 
            $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
 
        }
 
    }



    try {
 
        # Get the current ACL
 
        $acl = Get-Acl -Path $path



        # Create a new FileSystemAccessRule
 
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($displayName, $fileSystemRights, $inheritanceFlags, $propagationFlags, [System.Security.AccessControl.AccessControlType]::Allow)



        # Add the access rule to the ACL
 
        $acl.SetAccessRule($accessRule)



        # Apply the updated ACL to the path
 
        Set-Acl -Path $path -AclObject $acl



        # Log success message
 
        Log-Message "Successfully applied $basicPermissions permission for $displayName on $path with scope $scope."
 
    }
 
    catch {
 
        # Log error message
 
        Log-Message "Failed to apply $basicPermissions permission for $displayName on $path with scope $scope. Error: $_"
 
    }
 
}



# Log completion message
 
Log-Message "NTFS permissions update completed."
 
