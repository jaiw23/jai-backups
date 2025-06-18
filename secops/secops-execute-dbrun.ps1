
#--------
# DBrun
#-------
 
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
 
$raw_service_request_new = get-WfaWorkflowParameter -Name raw_service_request
$raw_service_request = $raw_service_request_new | convertfrom-json
 
$request_new = get-WfaWorkflowParameter -Name request
$request = $request_new | convertfrom-json
 
 
$snow_cfg_new = get-WfaWorkflowParameter -Name snow_cfg
$snow_cfg = $snow_cfg_new | convertfrom-json
 
function dbrun(){
 
    param(
      [parameter(Mandatory=$true)]
      [hashtable]$dbrun_auth_header,
      [parameter(Mandatory=$true)]
      [hashtable]$dbrun_cfg,
      [parameter(Mandatory=$true)]
      $raw_service_request
    )
 
    $url = $dbrun_cfg['base_url'] + '/executor/executions'
    $data = @{
            "env" =          $dbrun_cfg['env'];
            "action" =       $dbrun_cfg['action'];
            "component" =    $dbrun_cfg['component'];
            "continue_with_allowed_servers" =      $dbrun_cfg['continue_with_allowed_servers'];
            "narId" =         $dbrun_cfg['nar_id'];
            "impacted_nar" =  $dbrun_cfg['nar_id'];
            "description" =   $dbrun_cfg['description'];
            "queued" =        $dbrun_cfg['queued'];
            "user" =          $dbrun_cfg['user'];
            "force_continue" = $dbrun_cfg['force_continue'];
            "instance" =       $dbrun_cfg['instance'];
            "param" =         @(@{"name" = "raw_service_request"; "type" = "dictionary"; "value" = $raw_service_request});
            "snow_id" =       "";
            "text_output" =   $dbrun_cfg['text_output'];
         }
 
    #Get-WfaLogger -Info -Message ($data | convertto-json -Depth 20)
 
    try{
        $url = $dbrun_cfg['base_url'] + '/executor/executions'
        $response = Invoke-WebRequest -uri $url -Method POST `
            -body $( ConvertTo-Json $data -Depth 10 ) `
            -headers $dbrun_auth_header
       
        Get-WfaLogger -Info -Message $($response | out-string)
 
        if ($response.StatusCode -eq 200){
            Get-Wfalogger -Info -Message $($response | Out-String)
            return $response
         }
        
        }catch {
            Get-WfaLogger -Info -Message ($_ | out-string)
        }
 
 
}
 
function dbrun_auth(){
 
    param(
      [parameter(Mandatory=$true)]
      [hashtable]$dbrun_cfg
    )
 
    $dbrun_auth_header = @{
        "Accept"            ="application/json"; 
        "content-type"      ="application/json";
       }
 
    try{
        $url = $dbrun_cfg['base_url'] + '/auth/system_tokens/'+ $dbrun_cfg['nar_id']+'/'+ $dbrun_cfg['env']
        $response = Invoke-WebRequest -uri $url -Method GET
        Get-WfaLogger -Info -Message $($response | out-string)
        if ($response.StatusCode -eq 200){
            $dbrun_auth_header['X-Auth-Token'] = $($response.content | convertfrom-json).token
            return $dbrun_auth_header
         }
        
        }catch {
            Get-WfaLogger -Info -Message ($_ | out-string)
        }
 
}
 
function snow_comment() {
   param(
      [parameter(Mandatory=$true)]
      $snow_cfg,
      [parameter(Mandatory=$true)]
      [string]$comment
   )
   #-----------------------------------------------------------------
   # FIXME: RTU 25 Oct 2021
   # NETAPP-81
   # We will now support snow updates from WFA
   # This function will get auth info and perform updates to snow
   #-----------------------------------------------------------------
 
   $data = @{"work_notes" = $comment}
   $headers = @{"Authorization" = $snow_cfg.headers.Authorization;
                "Content-Type" = $snow_cfg.headers."Content-Type";
   }
 
    try {
      $uri = "$($snow_cfg.base_url)/$($snow_cfg.sys_id)"
      $response = Invoke-WebRequest -uri $uri -Method PUT `
         -body $( ConvertTo-Json $data -Depth 10 ) `
         -headers $headers `
         -Proxy $snow_cfg.proxy
      if ($response.StatusCode -ne 200){
         Get-Wfalogger -Info -Message $("Error commenting : $($_.Exception | out-String)")
      }
   }
   catch { Get-Wfalogger -Info -Message $($_ | Out-String)}
}
 
 
$dbrun_cfg = @{
   'base_url'              = https://cgaslprd.uk.db.com:5001;
   'nar_id'                = "133275-1";
   'env'                   = "PROD";
   'action' = "site";
   'component' = "";
   'continue_with_allowed_servers' = "True";
   'description' = "Running SECOPS site.yml";
   'queued' = "1";
   'user' = jai.waghela@db.com;
   'force_continue' = "True"
   'instance' = "dbDoes"
 
}
 
$dbrun_auth = dbrun_auth -dbrun_cfg $dbrun_cfg
$dbrun_response = dbrun -dbrun_auth_header $dbrun_auth -dbrun_cfg $dbrun_cfg -raw_service_request $raw_service_request
snow_comment -snow_cfg $snow_cfg -comment "Payload sent to dbrun : $($dbrun_response.Content | out-string)"

