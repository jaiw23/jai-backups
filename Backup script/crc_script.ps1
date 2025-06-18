<#########################################################
Copyright (c) 2018 NetApp.  All rights reserved.

Name : crc_script.ps1
Version : v1.0
Author : Jai Waghela

Description : 
- Script will provide CRC error count for all the ethernet ports on NetApp clusters as an Email to the storage administrator. 
- Script requires a text file named "clusters.txt" having all the cluster names or IP address as Input. 
- Please note that clusters.txt should be present in same location where script is present.
- Credentials provided are local to the user, which means any other user will not be able to use the credentials provided by one user.
- In order for other user to run the script, copy the script to different location and delete credential.xml file present inside "cred" folder. It will prompt again for username and password.

Requirements : 
- Password authenticated local user with admin privilage for ONTAPI and CONSOLE application on all the clusters for which information is needed.
- Powershell toolkit to be installed on the host from where script will be executed.

Contact: jai.waghela@netapp.com
##########################################################>

Import-Module DataONTAP 
$index =0
$objects = @()
$path = Get-Location
if(Test-Path "$path\output")
{
Remove-Item $path\output\* -Recurse -Force
}
$check = 0
$check1=0
if(-Not(Test-Path  "$path\output"))
{
new-item -type directory -path $path\output | Out-Null
}
if(-Not(Test-Path  "$path\temp"))
{
new-item -type directory -path $path\temp | Out-Null
}
if(-Not(Test-Path  "$path\cred"))
{
new-item -type directory -path $path\cred | Out-Null
}
if(-Not(Test-Path  "$path\cred\credential.xml"))
{
Get-Credential | Export-Clixml "$path\cred\credential.xml"
}
if(-Not(Test-Path  "$path\clusters.txt"))
{
Write-Host ""
Write-Warning -Message ("Cluster list not found in $path. Please Create a .txt file named ""clusters.txt"" in $path and re run the scriprt")
Exit-PSSession
}
$clusters= Get-Content "$path\clusters.txt"
$objects = @()
$faulty = @()
foreach($cluster in $clusters)
{
Connect-NcController -Name $cluster -HTTPS -Credential (Import-Clixml $path\cred\credential.xml) | Out-Null
Write-Host ""
Write-Host ("Enumerating Cluster ""$cluster""") -ForegroundColor Gray
Write-Host ""
$nodes = Get-NcNode 
$ports = Get-NcNetPort 
ForEach($node In $nodes)
{ 
$ports = Get-NcNetPort -Node $node
ForEach($port In $ports)
{ 
$command = @("system", "node", "run", "-node", $node.Node, "-command", "ifstat", $port.Port) 
$api = $("<system-cli><args><arg>" + ($command -join "</arg><arg>") + "</arg></args></system-cli>")
Do{
$output = Invoke-NcSystemApi -Request $api -ErrorAction Stop 
}Until($output.results.'cli-output'-ne '')
Write-Host "" 
Write-Host $("Scanning Port") -ForegroundColor Yellow
Write-Host "" 
Write-Host $("Port """ + $port.Port + """ scanned on Node """ + $node.Node + """") -ForegroundColor Cyan 
Write-Host "" 
If($output.results."cli-result-value" -eq 1)
{ 

try {

  $f=$output.results.'cli-output'.Trim() | Select-String -Pattern 'crc','interface' > $path\output\$node"_"$port.txt
  #$output.results.'cli-output'
  $b = Get-Content $path\output\$node"_"$port.txt | Select-String -Pattern 'crc','interface'  
  $portpp = (($b[0].Line | Select-String -Pattern 'e*').Line.Trim().Split(' '))[3]
  $c = $b[1].Line.Replace(' ','').Split('|').Split(':')
$portpp = (($b[0] | Select-String -Pattern 'e*').Line.Trim().Split(' '))[3]
for($index=0;$index -lt $c.Count;$index++)
{
if($c[$index] -like "CRC*")
{
$index
$type= $c[$index]
$val = $c[$index +1]
}
}
$objects += New-Object -Type PSObject -Prop @{'Cluster'=$cluster;'Node'=$node;'Port'=$port;'Error'=$type;'Count'=$val;}
}
catch{
  Write-Warning -Message $($_.Exception.Message)
 }
} 
} 
}
}
for($q=0;$q -lt $objects.Count;$q++)
{
if($objects[$q].count -gt 0){$faulty += $objects[$q]}
}
if($faulty.Count -eq "0")
{
$errcount = "0"
}
else {$}
$Header = @"
<style>
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #6495ED;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
</style>
"@
Write-Host $("Port Details") -ForegroundColor Yellow
$objects | Format-Table
Write-Host ""
Write-Host ("Ports having CRC errors count greater than 100: $($faulty.Count)") -ForegroundColor Yellow
Write-Host ""
$faulty | Format-Table
$faulty | ConvertTo-Html -Head $Header -Title "CRC Error Report" -Body "<h2>CRC Error Report</h2>`n<h5>Updated: on $(Get-Date)</h5>`n<h3>Ports with error : $($faulty.Count)</h3>"|Out-File $path\temp\port.htm
$objects | ConvertTo-Html -Head $Header -Title "CRC Error Report" -Body "<h3>Complete Port List</h3>"|Out-File -Append $path\temp\port.htm
$contents = Get-Content $path\temp\port.htm
$contents > $path\temp\content.txt
$faulty | Export-Csv $path\temp\faulty.csv
$objects | Export-Csv  $path\temp\all_ports.csv
#Invoke-Item $path\temp\port.htm

############send mail#######################
<# 
$fromaddress = "jai.waghela@netapp.com" 
$toaddress = "jai.waghela@netapp.com" 
$body = $ports 
$attachment = "$path\temp\faulty.csv"
$attachment1= "$path\temp\all_ports.csv"
$Subject = "CRC report - $(Get-Date)" 
$SMTPServer = "10.199.100.30"
Send-MailMessage -From $fromaddress -to $toaddress  -Subject $Subject `
-Body $ports -BodyAsHtml -SmtpServer $SMTPServer -Attachments $attachment,$attachment1
#>
####################