

param (
   [parameter(Mandatory=$False, HelpMessage="Application short name")]
   [string]$request_type,
  
   [parameter(Mandatory=$False, HelpMessage="Application short name")]
   [string]$ritm,
  
   [parameter(Mandatory=$False, HelpMessage="Application short name")]
   [string]$change_itask,
  
   [parameter(Mandatory=$False, HelpMessage="Application short name")]
   [string]$app_short_name,
 
   [parameter(Mandatory=$True, HelpMessage="Contact")]
   [string]$contact,
 
   [parameter(Mandatory=$True, HelpMessage="Cost Centre")]
   [string]$cost_centre,
 
   [parameter(Mandatory=$True, HelpMessage="email address")]
   [string]$email_address,
 
   [parameter(Mandatory=$True, HelpMessage="environment")]
   [string]$environment,
 
   [parameter(Mandatory=$True, HelpMessage="Desired storage location")]
   [string]$location,
 
   [parameter(Mandatory=$False, HelpMessage="NAR ID of app")]
   [string]$nar_id,
 
   [parameter(Mandatory=$True)]
   [string]$service_level,
 
   [parameter(Mandatory=$True)]
   [string]$service_name,
 
   [parameter(Mandatory=$False)]
   [string]$qtrees,
 
   [parameter(Mandatory=$True)]
   [int]$phase
 
)
 
########################################################################
# FUNCTIONS
########################################################################
#-----------------------------------------------------------------------
# UTILITY FUNCTIONS
#-----------------------------------------------------------------------
#-----------------------------------------------------------------
# Return value names are of the form "__raw_req_" where NNN
# is a 3 digit number indicating sequence.  Sequence is maintained
# because it may be significant within the Execution Layer.
#-----------------------------------------------------------------
 
function set_wfa_return_values() {
   param(
      [parameter(Mandatory=$true, HelpMessage="placement solution")]
      [hashtable]$placement_solution
   )
   #-----------------------------------------------------------------
   # The following 2 return values are interpreted by the calling
   # Python script
   #-----------------------------------------------------------------
   Add-WfaWorkflowParameter -Name 'success'  -Value $placement_solution['success']  -AddAsReturnParameter $True
   Add-WfaWorkflowParameter -Name 'reason'   -Value $placement_solution['reason']   -AddAsReturnParameter $True
   if ( -not $placement_solution['success'] -eq "TRUE" ){
      return
   }
   #-----------------------------------------------------------------
   # The rest of the return values are all passed unmodified to the
   # Execution Layer
   #-----------------------------------------------------------------
   Add-WfaWorkflowParameter -Name 'req_source'  -Value 'wfa' -AddAsReturnParameter $True
   Add-WfaWorkflowParameter -Name 'raw_req_001' -Value $("__res_type='';std_name=" + $placement_solution['std_name']) -AddAsReturnParameter $True
   Add-WfaWorkflowParameter -Name 'raw_req_002' -Value $("__res_type='';service=" + $placement_solution['service']) -AddAsReturnParameter $True
   Add-WfaWorkflowParameter -Name 'raw_req_003' -Value $("__res_type='';operation=" + $placement_solution['operation']) -AddAsReturnParameter $True
 
   Get-WfaLogger -Info -Message $( $placement_solution['return_values'].length )
   $return_value_idx = 4
   foreach ($return_value in $placement_solution['return_values'] ){
      Get-WfaLogger -Info -Message $return_value
      Add-WfaWorkflowParameter -Name $("raw_req_{0:d3}"  -f ($return_value_idx) ) -Value $return_value -AddAsReturnParameter $True
      $return_value_idx += 1
   }
}
 
