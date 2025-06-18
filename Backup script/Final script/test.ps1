$tempdir = "$path\Temp"
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


#$clusters = Get-Content $path\clusters.txt |  where {$_ -ne ""}
$clusters = "loncdcnasmcp01"
foreach($cluster in $clusters){
$vol = @()
$htmltable = @()
$url = "http://restprd.corp.netapp.com/asup-rest-interface/ASUP_DATA/client_id/Fujitsu_capacity/cluster_name/$cluster/asup_subject/*MANAGEMENT*/last/1"
		$xml = get_xml $url asupcheck.xml $cluster
        $system = $xml.xml.results.system.hostname
        $systemlink = $xml.xml.results.system.asups.asup.asup_content_list
        foreach ($sys in $system)
        {
        #$url = "http://restprd.corp.netapp.com/asup-rest-interface/ASUP_DATA/client_id/Fujitsu_capacity/hostname/$sys/asup_subject/*MANAGEMENT*/last/1"
        $url2 = "http://restprd.corp.netapp.com/asup-rest-interface/ASUP_DATA/client_id/Fujitsu_capacity/hostname/$sys/asup_type/DOT-REGULAR"
        #$xml = get_xml $url asupchecknode.xml $sys
        $xml2 = get_xml $url2 asupchecknode2.xml $sys
		<#$node = $xml.xml.results.system.asups.asup.hostname
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
			Zip-File -infile "$path\Temp\$file" -outfile "$path\Temp\$sys backup.txt"#>

            
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
   [Array]$lines += "/"+$row.vs+"/"+$row.vol }
$lines = $lines | Select-String -NotMatch "vol0" | Select-String -NotMatch "DV_CRS" | Select-String -NotMatch "root"| select -Unique
$vol += $lines
}
$testvol = get-content "$path\TEMP\voltest.txt"
$c = Compare-Object -ReferenceObject $vol -DifferenceObject $testvol -PassThru
$c
}

            
            