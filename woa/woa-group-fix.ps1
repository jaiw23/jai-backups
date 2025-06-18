
cls
$chg_ref = $args[0]
$tk_owner = $args[1]
$curr_dir = Get-Location
if(-Not(Test-Path  "$curr_dir\woa-groupdirs.txt"))
{
Write-Output ("woa-groupdirs.txt not found in $path. Please Create a .txt file named ""woa-groupdirs.txt"" in $path and re run the scriprt")
Exit-PSSession
}
if(-Not(Test-Path  "$curr_dir\logs\"))
{
new-item -type directory -path $curr_dir\logs | Out-Null
}
if(-Not(Test-Path  "$curr_dir\archive\"))
{
new-item -type directory -path $curr_dir\archive | Out-Null
}
 
$date = (Get-Date -Format 'dd-mm-yyyy_hh-mm-ss')
 
$file = "$curr_dir\woa-groupdirs.txt"
$dest_file = "$curr_dir\archive\$chg_ref-$date-woa-groupdirs.txt"
 
Start-Transcript -Path $curr_dir\logs\$chg_ref-$date.txt | Out-Null
 
$content = Get-Content $file | where {$_ -ne ""}
$error_count = 0
 
foreach ($path in $content){
try{
$obj = @()
$diffobj = @()
$flag = $false
Write-Output "`n++++++++++++++++++++++++++++++++++++++++ WOA automated fix initiating for $path +++++++++++++++++++++++++++++++++++++++++++++*"
Write-Output "Share: $path `n"
Write-Output "ACL on parent before automation: "
Write-Output $(Get-Acl $path | fl | out-string)
 
 
icacls $path /inheritancelevel:d
 
$Acl = Get-Acl $path
 
if($Acl.Access.IdentityReference -contains "NT Authority\Authenticated Users"){ Write-Output "Authenticated Users Found. Removing it"
if($ACL.Access | where {$_.IdentityReference -eq "NT Authority\Authenticated Users" -and $_.IsInherited -eq "True"}){
}
$ACL.Access | where {$_.IdentityReference -eq "NT Authority\Authenticated Users"} | %{$ACL.RemoveAccessRule($_)}
$flag = $true
}
 
if($Acl.Access.IdentityReference -contains "Everyone"){ Write-Output "Everyone Found. Removing it"
if($ACL.Access | where {$_.IdentityReference -eq "Everyone" -and $_.IsInherited -eq "True"}){
}
$Acl.Access | where {$_.IdentityReference -eq "Everyone"} | %{$Acl.RemoveAccessRule($_)}
$flag = $true
}
 
if($Acl.Access.IdentityReference -contains "Builtin\Users"){ Write-Output "Builtin\Users Found. Removing it"
if($ACL.Access | where {$_.IdentityReference -eq "Builtin\Users" -and $_.IsInherited -eq "True"}){
}
$Acl.Access | where {$_.IdentityReference -eq "Builtin\Users"} | %{$Acl.RemoveAccessRule($_)}
$flag = $true
}
 
if($Acl.Access.IdentityReference -contains "DBG\Domain Users"){ Write-Output "DBG\Domain Users Found. Removing it"
if($ACL.Access | where {$_.IdentityReference -eq "DBG\Domain Users" -and $_.IsInherited -eq "True"}){
}
$Acl.Access | where {$_.IdentityReference -eq "DBG\Domain Users"} | %{$Acl.RemoveAccessRule($_)}
$flag = $true
}
 
if(-not $flag) {Write-Output "Open Access Not Found..."}
 
if($flag){
 
Get-ChildItem -Path $path -Recurse -Depth 0 `
    | Where-Object { $_.PSIsContainer} `
    | ForEach-Object {
        $currentACL = Get-Acl $_.FullName
        $parentACL = Get-Acl ($_.FullName | Split-Path -Parent)
        if($($currentACL.Access.IdentityReference | Out-String) -ne $($parentACL.Access.IdentityReference | Out-String )){
            #write-host -ForegroundColor Yellow "$($currentACL.Path | Convert-Path)`n"
            #$currentACL.AccessToString
            $obj_entry = $currentACL.Access.IdentityReference.Value  #| Export-Csv -Delimiter ";" c:\ACL1.csv -Append
            $obj += $obj_entry
        }
     }
$obj = $obj | Select-Object -Unique | Where-Object {($_ -notlike "S-*") -and ($_ -notlike "NT*") -and ($_ -notlike "Everyone") -and ($_ -notlike "NT Authority\Authenticated Users") -and ($_ -notlike "Builtin\Users") -and ($_ -notlike "DBG\Domain Users")}
$parent = (Get-Acl $path).Access.IdentityReference.Value
#Compare-Object -ReferenceObject $parent -DifferenceObject $obj
$final = $obj | where {$parent -notcontains $_}
 
if($tk_owner -eq "true"){
Write-Output "Taking Folder Ownership"
takeown /a /r /d Y /f $path
}
 
 
if($Acl.Access.IdentityReference -notcontains "BUILTIN\Administrators"){
Write-Output "Adding BUILTIN\Administrators"
$Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators",
            "FullControl",      # [System.Security.AccessControl.FileSystemRights]
            "ContainerInherit, ObjectInherit", # [System.Security.AccessControl.InheritanceFlags]
            "None",      # [System.Security.AccessControl.PropagationFlags]
            "Allow"      # [System.Security.AccessControl.AccessControlType]
        )))
}
 
if($final.length -ne 0){
Write-Output "Found below ACL in subdirectories"
$final
foreach($final_acl in $final){
Write-Output "Applying $final_acl to $path with ListDirectory permission"
        $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$final_acl",
            "ListDirectory",      # [System.Security.AccessControl.FileSystemRights]
            "None", # [System.Security.AccessControl.InheritanceFlags]
            "None",      # [System.Security.AccessControl.PropagationFlags]
            "Allow"      # [System.Security.AccessControl.AccessControlType]
        )))
        }
}
else{Write-Output "No additional ACLs found in subdirectories"}
}
 
if($flag){
 
        write-output "applying final permissions now"
        $Acl.Access 
        (Get-Item $path).SetAccessControl($Acl)
        write-output "done !!"
        write-output ""
        }
else {Write-Output "No action taken..."}
}
 
catch{
    Write-Output "ERROR: for share : $($path) : $($Error[0])"
    $error_count += 1
}
 
Write-Output "ACL on parent after automation: "
Write-Output $(Get-Acl $path | fl | out-string)
write-output ""
 
Copy-Item -Path $file -Destination $dest_file -Force
 
Write-Output "`n*************************************WOA automated fix completed for $path ********************************************"
 
}
Write-Output "`nAutomation Complete. Total shares processed: $($content.count) . Errors : $error_count"
Stop-Transcript | Out-Null