function Get-WFAUserPassword () {
   param(
      [parameter(Mandatory=$true)]
      [string]$pw2get
   )
 
   $InstallDir = (Get-ItemProperty -Path HKLM:\Software\NetApp\WFA -Name WFAInstallDir).WFAInstallDir
  
   $string = Get-Content $InstallDir\jboss\bin\wfa.conf | Where-Object { $_.Contains($pw2get) }
   $mysplit = $string.split(":")
   $var = $mysplit[1]
  
   cd $InstallDir\bin\supportfiles\
   $string = echo $var | .\openssl.exe enc -aes-256-cbc -pbkdf2 -iter 100000 -a  -d -salt -pass pass:netapp
 
   return $string
  }
 
function update_chargeback_table(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$db_user,
      [parameter(Mandatory=$true)]
      [string]$db_pw
   )
 
   Get-WfaLogger -Info -Message "Entered chargeback function"
 
   foreach($qtree_value in $request['qtrees']){
 
   Get-WfaLogger -Info -Message "qtree = $($qtree_value['qtree'] | out-string)"
      Get-WfaLogger -Info -Message "svm = $($qtree_value['svm'] | out-string)"
      Get-WfaLogger -Info -Message "vol = $($qtree_value['vol'] | out-string)"
      Get-WfaLogger -Info -Message "cluster = $($qtree_value['cluster'] | out-string)"
      Get-WfaLogger -Info -Message "--------------------"
 
   $sql = "
      SELECT
         cluster_primary_address AS hostname,
         storage_requirement_gb  AS storage_requirement_gb
      FROM playground.chargeback
      WHERE 1
         AND vserver_name  = '" + $($qtree_value['svm']) + "'
         AND volume_name   = '" + $($qtree_value['vol']) + "'
         AND qtree_name    = '" + $($qtree_value['qtree']) + "'
   ;
   "
   Get-WfaLogger -Info -Message $("Execute SQL: " + $sql)
 
   $results = Invoke-MySqlQuery -query $sql -user root -password $db_pw
   Get-WfaLogger -Info -Message "Checking if storage path already exists in chargeback table"
   Get-WfaLogger -Info -Message $("results[0]: " + $results[0])
   if ( $results[0] -eq 0 ){
      $msg = "Unable to find path in chargeback table: " + $($qtree_value['qtree'] | out-string)
      Get-WfaLogger -Info -Message $msg
 
      $sql = "
         INSERT INTO playground.chargeback
         VALUES (
            NULL,
            '" + $($qtree_value['cluster']) + "',
            '" + $($qtree_value['svm']) + "',
            '" + $($qtree_value['vol']) + "',
            '" + $($qtree_value['qtree']) + "_deleted"  + "',
            '',
            'nfs',
            0,
            '',
            '" + $request['app_short_name']                                + "',
            '" + $request['service_name']                                  + "',
            '',
            '',
            '',
            '" + $request['email_address']                                 + "',           
            '" + $($qtree_value['cluster'])                                        + "',
            NULL,
            '" + $request['environment']                                   + "',
            '" + $request['correlation_id']                               + "'
         )
         ;
      "
      Get-WfaLogger -Info -Message $sql
 
      Invoke-MySqlQuery -query $sql -user $db_user -password $db_pw
     
      }
    
     else {
  
       $sql = "
         UPDATE playground.chargeback
         SET storage_requirement_gb = 0, qtree_name = '$($qtree_value['qtree'])_deleted'
         WHERE 1
         AND cluster_name =   '" + $($qtree_value['cluster']) + "'
         AND vserver_name =   '" + $($qtree_value['svm']) + "'
         AND qtree_name =     '" + $($qtree_value['qtree']) + "'
         ;
         "
         Get-WfaLogger -Info -Message $sql
 
         Invoke-MySqlQuery -query $sql -user $db_user -password $db_pw
 
         }
    }
}
 
