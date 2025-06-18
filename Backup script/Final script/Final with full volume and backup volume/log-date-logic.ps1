$results = @("dmp Thu Sep 3 23:00:42 +08 2020 TSM /sinkdcmcp1svm3/sinkdcmcp1svm3_data_02(0) Start (Level 0, NDMP:56979)")
ForEach($result In $results){
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
         Write-Host $result
      }Else{
         Write-Warning -Message $result
      }
   }
}