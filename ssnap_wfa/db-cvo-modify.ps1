param (
 
  [parameter(Mandatory=$True)]
  [string]$snow_request_id,
 
  [parameter(Mandatory=$True, HelpMessage="Existing storage path")]
  [string]$existing_storage_path,
 
  [parameter(Mandatory=$True)]
  [string]$service_level,
 
  [parameter(Mandatory=$True)]
  [string]$service_name,
 
  [parameter(Mandatory=$True)]
  [int]$storage_requirement,
 
  [parameter(Mandatory=$True)]
  [string]$correlation_id,
 
  [parameter(Mandatory=$True)]
  [string]$sys_id
 
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
   Add-WfaWorkflowParameter -Name 'raw_req_003' -Value $("__res_type='';operation=" + 'update') -AddAsReturnParameter $True
 
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
      [hashtable]$quota,
      [parameter(Mandatory=$true)]
      [string]$db_user,
      [parameter(Mandatory=$true)]
      [string]$db_pw
   )
 
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   ($null, $volume, $qtree) = $tmp.split('/')
   Get-WfaLogger -Info -Message "Entered update_chargeback_table()"
 
   $sql = "
      SELECT
         cluster_primary_address AS hostname,
         storage_requirement_gb  AS storage_requirement_gb
      FROM playground.chargeback
      WHERE 1
         AND vserver_name  = '${vserver}'
         AND volume_name   = '${volume}'
         AND qtree_name    = '${qtree}'
   ;
   "
   Get-WfaLogger -Info -Message $("Execute SQL: " + $sql)
   $results = Invoke-MySqlQuery -query $sql -user root -password $db_pw
   Get-WfaLogger -Info -Message "Checking if storage path already exists in chargeback table"
   Get-WfaLogger -Info -Message $("results[0]: " + $results[0])
   if ( $results[0] -eq 0 ){
      $msg = "Unable to find path in chargeback table: " + $request['existing_storage_path']
      Get-WfaLogger -Info -Message $msg   
      }
     
    else { 
 
   $sql = "
      UPDATE playground.chargeback
      SET storage_requirement_gb = " + $quota['new_size'] + "
      WHERE 1
         AND cluster_name =   '" + $quota['hostname'] + "'
         AND vserver_name =   '" + $quota['vserver'] + "'
         AND qtree_name =     '" + $request['existing_storage_path'].split('/')[2] + "'
   ;
   "
   Get-WfaLogger -Info -Message $sql
   Invoke-MySqlQuery -query $sql -user $db_user -password $db_pw
   Get-WfaLogger -Info -Message "Chargeback table updated"
   }
 
}
 
function update_cvo_chargeback_table(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$db_user,
      [parameter(Mandatory=$true)]
      [string]$db_pw
   )
 
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   ($null, $volume, $qtree) = $tmp.split('/')
   Get-WfaLogger -Info -Message "Entered update_cvo_chargeback_table()"
 
   $sql = "
      SELECT
         cluster_primary_address AS hostname,
         storage_requirement_gb  AS storage_requirement_gb
      FROM playground.cvo_chargeback
      WHERE 1
         AND vserver_name  = '${vserver}'
         AND volume_name   = '${volume}'
   ;
   "
   Get-WfaLogger -Info -Message $("Execute SQL: " + $sql)
   $results = Invoke-MySqlQuery -query $sql -user root -password $db_pw
   Get-WfaLogger -Info -Message "Checking if storage path already exists in chargeback table"
   Get-WfaLogger -Info -Message $("results[0]: " + $results[0])
   if ( $results[0] -eq 0 ){
      $msg = "Unable to find path in chargeback table: " + $request['existing_storage_path']
      Get-WfaLogger -Info -Message $msg   
      }
     
   else { 
 
   $sql = "
      UPDATE playground.cvo_chargeback
      SET storage_requirement_gb = " + $volume['size'] + "
      WHERE 1
         AND cluster_name =   '" + $volume['hostname'] + "'
         AND vserver_name =   '" + $volume['vserver'] + "'
   ;
   "
   Get-WfaLogger -Info -Message $sql
   #Invoke-MySqlQuery -query $sql -user $db_user -password $db_pw
   Get-WfaLogger -Info -Message "CVO Chargeback table updated"
   }
 
}
#-----------------------------------------------------------------------
# STORAGE RESOURCE FUNCTIONS
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# These items are not specifically returned by WFA as part of the
# request, but are used to build other storage resources that are
# returned as part of the request.  Therefore, we are only defining
# the objects themselves and not return values.
#-----------------------------------------------------------------------
 