function update_budget_table(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$db_user,
      [parameter(Mandatory=$true)]
      [string]$db_pw
   )
   Get-WfaLogger -Info -Message "Entered update_budget_table()"
 
   $sql = "
           SELECT *
           FROM playground.secops_budget
           WHERE 1
           AND ritm = '$ritm'
           AND env = '$environment'
           AND location = '$location'
           ;
          "
 
   $result = Invoke-MySqlQuery -Query $sql -user 'root' -password $mysql_pass
   Get-WfaLogger -Info -Message $($result[1].budget)
   Get-WfaLogger -Info -Message $($request['qtrees'].Count)
   Get-WfaLogger -Info -Message $($request['qtrees'].Count * 25)
   $budget_allocated = $result[1].budget + ($request['qtrees'].Count * 25)
   $new_count = [math]::floor($budget_allocated/25)
 
   $sql = "
         UPDATE playground.secops_budget
         SET
         budget = $budget_allocated,
         count = $new_count
         WHERE
         ritm = '" +$ritm+ "' AND
         location = '" +$location+ "' AND
         env = '" +$environment+ "'
         ;
      "
      Get-WfaLogger -Info -Message $sql
      Invoke-MySqlQuery -query $sql -user $db_user -password $db_pw
}
 
 
function qtree_phase1 (){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   Get-WfaLogger -Info -Message "Entered qtree_phase1()"
   $qtrees        = @()
   $return_values = @()
 
   foreach($qtree_value in $request['qtrees']){
      Get-WfaLogger -Info -Message "qtree = $($qtree_value['qtree'] | out-string)"
      Get-WfaLogger -Info -Message "svm = $($qtree_value['svm'] | out-string)"
      Get-WfaLogger -Info -Message "vol = $($qtree_value['vol'] | out-string)"
      Get-WfaLogger -Info -Message "cluster = $($qtree_value['cluster'] | out-string)"
      Get-WfaLogger -Info -Message "--------------------"
 
      $qtrees += @{
         'hostname'     = $qtree_value['cluster'];
         'vserver'      = $qtree_value['svm'];
         'flexvol_name' = $qtree_value['vol'];
         'from_name'    = $qtree_value['qtree'];
         'name'         = $qtree_value['qtree'] + '_to_be_deleted'
      }
   }
 
   return @{
      'success'         = $True;
      'reason'          = "successfully built qtree name";
      'ontap_qtree'     = $qtrees
   }
}
 
function qtree_phase2 (){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   Get-WfaLogger -Info -Message "Entered qtree_phase2()"
 
   $qtrees        = @()
   $return_values = @()
 
   foreach($qtree_value in $request['qtrees']){
      Get-WfaLogger -Info -Message "qtree = $($qtree_value['qtree']+ '_to_be_deleted' | out-string)"
      Get-WfaLogger -Info -Message "svm = $($qtree_value['svm'] | out-string)"
      Get-WfaLogger -Info -Message "vol = $($qtree_value['vol'] | out-string)"
      Get-WfaLogger -Info -Message "cluster = $($qtree_value['cluster'] | out-string)"
      Get-WfaLogger -Info -Message "--------------------"
 
      $qtrees += @{
         'hostname'     = $qtree_value['cluster'];
         'vserver'      = $qtree_value['svm'];
         'flexvol_name' = $qtree_value['vol'];
         'name'         = $qtree_value['qtree'] + '_to_be_deleted'
      }
   }
 
   return @{
      'success'         = $True;
      'reason'          = "successfully built qtree name";
      'ontap_qtree'     = $qtrees
   }
}
 
 
function nfs_export(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request
   )
 
   Get-WfaLogger -Info -Message "Entering nfs_export()"
   #------------------------------------------------------------
   # I pull the info from the passed path rather than the qtree
   # name because the path always refers to the original qtree
   # name.  The qtree name changes from phase 1 to phase 2 so to
   # be absolutely sure that I always refer to the correct name
   # I use the path.  This ensures that if we move this function
   # to Phase 2, it still works correctly.
   #------------------------------------------------------------
 
   $return_values = @()
   $export_policy = @()
 
   foreach($qtree_value in $request['qtrees']){
      Get-WfaLogger -Info -Message "qtree = $($qtree_value['qtree']+ '_to_be_deleted' | out-string)"
      Get-WfaLogger -Info -Message "--------------------"
 
      $export_policy += @{
         'hostname'     = $qtree_value['cluster'];
         'vserver'      = $qtree_value['svm'];
         'name'         = $qtree_value['qtree']
      }
   }
 
   return @{
      'success'         = $True;
      'reason'          = "successfully built exportr_policy";
      'ontap_export_policy'     = $export_policy
   }
}
 
