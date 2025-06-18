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

$path = Get-Location
if(-Not(Test-Path  "$path\Temp\"))
{new-item -type directory -path $path\Temp | Out-Null} 
$tempdir = "$path\Temp\"

if(-Not(Test-Path  "$path\clusters.txt"))
{
Write-Output ""
Write-Warning -Message ("Filer list not found in $path. Please Create a .txt file named ""filers.txt"" in $path and re run the scriprt")
exit
}
$clusters = Get-Content $path\clusters.txt |  where {$_ -ne ""}

foreach($cluster in $clusters){

$url = "http://restprd.corp.netapp.com/asup-rest-interface/ASUP_DATA/client_id/Fujitsu_capacity/cluster_name/$cluster/asup_subject/*MANAGEMENT*/last/1"
$volume = @()
		$xml = get_xml $url asupcheck.xml $cluster
        $system = $xml.xml.results.system.hostname
        foreach ($sys in $system)
        {
       
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
            
            $file = "backuptest.gz"
            $xml = get_xml $section['BACKUP.GZ'] $file $node
			$url = $xml.xml.results.system.asups.asup.list.content.datalink
			$backup= get_file $url $file
			Zip-File -infile "$path\Temp\$file" -outfile "$path\Temp\$sys backup.txt"
           
            
            $startstring = Get-Content "$path\Temp\backup.txt" | Select-String -Pattern " Start "
         
            foreach($string in $startstring)
                {
                $charcount = (($string -split ' ')[8] | Measure-Object -Character).Characters
                $volume += ($string -split ' ')[8].substring(0,$charcount-3)
                }

            }
                $volume = $volume |Select-String -NotMatch "root" | Select -Unique
			
        
    
                foreach ($vol in $volume)
                {
                $objbackupentry = ''| Select-Object Cluster, Volume, type, Stime, Etime, size
                $starttimestring = (Get-Content "$path\Temp\backup.txt" | Select-String -Pattern " Start " | Select-String -Pattern "$vol")[0]
                $starttime = ($starttimestring -split '/')[0].Substring(4, 28)
                $level = ($starttimestring -split ' ')[11].Substring(0,1)
                if($level -eq 0){$backuptype = 'Full'}else{$backuptype = 'Incr'}               
                $endtimestring = (Get-Content "$path\Temp\backup.txt" | Select-String -Pattern " End " | Select-String -Pattern "$vol")[0]
                $endtime = ($endtimestring -split '/')[0].Substring(4, 28)
                $backupsizecharcount = (($endtimestring -split "END")[1].Trim() | Measure-Object -Character).Characters
                $backupsize = (($endtimestring -split "END")[1].Trim()).substring(1,$backupsizecharcount-2)
                $objbackupentry.Cluster = $cluster
                $objbackupentry.Volume = $vol
                $objbackupentry.type = $backuptype
                $objbackupentry.Stime = $starttime
                $objbackupentry.Etime = $endtime
                $objbackupentry.size = $backupsize
                $objbackup += $objbackupentry
                
                }

            
                
}

$objbackup | Format-Table