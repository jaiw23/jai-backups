<#Import-Module DataONTAP 
Connect-NcController -Name 192.168.0.10
$command = @("system", "node", "run", "-node", "cluster1-01", "-command", "rdfile /etc/log/backup") 
$api = $("<system-cli><args><arg>" + ($command -join "</arg><arg>") + "</arg></args></system-cli>")
Do{
$output = Invoke-NcSystemApi -Request $api -ErrorAction Stop 
}Until($output.results.'cli-output'-ne '')#>

#$log = Get-Content -Path "C:\Users\jaiw\Documents\DB\Backup script\new\a.txt"


function parse_logs ($log){
ForEach($result In $log){
   if($result.Contains("TSM")){
      $timestamp    = $($result.Substring(0, $result.IndexOf("TSM"))).Replace("dmp", "").Trim()
      $items        = $timestamp.Split(" ")
      $monthName    = $items[1]
      $dayNumber    = $items[2]
      $24hourTime   = $items[3]
      $timezone     = $items[4]
      $yearNumber   = $items[5]
      $monthNumber  = [array]::indexof([cultureinfo]::CurrentCulture.DateTimeFormat.AbbreviatedMonthGenitiveNames, $monthName) + 1
      $logDate      = $($yearNumber + "-" +  ([String]$monthNumber).PadLeft(2,'0') + "-" + ([String]$dayNumber).PadLeft(2,'0'))
      $currentDate  = Get-Date -uformat "%Y-%m-%d"
      #Write-Host "Log Date: $logDate. Current Date: $currentDate"
      If($logDate -match $currentDate){
         return $result
      }
   }
}
}

$path = Get-Location
if(-Not(Test-Path  "$path\Temp\"))
{new-item -type directory -path $path\Temp | Out-Null} 
$tempdir = "$path\Temp\"

$filelocation="$path\backupreport.htm"

if(-Not(Test-Path  "$path\clusters.txt"))
{
Write-Output ""
Write-Warning -Message ("Cluster list not found in $path. Please Create a .txt file named ""clusters.txt"" in $path and re run the scriprt")
exit
}
if(-Not(Test-Path  "$path\credential.xml"))
{
Get-Credential | Export-Clixml "$path\credential.xml"
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

$objbackup = @()


$clusters = Get-Content $path\clusters.txt |  where {$_ -ne ""}

foreach($cluster in $clusters)
{
Connect-NcController -Name $cluster -Credential (Import-Clixml $path\credential.xml) | Out-Null
Write-Host ""
Write-Host ("Enumerating Cluster ""$cluster""") -ForegroundColor Gray
Write-Host ""
$nodes = Get-NcNode 
ForEach($node In $nodes)
{
$log = ""
$command = @("system", "node", "run", "-node", "cluster1-01", "-command", "rdfile /etc/log/backup") 
$api = $("<system-cli><args><arg>" + ($command -join "</arg><arg>") + "</arg></args></system-cli>")
Do{
$output = Invoke-NcSystemApi -Request $api -ErrorAction Stop 
}Until($output.results.'cli-output'-ne '')
$log = $output.results.'cli-output'
$currlog = parse_logs ($log)
}
}
$currlog
<#foreach($cluster in $clusters){
$voltotal = @()
$htmltable = @()
$url = "http://restprd.corp.netapp.com/asup-rest-interface/ASUP_DATA/client_id/Fujitsu_capacity/cluster_name/$cluster/asup_subject/*MANAGEMENT*/last/1"

		$xml = get_xml $url asupcheck.xml $cluster
        $system = $xml.xml.results.system.hostname
        $systemlink = $xml.xml.results.system.asups.asup.asup_content_list
        foreach ($sys in $system)
        {
        Write-Output "Processing - $sys"
        $url = "http://restprd.corp.netapp.com/asup-rest-interface/ASUP_DATA/client_id/Fujitsu_capacity/hostname/$sys/asup_subject/*MANAGEMENT*/last/1"
        $url2 = "http://restprd.corp.netapp.com/asup-rest-interface/ASUP_DATA/client_id/Fujitsu_capacity/hostname/$sys/asup_type/DOT-REGULAR"   
        $xml = get_xml $url asupchecknode.xml $sys
        $xml2 = get_xml $url2 asupchecknode2.xml $sys
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

            
            $link2 = $xml2.xml.results.system.asups.asup.asup_content_list
            $node2 = $xml2.xml.results.system.asups.asup.hostname
			$link2 = ($link2 -split '[\r\n]')
			$link2 = $link2[0]
			if($link2 -ne $null){
				$content2 = get_xml $link2 asup2.xml $serial
				$links3 = $content2.xml.results.system.asups.asup.list.content
				$section2= @{}
				foreach($l3 in $links3){
					$name2=$l3.name
					$name2 = $name2.replace("-","")
					$link3=$l3.link
					$section2.ADD($name2, $link3)
				}
			}
           
           $file2 = "$sys volume.xml"
           $file3 = "$sys voltable"
            $xml3 = get_xml $section2['VOLUME.XML'] $file2 $node2
            $url3 = $xml3.xml.results.system.asups.asup.list.content.datalink
            Invoke-WebRequest $url3 -OutFile "$path\TEMP\$file3"
			
[xml]$content   = Get-Content -Path "$path\TEMP\$file3"
[Array]$lines   = @();
ForEach($row In $content.T_VOLUME.ROW){
[Array]$lines += "/"+$row.vs+"/"+$row.vol}
$lines = $lines | Select-String -NotMatch "vol0" | Select-String -NotMatch "DV_CRS" | Select-String -NotMatch "root"| Select-String -NotMatch "restore"|Select-String -NotMatch "export"| Select-String -NotMatch "u1svm" | select -Unique
$voltotal += $lines
            
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
                #$starttimestring
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
 
$c = Compare-Object -ReferenceObject $voltotal -DifferenceObject $htmltable.Volume -PassThru

 ConvertTo-Html –title "Backup Report" –body "<H3 style ='font-family: Trebuchet MS; color : #464A46;font-size : 14px'>$cluster</H5>"| Out-File -Append $filelocation       
 $htmltable | ConvertTo-Html -Head $Header | Out-File -Append $filelocation
 ConvertTo-Html –title "Backup Report" –body "<H3 style ='font-family: Trebuchet MS; color : #464A46;font-size : 13px'>$cluster - Total volumes backed up = $($htmltable.volume.count) || Not backed up = <font color=red>$($c.count)</font></H5>"| Out-File -Append $filelocation
 foreach($l in $c){
 ConvertTo-Html –title "Backup Report" –body "<font size=2.4px color=red>$l</font><br>"| Out-File -Append $filelocation}
 }             


$objbackup| Export-Csv -NoTypeInformation "$path\Temp\Backup_report.csv"

$mailbody = Get-Content $filelocation -Raw

############send mail#######################
$fromaddress = "backup-script@netapp.com" 
$toaddress =  @('jai.waghela@netapp.com')
#$toaddress =  @('db.global.netapp@list.db.com','ng-GSDC-DB-Offshore@netapp.com')
$body = $mailbody
$attachment = "$path\Temp\Backup_report.csv"
$Subject = "NAS Premium daily backup report - $(Get-Date -Format "dd-MM-yyyy")"
$SMTPServer = "smtp.corp.netapp.com"
Send-MailMessage -From $fromaddress -to $toaddress  -Subject $Subject `
-Body $body -BodyAsHtml -SmtpServer $SMTPServer -Attachments $attachment
####################
#>