function snow_get_sysid() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$snow_cfg
   )
   #-----------------------------------------------------------------
   # FIXME: RTU 25 Oct 2021
   # NETAPP-81
   # We will now support snow updates from WFA
   # This function will get auth info and perform updates to snow
   #-----------------------------------------------------------------
    try {
      $uri = "$($snow_cfg['base_url'])?sysparm_query=number=$($snow_cfg['itask'])"
      $response = Invoke-WebRequest -uri $uri -Method GET `
         -body $( ConvertTo-Json $data -Depth 10 ) `
         -headers $snow_cfg['headers'] `
         -Proxy $snow_cfg['proxy']
      if ($response.StatusCode -ne 200){
         Get-Wfalogger -Info -Message  $("Error getting sys_id: $($_.Exception | out-String)")
         Throw "Invalid ITASK provided"
      }
      return $response
   }
   catch { Get-Wfalogger -Info -Message $($_ | Out-String)
           Throw "Cant get sys_id for $($snow_cfg['itask'])"
   }
}
 
function snow_comment() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$snow_cfg,
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
 
    try {
      $uri = "$($snow_cfg['base_url'])/$($snow_cfg['sys_id'])"
      $response = Invoke-WebRequest -uri $uri -Method PUT `
         -body $( ConvertTo-Json $data -Depth 10 ) `
         -headers $snow_cfg['headers'] `
         -Proxy $snow_cfg['proxy']
      if ($response.StatusCode -ne 200){
         Get-Wfalogger -Info -Message $("Error commenting : $($_.Exception | out-String)")
      }
   }
   catch { Get-Wfalogger -Info -Message $($_ | Out-String)}
}
 
function dbrun_wfa_resume() {
 
   Get-WfaLogger -Info -Message "Inside dbRun func"
   $return_values = @()
   $dbrun_resume        = @()
 
   $cred1 = Get-WfaCredentials -Host $localhost
   $user = $cred1.UserName
   $pass = [System.Net.NetworkCredential]::new("", $cred1.Password).Password
 
   $pair = "$($user):$($pass)"
 
   $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
 
   $basicAuthValue = "Basic $encodedCreds"
 
      $dbrun_resume += @{
         'wfa_url'      = 'https://nycinnwfab1.us.db.com/rest/secops_provisioning/jobs/' + $wfa_job_id + '/resume';
         'wfa_action'   = 'resume';
         'wfa_auth'       = $basicAuthValue;
         'wfa_job_id'    = $wfa_job_id;
         'content_type' = 'application/json';
         'accept'       = 'application/json';
         'proxy'        = 'http://serverproxy.intranet.db.com:8080';
      }
 
   return @{
      'success'         = $True;
      'reason'          = "successfully set wfa resume parameter";
      'dbrun_wfa_resume'     = $dbrun_resume
   }
}
 
function mount_paths(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request
   )
 
   $return_values = @()
   if($request['phase'] -eq 1){
   $comment = $SERVICENOW_COMMENT_PHASE1 + "<br><br>"
   }
   elseif($request['phase'] -eq 2){
   $comment = $SERVICENOW_COMMENT_PHASE2 + "<br><br>"
   }
   foreach($qtree_value in $request['qtrees']){ 
      $mount_paths += $qtree_value['svm']+$acl_codes_map['domains'][$qtree_value['svm'].ToUpper().Substring(0,3)]+":/"+$qtree_value['vol']+"/"+$qtree_value['qtree']+"<br>"
   }
   $paths = @{
      'success'      = $True;
      'reason'       = 'Mount path created';
      'return_values'    = $return_values;
      'mount_paths'   = $comment + $mount_paths;
      }  
   return $paths
}
 
