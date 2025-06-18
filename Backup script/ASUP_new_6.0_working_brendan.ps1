function get_xml($url, $filename, $serial){
$path = Get-Location
if(-Not(Test-Path  "$path\Temp\"))
{new-item -type directory -path $path\Temp | Out-Null} 
$tempdir = "$path\Temp"
	$destination = $tempdir+"\"+$filename
	try{
		Invoke-WebRequest $url -OutFile $destination
		[xml]$xml = Get-Content $destination
		return $xml
	}
	catch{
        if(-Not(Test-Path  "C:\Temp\adhoc"))
        {
        new-item -type directory -path "C:\Temp\adhoc" | Out-Null
        }
		$date = (Get-Date)
		Write "$date - Error: $_ Serial: $serial" >> C:\Temp\adhoc\log.txt
		Write "$date - URL: $url" >>$logfile
	}
}

function get_file($url, $filename){
	$destination = $tempdir+"\"+$filename
	try{
		Invoke-WebRequest $url -OutFile $destination
	}
	catch{

if(-Not(Test-Path  "C:\Temp"))
        {
        new-item -type directory -path "C:\Temp" | Out-Null
        }
		$date = (Get-Date)
		Write "$date - Error: $_ URL: $url" >> C:\Temp\log.txt
	}
}


function run {
$path = Get-Location
if(-Not(Test-Path  "$path\Temp\"))
{new-item -type directory -path $path\Temp | Out-Null} 
$tempdir = "$path\Temp\"
$objects = @()
if(-Not(Test-Path  "$path\filers.txt"))
{
Write-Output ""
Write-Warning -Message ("Filer list not found in $path. Please Create a .txt file named ""filers.txt"" in $path and re run the scriprt")
pause
exit
}
$filers = Get-Content $path\filers.txt |  where {$_ -ne ""}
$date = (Get-Date -Format 'dd-MM-yyyy_hh-mm-ss')
$yesterday = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd')
$today = (Get-Date).ToString('yyyy-MM-dd')
$filename = 'ASUP-adhoc-' + $date
$count = 0
foreach($filer in $filers)
{
$xml = ''
$agendate = ''
$url = "http://restprd.corp.netapp.com/asup-rest-interface/ASUP_DATA/client_id/Fujitsu_capacity/hostname/$filer/asup_subject/*MANAGEMENT*,*WEEKLY*/last/40"
Write-Host "Processing Host : $filer"
		$xml = get_xml $url asupcheck.xml $serial
		$osversion = $xml.xml.results.system.sys_version
        $cluster = $xml.xml.results.system.cluster.cluster_name
        if($cluster.Count -gt '1'){$cluster = $cluster[0]}
        $asuptype = $xml.xml.results.system.asups.asup.asup_type
        $asupdate = $xml.xml.results.system.asups.asup.asup_received_date
        $asupgendate = $xml.xml.results.system.asups.asup.asup_gen_date
        if($asupgendate.count -gt 1)
        {$agendate = $asupgendate[0].substring(0,10)}
        else{
        $agendate = $asupgendate.substring(0,10)}     
        $hostname = $xml.xml.results.system.hostname
        if($hostname.Count -gt '1'){$hostname = $hostname[0]}
    


$objects += New-Object -Type PSObject -Prop @{'Hostname'=$filer;'Last ASUP Date'=$agendate}
}
$Header = @"
<style>
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #6495ED;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
</style>
"@
$objects | Format-Table -AutoSize -Property 'Hostname','Last ASUP Date'
Write-Host "--------------------------------"
Write-Host "Total Controllers processed :" $objects.Count
Write-Host "Check the output CSV file with latest timestamp in Temp folder "
$objects| Select-Object 'Hostname','Last ASUP Date' | Export-Csv -NoTypeInformation "$path\Temp\$filename.csv"
$objects |Select-Object 'Hostname','Last ASUP Date' |ConvertTo-Html -Head $Header -Title "Daily ASUP Report" -Body "<h3>Daily ASUP Report - Ad-Hoc</h3>`n<h4>Total Controllers processed : $($objects.Count)</h4>"|Out-File $path\asup-checker.htm
$asup = Get-Content $path\asup-checker.htm | Out-String

############send mail#######################
$fromaddress = "asup-checker@netapp.com" 
$toaddress =  @('Matt.Diep@netapp.com', 'Brendan.Tudor@netapp.com', 'jai.waghela@netapp.com')
$body = $objects
$attachment = "$path\Temp\$filename.csv"
$Subject = "Daily ASUP Report (ad-hoc) - $(Get-Date)"
$SMTPServer = "smtp.corp.netapp.com"
Send-MailMessage -From $fromaddress -to $toaddress  -Subject $Subject `
-Body $asup -BodyAsHtml -SmtpServer $SMTPServer -Attachments $attachment
####################

Remove-Item –path $path\Temp\asupcheck.xml
}
run

