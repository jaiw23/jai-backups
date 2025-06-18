$path = Get-Location
if(-Not(Test-Path  "$path\Temp\"))
{new-item -type directory -path $path\Temp | Out-Null} 
$tempdir = "$path\Temp\"

$filelocation="$path\backupreport.htm"

if(-Not(Test-Path  "$path\clusters.txt"))
{
Write-Output ""
Write-Warning -Message ("Filer list not found in $path. Please Create a .txt file named ""filers.txt"" in $path and re run the scriprt")
exit
}
if(Test-Path "$path\backupreport.htm"){Remove-Item –path "$path\backupreport.htm" -Force}
if(Test-Path "$path\Temp\Backup_report.csv"){Remove-Item –path "$path\Temp\Backup_report.csv" -Force}

####### css ###################

$Header = @"
<style>
TABLE {font-family: "Trebuchet MS", Arial, Helvetica, sans-serif;border-collapse: collapse;width: 100%;table-layout: auto;color: #4a4a4d;}
TH {padding-top: 4px;padding-bottom: 4px;text-align: left;background-color: #6a8aa8;color: white;font-size : 90%}
TD {border-bottom: 1px solid #cecfd5;border-right: 1px solid #cecfd5;font-size : 90%}
</style>
"@


#############################
# Add Text to the HTML file #
#############################
ConvertTo-Html –title "Backup Report" –body "<h2 style ='font-family: Trebuchet MS; color : #444647;font-size : 18px'>NAS Premium Daily Backup Report</h2>`n<h5 style ='font-family: Trebuchet MS';font-size : 7px;color : #444647;>Updated on $(Get-Date)</h5>`n<h5 style ='font-family: Trebuchet MS';color : #464A46>*** This report is for past 24Hrs </h5>`n"| Out-File -Append $filelocation

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

Function Zip-File{
    Param(
        $infile,
        $outfile = ($infile -replace '\.gz$','')
        )

    $input = New-Object System.IO.FileStream $inFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
    $output = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
    $gzipStream = New-Object System.IO.Compression.GzipStream $input, ([IO.Compression.CompressionMode]::Decompress)

    $buffer = New-Object byte[](1024)
    while($true){
        $read = $gzipstream.Read($buffer, 0, 1024)
        if ($read -le 0){break}
        $output.Write($buffer, 0, $read)
        }

    $gzipStream.Close()
    $output.Close()
    $input.Close()
}
$objbackup = @()


$clusters = Get-Content $path\clusters.txt |  where {$_ -ne ""}

foreach($cluster in $clusters){

$htmltable = @()
$url = "http://restprd.corp.netapp.com/asup-rest-interface/ASUP_DATA/client_id/Fujitsu_capacity/cluster_name/$cluster/asup_subject/*MANAGEMENT*/last/1"

		$xml = get_xml $url asupcheck.xml $cluster
        $system = $xml.xml.results.system.hostname
        $systemlink = $xml.xml.results.system.asups.asup.asup_content_list
        foreach ($sys in $system)
        {
        $url = "http://restprd.corp.netapp.com/asup-rest-interface/ASUP_DATA/client_id/Fujitsu_capacity/hostname/$sys/asup_subject/*MANAGEMENT*/last/1"
        $xml = get_xml $url asupchecknode.xml $sys
		$node = $xml.xml.results.system.asups.asup.hostname
		$link = $xml.xml.results.system.asups.asup.asup_content_list
			$link = ($link -split '[\r\n]')
			$link = $link[0]
			if($link[0] -ne $null){
				$content = get_xml $link asup.xml $serial
				$links = $content.xml.results.system.asups.asup.list.content
				$section= @{}
				foreach($l in $links){
					$name=$l.name
					$name = $name.replace("-","")
					$link=$l.link
					$section.ADD($name, $link)
				}
			}
            
            $file = "$sys backuptest.gz"
            $xml = get_xml $section['BACKUP.GZ'] $file $node
			$url = $xml.xml.results.system.asups.asup.list.content.datalink
			$backup= get_file $url $file
			Zip-File -infile "$path\Temp\$file" -outfile "$path\Temp\$sys backup.txt"
           
            
            $startstring = Get-Content "$path\Temp\$sys backup.txt" | Select-String -Pattern " Start "
            
            $volume = @()

            foreach($string in $startstring)
                {
                if(($string -split ' ').count -eq 13)
                {
                $charcount = (($string -split ' ')[8] | Measure-Object -Character).Characters
                $volume += ($string -split ' ')[8].substring(0,$charcount-3)
                }
                elseif(($string -split ' ').count -eq 14)
                {
                $charcount = (($string -split ' ')[9] | Measure-Object -Character).Characters
                $volume += ($string -split ' ')[9].substring(0,$charcount-3)
                }
                }

            
                $volume = $volume |Select-String -NotMatch "root" | select -Unique
			
        
    
                foreach ($vol in $volume)
                {
                $vol = $vol | select -Unique
                $objbackupentry = ''| Select-Object Cluster, Volume, Type, StartTime, EndTime, BackupSize
                $starttimestring = (Get-Content "$path\Temp\$sys backup.txt" | Select-String -Pattern " Start " | Select-String -Pattern "$vol")[0]
                
                $starttime = ($starttimestring -split '/')[0].Substring(4, 28)
                if(($starttimestring -split ' ').count -eq 13){
                $level = ($starttimestring -split ' ')[11].Substring(0,1)
                if($level -eq 0){$backuptype = 'Full'}else{$backuptype = 'Incr'}} 
                
                elseif(($starttimestring -split ' ').count -eq 14){
                $level = ($starttimestring -split ' ')[12].Substring(0,1)
                if($level -eq 0){$backuptype = 'Full'}else{$backuptype = 'Incr'}} 
                            
                $endtimestring = (Get-Content "$path\Temp\$sys backup.txt" | Select-String -Pattern " End " | Select-String -Pattern "$vol")[0]
                $endtime = ($endtimestring -split '/')[0].Substring(4, 28)
                $backupsizecharcount = (($endtimestring -split "END")[1].Trim() | Measure-Object -Character).Characters
                $backupsize = (($endtimestring -split "END")[1].Trim()).substring(1,$backupsizecharcount-2)
                $objbackupentry.Cluster = $cluster
                $objbackupentry.Volume = $vol
                $objbackupentry.Type = $backuptype
                $objbackupentry.StartTime = $starttime
                $objbackupentry.EndTime = $endtime
                $objbackupentry.BackupSize = $backupsize
                $objbackup += $objbackupentry
                $htmltable +=$objbackupentry
                }

     }
 ConvertTo-Html –title "Backup Report" –body "<H3 style ='font-family: Trebuchet MS; color : #464A46;font-size : 14px'>$cluster</H5>"| Out-File -Append $filelocation       
 $htmltable | ConvertTo-Html -Head $Header | Out-File -Append $filelocation
 ConvertTo-Html –title "Backup Report" –body "<H3 style ='font-family: Trebuchet MS; color : #464A46;font-size : 13px'>$cluster - Total volumes backed up = $($htmltable.volume.count) </H5>"| Out-File -Append $filelocation
 
 }             

$objbackup| Export-Csv -NoTypeInformation "$path\Temp\Backup_report.csv"

$mailbody = Get-Content $filelocation -Raw

############send mail#######################
$fromaddress = "backup-script@netapp.com" 
$toaddress =  @('jai.waghela@netapp.com','jai.waghela@db.com')
#$toaddress =  @('db.global.netapp@list.db.com','ng-GSDC-DB-Offshore@netapp.com')
$body = $mailbody
$attachment = "$path\Temp\Backup_report.csv"
$Subject = "NAS Premium daily backup report - $(Get-Date -Format "dd-MM-yyyy")"
$SMTPServer = "smtp.corp.netapp.com"
Send-MailMessage -From $fromaddress -to $toaddress  -Subject $Subject `
-Body $body -BodyAsHtml -SmtpServer $SMTPServer -Attachments $attachment
####################