function servicenow_dbrun(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$snow_cfg
   )
   $return_values = @()
   Get-WfaLogger -Info -Message $( "sending SNOW details to dbrun")
 
   $snow = @{
      'success'         = $True;
      'reason'          = "Connecting to ServiceNow";
      'servicenow'   = @(
        @{
          'url'                = "$($snow_cfg['base_url'])/$($snow_cfg['sys_id'])";
          'Authorization'      = "$($snow_cfg['headers']['Authorization'])";
          'proxy'              = "$($snow_cfg['proxy'])";
        }
      )
   }  
   return $snow
}
 
########################################################################
# VARIABLES & CONSTANTS
########################################################################
 
$STORAGE_REQUIREMENT_UNITS = 'g'
$cluster_service_map = @{
   'NAS Premium' = @{
      'gfs' = @{
         'prefix'    = 'm';
         'service'   = 'nas_premium_gfs';
         'std_name'  = 'nas_premium'
      }; 
      'Fabric' = @{
         'prefix'    = 'm';
         'service'   = 'nas_premium_fabric';
         'std_name'  = 'nas_premium'
      };
      'secops' = @{       
         'prefix'  = '';
         'service'   = 'nas_premium_secops';
         'std_name'  = 'nas_premium'
      };  
   };
   'NAS Shared'    = @{
      'FSU' = @{
         'prefix'    = 'c';
         'service'   = 'nas_shared_fsu';
         'std_name'  = 'nas_shared_'
      };
      'VFS' = @{
         'prefix'    = 'c';
         'service'   = 'nas_shared_vfs';
         'std_name'  = 'nas_shared'
      };
      'eDiscovery' = @{
         'prefix'    = 'c';
         'service'   = 'nas_shared_ediscovery';
         'std_name'  = 'nas_shared'
      };  
   };
}
 
$acl_codes_map = @{
   'services'  = @{
      'NAS Premium'   = 'P';
      'NAS Shared'    = 'S'
  };
   'regions'   = @{
      'LON'    = 'EM';
      'FRA'    = 'EM';
      'SIN'    = 'AP';
      'NYC'    = 'US';
      'IND'    = 'AP'
 
   };
   'domains'   = @{
      'LON'    = '.uk.db.com';
      'FRA'    = '.de.db.com';
      'SIN'    = '.sg.db.com';
      'NYC'    = '.us.db.com';
      'IND'    = '.in.db.com'
 
   };
   'environments' = @{
      'prd'          = 'P';
      'uat'          = 'U';
      'dev'          = 'D';
   };
}
 
$SERVICENOW_COMMENT_PHASE1 = "Your SECOPS deletion request for below paths is now fully complete and access has been removed to your storage as requested. The storage will be completely deleted in 30 days."
$SERVICENOW_COMMENT_PHASE2  = "Your SECOPS deletion request is now fully complete and below storage deleted as requested"
 
########################################################################
# MAIN
########################################################################
Get-WfaLogger -Info -Message "##################### PRELIMINARIES #####################"
Get-WfaLogger -Info -Message "Get DB Passwords"
$playground_pass  = Get-WFAUserPassword -pw2get "WFAUSER"
$mysql_pass       = Get-WFAUserPassword -pw2get "MySQL"
 
$request = @{
   'app_short_name'                = $app_short_name.ToLower();
   'email_address'                 = $email_address;
   'environment'                   = $environment.ToLower();
   'location'                      = $location.ToLower();
   'service_level'                 = $service_level.ToLower();
   'service_name'                  = $service_name.ToLower();
   'qtrees'                        = @();
   'ritm'                          = $ritm;
   'correlation_id'                = $change_itask;
   'sys_id'                        = $sys_id;
   'phase'                         = $phase;
}
 
