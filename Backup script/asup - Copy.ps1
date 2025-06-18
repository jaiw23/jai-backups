function get_xml($url, $filename, $serial){
$tempdir = 'C:\Temp\asup'
	$destination = $tempdir+"\"+$filename
	try{
		Invoke-WebRequest $url -OutFile $destination
		[xml]$xml = Get-Content $destination
		return $xml
	}
	catch{
		$date = (Get-Date)
		Write "$date - Error: $_ Serial: $serial" >> C:\Temp\log.txt
		Write "$date - URL: $url" >>$logfile
	}
}

function get_file($url, $filename){
	$destination = $tempdir+"\"+$filename
	try{
		Invoke-WebRequest $url -OutFile $destination
	}
	catch{
		$date = (Get-Date)
		Write "$date - Error: $_ URL: $url" >> C:\Temp\log.txt
	}
}


function run {
$tempdir = 'C:\Temp\asup'
clear
$serial = 941423000098
$url = "http://restprd.corp.netapp.com/asup-rest-interface/ASUP_DATA/client_id/smartsolve/sys_serial_no/$serial/asup_type/DOT-REGULAR"

		$xml = get_xml $url asupcheck.xml $serial
		$osversion = $xml.xml.results.system.sys_version
		$model = $xml.xml.results.system.sys_model
		$mode = $xml.xml.results.system.asups.asup.sys_operating_mode
$mode = "abcde5678"
$mode = $xml.xml.results.system.asups.asup.sys_operating_mode
		
		$split = $mode -split ' '
		$mode = $split[0]
$link = $xml.xml.results.system.asups.asup.asup_content_list
			$link = ($link -split '[\r\n]')
			$link = $link[0]
			if($link[0] -ne $null){
				$content = get_xml $link asup.xml $serial
				$links = $content.xml.results.system.asups.asup.list.content
				$section= @{}
				foreach($l in $links){
#Write-Host $l.name
					$name=$l.name
					$name = $name.replace("-","")
					$link=$l.link
					$section.ADD($name, $link)
				}
			}
$file = 'AGGR-EFFICIENCY.XML'
			$xml = get_xml $section['AGGREFFICIENCY.XML'] $file $serial
			$url = $xml.xml.results.system.asups.asup.list.content.datalink
			$aggr= get_file $url $file

[xml]$content   = Get-Content -Path "C:\Temp\asup\AGGR-EFFICIENCY.XML"
[Array]$lines   = @();
[String]$header = "Collection Date Time,"
ForEach($field In $content.T_AGGR_EFFICIENCY.TABLE_INFO.field){
   $header += $($field.ui_name).Replace(",", "") + ","
}
[String]$header = $header.Substring(0, $header.Length -1)
[Array]$lines  += $header
ForEach($row In $content.T_AGGR_EFFICIENCY.ROW){
   [Array]$lines += $row.col_time_us + "," + $row.aggr     + "," + $row.node + "," + $row.tlu    + "," + $row.tpu  + "," + $row.tser   + "," + `
                    $row.vlu         + "," + $row.vpu      + "," + $row.ves  + "," + $row.vcs    + "," + $row.vvzs + "," + $row.vdrser + "," + `
                    $row.alu         + "," + $row.apu      + "," + $row.acs  + "," + $row.adrser + "," + $row.slu  + "," + $row.fvlu   + "," + `
                    $row.fvpu        + "," + $row.sfvdrser + "," + $row.noov + "," + $row.nosdv  + "," + $row.noscldv
}
$lines | out-file  'C:\Temp\asup\aggr.csv'

}


run