function quota() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   Get-WfaLogger -Info -Message "Entered quota()"
 
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   Get-WfaLogger -Info -Message $("existing_storarge_path: " + $request['existing_storage_path'])
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   ($null, $volume, $qtree) = $tmp.split('/')
   Get-WfaLogger -Info -Message $("vserver: " + $vserver)
   Get-WfaLogger -Info -Message $("tmp: " + $tmp)
   $return_values = @()
   $quotas = @()  
   $sql = "
      SELECT
         quota_rule.cluster AS hostname,
         (quota_rule.disk_limit)/1024/1024  AS storage_requirement_gb
      FROM cm_storage_quota.quota_rule
      WHERE 1
         AND quota_rule.vserver_name  = '${vserver}'
         AND quota_rule.quota_volume  = '${volume}'
         AND quota_target             = '/vol/${volume}/${qtree}'
   ;
   "
   Get-WfaLogger -Info -Message $("Execute SQL: " + $sql)
   $results = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
   Get-WfaLogger -Info -Message $("results[0]: " + $results[0])
   if ( $results[0] -eq 0 ){
      $msg = "Unable to find path in quota table: " + $request['existing_storage_path']
      Get-WfaLogger -Info -Message $msg
      return @{
         'success'         = $False;
         'reason'          = $msg;
         'return_values'   = $return_values;
         'ontap_quota'     = $quotas
      }
   }
   # elseif ( $requests[0] -gt 1 ){
   #    $msg = "Found multiple matching entries in chargeback table for path:" + $request['existing_storage_path']
   #    Get-WfaLogger -Info -Message $msg
   #    return @{
   #       'success'         = $False;
   #       'reason'          = $msg;
   #       'return_values'   = $return_values;
   #       'ontap_quota'     = $quotas
   #    }
   # }
 
   Get-WfaLogger -Info -Message "Modifying qtree quota"
   Get-WfaLogger -Info -Message "Existing Quota Size in GB:"
   Get-WfaLogger -Info -Message $($results[1]['storage_requirement_gb']|Out-String)
 
   $new_quota = [int]$results[1]['storage_requirement_gb'] + $request['storage_requirement']
 
   Get-WfaLogger -Info -Message $( "Modifying quota for path: " + $request['existing_storage_path'] )
   $quotas += @{
      'hostname'     = $results[1]['hostname'];
      'vserver'      = $vserver;
      'volume'       = $volume;
      'quota_target' = '/vol/' + $volume + '/' + $qtree;
      'disk_limit'   = [string]$new_quota + $STORAGE_REQUIREMENT_UNITS
      'new_size'     = [string]$new_quota
   }
   $return_values += `
      '__res_type=ontap_quota;'                                                     + `
      'hostname='          + $results[1]['hostname']                              + ',' + `
      'vserver='           + $vserver                               + ',' + `
      'volume='            + $volume                                  + ',' + `
      'quota_target='      + '/vol/' + $volume + '/' + $qtree + ',' + `
      'disk_limit='        + [string]$new_quota + $STORAGE_REQUIREMENT_UNITS
 
   return @{
      'success'         = $True;
      'reason'          = "successfully built qtree name";
      'return_values'   = $return_values;
      'ontap_quota'     = $quotas
   }
}
 