#---------------- SNOW ----------------
$snow_cfg = @{
   'base_url'              = https://dbunityworker.service-now.com/api/now/table/change_task;
   'itask'                 = $change_itask;
   'proxy'                 = 'http://serverproxy.intranet.db.com:8080';
   "headers" = @{
                           "Content-Type" = "application/json";
                           "Authorization" = "Basic bmFzX2F1dG9tYXRpb25faW50ZXJmYWNlOk5mMkoxeE1N"};
    }
 
$response_api = snow_get_sysid -snow_cfg $snow_cfg
$snow_cfg['sys_id'] = ($response_api.content | convertfrom-json).result.sys_id
get-wfalogger -info -message "$($snow_cfg | Out-String)"
 
#---------------------------------------------------------------
# Create array of qtrees from input provided in GUI
#---------------------------------------------------------------
 
Get-Wfalogger -Info -Message "getting qtree list"
foreach( $qtree_row in $qtrees.Split(',') ){
  $qtree, $svm, $vol, $cluster = $qtree_row.Split('~')
  Get-Wfalogger -Info -Message $('qtree= ' + $qtree)
  $qtree_list = @{
    "qtree"    = $qtree;
    "svm"      = $svm;
    "vol"      = $vol;
    "cluster"  = $cluster;
  }
  $request['qtrees'] += $qtree_list
}
 
 
$wfa_job_id = Get-WfaRestParameter -Name jobId
 
$placement_solution = @{
   'success'         = 'TRUE';
   'reason'          = 'successfully determined a placement solution';
   'std_name'        = '';
   'service'         = '';
   'operation'       = '';
   'resources'       = @{};
   'return_values'   = @();
}
 
$raw_service_request = @{
  'service'     = 'nas_premium_secops';
  'operation'   = '';
  'std_name'    = 'nas_premium';
  'req_details' = @{}
}
 
$wfa_job_id = Get-WfaRestParameter -Name jobId
snow_comment -snow_cfg $snow_cfg -comment "Execution started (Deletion) - WFA job id : $wfa_job_id"
 