function volume(){
  param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
      )
 
   Get-WfaLogger -Info -Message "Entered volume()"
 
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   Get-WfaLogger -Info -Message $("existing_storarge_path: " + $request['existing_storage_path'])
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   $vserver = $vserver.split('.')[0]
   ($null, $volume, $qtree) = $tmp.split('/')
   Get-WfaLogger -Info -Message $("vserver: " + $vserver)
   Get-WfaLogger -Info -Message $("tmp: " + $tmp)
   $return_values = @()
   $vol_obj = @{}  
   $sql = "
      SELECT
         cm_storage.cluster.primary_address AS hostname,
         sum(cm_storage.volume.size_mb)/1024/1024  AS total_allocated_tb,
         count(cm_storage.volume.name) AS total_volume_count,
         cm_storage.volume.size_mb/1024 AS storage_requirement_gb
      FROM cm_storage.cluster
      JOIN cm_storage.vserver on vserver.cluster_id = cluster.id
      JOIN cm_storage.volume on volume.vserver_id = vserver.id
      WHERE 1
         AND cluster.name = (
            select
               cm_storage.cluster.name
               FROM cm_storage.cluster
               JOIN cm_storage.vserver ON vserver.cluster_id = cluster.id
               WHERE vserver.name = '${vserver}')
         AND volume.name = '${volume}'
   ;
   "
   Get-WfaLogger -Info -Message $("Execute SQL: " + $sql)
   $results = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
   Get-WfaLogger -Info -Message $("results[0]: " + $results[0])
   if ( $results[0] -eq 0 ){
      $msg = "Unable to find path in volume table: " + $request['existing_storage_path']
      Get-WfaLogger -Info -Message $msg
      return @{
         'success'         = $False;
         'reason'          = $msg;
         'return_values'   = $return_values;
      }
   }
   elseif ( $results[1]['total_allocated_tb'] -ge $CVO_TOTAL_ALLOCATION_TB ){
      $msg = "Maximum allocation limit for CVO reached:" + $requests[1]['total_allocated_tb']
      Get-WfaLogger -Info -Message $msg
      return @{
         'success'         = $False;
         'reason'          = $msg;
         'return_values'   = $return_values;
         'ontap_volume'    = $vol_obj
      }
   }
 
   Get-WfaLogger -Info -Message "Modifying volume"
 
   $new_quota = [int]$results[1]['storage_requirement_gb'] + $request['storage_requirement']
 
   Get-WfaLogger -Info -Message $( "Modifying volume size for path: " + $request['existing_storage_path'] )
   $vol_obj += @{
      'hostname'     = $results[1]['hostname'];
      'vserver'      = $vserver;
      'name'         = $volume;
      'size'         = [string]$new_quota;
      'size_unit'    = 'gb'
   }
   $return_values += `
      '__res_type=cvo_ontap_volume;'                                + `
      'hostname='          + $results[1]['hostname']                + ',' + `
      'vserver='           + $vserver                               + ',' + `
      'name='              + $volume                                + ',' + `
      'size='              + [string]$new_quota                     + ',' + `
      'size_unit='         + 'gb'
 
   return @{
      'success'         = $True;
      'reason'          = "successfully set volume size";
      'return_values'   = $return_values;
      'ontap_volume'    = $vol_obj
   }
 
}
 
function servicenow(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true, HelpMessage="placement solution")]
      [hashtable]$quota
   )
   $return_values = @()
   $backup_required = $False
   $volume  = $quota['volume']
   $vserver   = $quota['vserver']
   Get-WfaLogger -Info -Message $volume
   $comment = $SERVICENOW_COMMENT
   $comment += $quota['disk_limit']
   $return_values +=                                              `
         '__res_type=servicenow;'                                    +       `
         'comment='           + $comment  + ','              + `
         'correlation_id='    + $request['correlation_id']   + ','   + `
         'action='            + 'completed'      + ','                 + `
         'sys_id='            + $request['sys_id']
   $return_values +=                                              `
         '__res_type=servicenow;'                                    +       `
         'correlation_id='    + $request['correlation_id']   + ','   + `
         'action='            + 'logging'      + ','                 + `
         'sys_id='            + $request['sys_id']
 
   $snow = @{
      'success'         = $True;
      'reason'          = "Connecting to ServiceNow";
      'return_values'   = $return_values
   }  
   return $snow
}
 
function cvo_servicenow(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true, HelpMessage="placement solution")]
      [hashtable]$vol
   )
   $return_values = @()
   $backup_required = $False
   $volume  = $vol['name']
   $vserver   = $vol['vserver']
   Get-WfaLogger -Info -Message $volume
   $comment = $SERVICENOW_COMMENT
   $comment += $vol['size']
   $comment += ' GB'
   $return_values +=                                              `
         '__res_type=servicenow;'                                    +       `
         'comment='           + $comment  + ','              + `
         'correlation_id='    + $request['correlation_id']   + ','   + `
         'action='            + 'completed'      + ','                 + `
         'sys_id='            + $request['sys_id']
   $return_values +=                                              `
         '__res_type=servicenow;'                                    +       `
         'correlation_id='    + $request['correlation_id']   + ','   + `
         'action='            + 'logging'      + ','                 + `
         'sys_id='            + $request['sys_id']
 
   $snow = @{
      'success'         = $True;
      'reason'          = "Connecting to ServiceNow";
      'return_values'   = $return_values
   }  
   return $snow
}
########################################################################
# VARIABLES & CONSTANTS
########################################################################
 
$STORAGE_REQUIREMENT_UNITS = 'GB'
 
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
   };
   'NAS Shared'    = @{
      'FSU' = @{
         'prefix'    = 'c';
         'service'   = 'nas_shared_fsu';
         'std_name'  = 'nas_shared'
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
   'CVO'    = @{
      'platform_code' = @{
         'rehost' = 'rh';
         'native' = 'nt'
      }
      'CVO-Premium' = @{
         'prefix'    = 'pr';
         'service'   = 'cvo_premium'
         'std_name'  = 'cvo'
      };
      'CVO-Standard' = @{
         'prefix'    = 'st';
         'service'   = 'cvo_standard';
         'std_name'  = 'cvo'
      };
      'CVO-Basic' = @{
         'prefix'    = 'bs';
         'service'   = 'cvo_basic';
         'std_name'  = 'cvo'
   }
}
}
 
$GFS                = 'gfs'
$FABRIC             = 'fabric'
$FSU                = 'fsu'
$VFS                = 'vfs'
$EDISCOVERY         = 'ediscovery'
$CVO                = 'CVO'
$PROD               = 'prd'
$NFS                = 'nfs'
$SMB                = 'smb'
$SERVICENOW_COMMENT = "Your "+$service_name+" modify request has been completed. New size for share is : "
$CVO_TOTAL_ALLOCATION_TB = 300
########################################################################
# MAIN
########################################################################
Get-WfaLogger -Info -Message "##################### PRELIMINARIES #####################"
Get-WfaLogger -Info -Message "Get DB Passwords"
$playground_pass  = Get-WFAUserPassword -pw2get "WFAUSER"
$mysql_pass       = Get-WFAUserPassword -pw2get "MySQL"
 
$request = @{
   'snow_request_id'          = $snow_request_id;
   'existing_storage_path'    = $existing_storage_path;
   'storage_requirement'      = $storage_requirement;
   'service_level'                 = $service_level;
   'service_name'                  = $service_name;
   'correlation_id'                = $correlation_id;
   'sys_id'                        = $sys_id;
 
}
#---------------------------------------------------------------
# The placement solution maintains both the return values and
# what amounts to an object definition.  The return values are
# taken unchanged and passed as WFA workflow return values.
# The objects are maintained because some are used in order to
# fully define other objects.
#---------------------------------------------------------------
 
$wfa_job_id = Get-WfaRestParameter -Name jobId
$sql = "
  SELECT
    snow_request_id   AS 'snow_request_id',
    wfa_job_id        AS 'wfa_job_id',
    lock_state        AS 'lock_state',
    start_time        AS 'start_time',
    last_activity     AS 'last_activity'
  FROM playground.lock
  WHERE 1
    AND snow_request_id = '$snow_request_id'
    AND wfa_job_id = '$wfa_job_id'
  ORDER BY start_time ASC;
"
$result = Invoke-MySqlQuery -Query $sql -user 'root' -password $mysql_pass
if ( $result[0] -ne 1 ){
   $fail_msg = 'Unable to obtain required workflow lock'
   Get-WfaLogger -Info -Message $($fail_msg)
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
elseif ( $result[1].lock_state -ne 'active' ){
   $fail_msg = 'Timed out trying to acquire execution lock'
   Get-WfaLogger -Info -Message $($fail_msg)
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
 
$placement_solution = @{
   'success'         = 'TRUE';
   'reason'          = 'successfully determined a placement solution';
   'std_name'        = '';
   'service'         = '';
   'resources'       = @{};
   'return_values'   = @();
}
 
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
 
$placement_solution['service']  = $service_data[$service_name]['service']
$placement_solution['std_name']  = $service_data[$service_name]['std_name']
 
if( $request['service_level'] -ne $CVO ){
 
Get-WfaLogger -Info -Message "##################### QUOTA RULE #####################"
$quota = quota                               `
   -request    $request                      `
   -mysql_pw   $mysql_pass
if ( -not $quota['success'] ){
   $fail_msg = $quota['reason']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
$placement_solution['resources']['ontap_quota'] = $quota['ontap_quota']
$placement_solution['return_values'] += $quota['return_values']
 
#---------------------------------------------------------------
# Everything was successful so consolidate and finish up
#---------------------------------------------------------------
#---------------------------------------------------------------
# FIXME: RTU 15 Oct 2020
# NETAPP-70
# update the chargeback table
# Update our lock record to complete if it's still showing
# active.
# Check that it is now complete.
# If it's not complete,
#     set success to FAIL
#     reason to lock expired
# set return values
#---------------------------------------------------------------
Get-WfaLogger -Info -Message "##################### CHARGEBACK TABLE #####################"
update_chargeback_table `
   -quota $quota['ontap_quota'][0] `
   -request $request `
   -db_user 'root' `
   -db_pw $mysql_pass
 
$lock_date = Get-Date -f 'yyyy-MM-dd HH:mm:ss'
$sql = "
   LOCK TABLES playground.lock WRITE;
   UPDATE playground.lock SET lock_state = 'released', last_activity = '$lock_date';
   UNLOCK TABLES;
"
$result = Invoke-MySqlQuery -Query $sql -user 'root' -password $mysql_pass
 
if ( $result[1].lock_state -eq 'timedout' ){
   $fail_msg = 'Failed to release execution lock'
   Get-WfaLogger -Info -Message $($fail_msg)
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
 
Get-WfaLogger -Info -Message "##################### SET SERVICE NOW #####################"
   $snow = servicenow `
      -request $request      `
      -quota   $quota['ontap_quota'][0]    
   if ( -not $snow['success'] ){
      $fail_msg = $snow['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
 
   $placement_solution['return_values'] += $snow['return_values']
 
}
 
elseif( $request['service_level'] -eq $CVO ){
 
Get-WfaLogger -Info -Message "##################### CVO VOLUME SIZE MODIFY #####################"
$volume = volume                               `
   -request    $request                      `
   -mysql_pw   $mysql_pass
if ( -not $volume['success'] ){
   $fail_msg = $volume['reason']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
$placement_solution['resources']['ontap_volume'] = $volume['ontap_volume']
$placement_solution['return_values'] += $volume['return_values']
 
Get-WfaLogger -Info -Message "##################### SET SERVICE NOW #####################"
   $snow = cvo_servicenow `
      -request $request      `
      -vol   $volume['ontap_volume']   
   if ( -not $snow['success'] ){
      $fail_msg = $snow['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
 
   $placement_solution['return_values'] += $snow['return_values']
 
Get-WfaLogger -Info -Message "##################### CVO CHARGEBACK TABLE #####################"
update_cvo_chargeback_table `
   -request $request `
   -db_user 'root' `
   -db_pw $mysql_pass
 
$lock_date = Get-Date -f 'yyyy-MM-dd HH:mm:ss'
$sql = "
   LOCK TABLES playground.lock WRITE;
   UPDATE playground.lock SET lock_state = 'released', last_activity = '$lock_date';
   UNLOCK TABLES;
"
$result = Invoke-MySqlQuery -Query $sql -user 'root' -password $mysql_pass
 
if ( $result[1].lock_state -eq 'timedout' ){
   $fail_msg = 'Failed to release execution lock'
   Get-WfaLogger -Info -Message $($fail_msg)
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
 
 
}
 
Get-WfaLogger -Info -Message "##################### RETURN VALUES #####################"
set_wfa_return_values -placement_solution $placement_solution