#---------------------------------------------------------------
# If we don't have a mapping for the service we must fail
#---------------------------------------------------------------
Get-WfaLogger -Info -Message "Check requested service against supported services"
if ( -not $cluster_service_map.ContainsKey($service_level) ){
   $fail_msg = 'unsupported service requested: ' + $service_level
   Get-WfaLogger -Info -Message $($fail_msg)
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
$service_data = $cluster_service_map[$service_level]
if ( -not $service_data.ContainsKey($service_name) ){
   $fail_msg = 'unsupported service requested: ' + $service_name
   Get-WfaLogger -Info -Message $($fail_msg)
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
 
if ( $request['phase'] -eq 1 ){
 
   $raw_service_request['operation']  = 'offline'
  
   Get-WfaLogger -Info -Message "##################### QTREE PHASE 1 #####################"
   $qtree = qtree_phase1  `
      -request    $request                      `
      -mysql_pw   $mysql_pass
   if ( -not $qtree['success'] ){
      $fail_msg = $qtree['reason']
      Get-WfaLogger -Info -Message $fail_msg
      exit
   }
    $raw_service_request['req_details']['ontap_qtree'] = $qtree['ontap_qtree']
    #Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
}
elseif( $request['phase'] -eq 2 ){
 
   $raw_service_request['operation']  = 'delete'
 
   Get-WfaLogger -Info -Message "##################### QTREE PHASE 2 #####################"
   $qtree = qtree_phase2  `
      -request    $request                      `
      -mysql_pw   $mysql_pass
   if ( -not $qtree['success'] ){
      $fail_msg = $qtree['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
    $raw_service_request['req_details']['ontap_qtree'] = $qtree['ontap_qtree']
    #Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
}
else{
   $fail_msg = "Invalid phase passed: " + $request['phase']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
 
if ($request['phase'] -eq 2){
   Get-WfaLogger -Info -Message "##################### NFS EXPORT #####################"
   $nfs = nfs_export  `
      -request    $request                      `                    
   if ( -not $nfs['success'] ){
      $fail_msg = $nfs['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
   $raw_service_request['req_details']['ontap_export_policy'] = $nfs['ontap_export_policy']
   #Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
}
 
Get-WfaLogger -Info -Message "##################### dbRun WFA RESUME #####################"
$dbrun_wfa_resume = dbrun_wfa_resume
if ( -not $dbrun_wfa_resume['success'] ){
      $fail_msg = 'Failed sending wfa resume payload'
      Get-WfaLogger -Info -Message $fail_msg
      snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
      Throw $fail_msg
   }
$raw_service_request['req_details']['dbrun_wfa_resume']      = $dbrun_wfa_resume['dbrun_wfa_resume']
 
Get-WfaLogger -Info -Message "##################### MOUNT PATHS #####################"
$path = mount_paths `
      -request $request
           
if ( -not $path['success'] ){
   $fail_msg = "Failed createing mount paths"
   Get-WfaLogger -Info -Message $fail_msg
   Throw $fail_msg
}
 
Get-WfaLogger -Info -Message $( $path['mount_paths'])
 
Get-WfaLogger -Info -Message "##################### dbRun SNOW PARAM #####################"
$dbrun_snow_param = servicenow_dbrun -snow_cfg $snow_cfg
if ( -not $dbrun_snow_param['success'] ){
      $fail_msg = 'Failed sending snow dbrun param'
      Get-WfaLogger -Info -Message $fail_msg
      snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
      Throw $fail_msg
   }
$raw_service_request['req_details']['servicenow']    = $dbrun_snow_param['servicenow']
 
if ($request['phase'] -eq 2){
 
Get-WfaLogger -Info -Message "##################### CHARGEBACK TABLE #####################"
update_chargeback_table `
   -request $request `
   -db_user 'root' `
   -db_pw $mysql_pass
 
 
Get-WfaLogger -Info -Message "##################### BUDGET TABLE #####################"
update_budget_table `
   -request $request `
   -db_user 'root' `
   -db_pw $mysql_pass
 
}
 
Get-WfaLogger -Info -Message "##################### RAW SERVICE REQUEST #####################"
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
Get-WfaLogger -Info -Message "##################### SNOW COMMENT #####################"
 
snow_comment -snow_cfg $snow_cfg -comment "Sending payload to dbrun : $(convertto-json $raw_service_request -depth 10 -Compress)"
 
 
Get-WfaLogger -Info -Message "##################### Save payload locally #####################"
$date_now = (Get-Date -Format 'dd-MM-yyyy_hh-mm-ss')
$file_path = "D:\secops_payload\$wfa_job_id-$change_itask-$date_now.txt"
$share_path = \\dbg\lon-gto\NetApp\WFA_Logs\secops_payload\$wfa_job_id-$change_itask-$date_now.txt
$(convertto-json $raw_service_request -depth 10 -Compress) | Out-File $file_path
$(convertto-json $raw_service_request -depth 10 -Compress) | Out-File $share_path
Get-WfaLogger -Info -Message "Saved payload in $file_path and $share_path"
 
 
Get-WfaLogger -Info -Message "##################### ADD RETURN VALUES #####################"
 
Add-WfaWorkflowParameter -Name "snow_cfg" -Value $(convertto-json $snow_cfg -depth 10)
Add-WfaWorkflowParameter -Name "request" -Value $(convertto-json $request -depth 10)
Add-WfaWorkflowParameter -Name "raw_service_request" -Value $($raw_service_request | convertto-json -depth 10 -Compress) -AddAsReturnParameter $True
Add-WfaWorkflowParameter -Name "email_body" -Value $($path['mount_paths'])

