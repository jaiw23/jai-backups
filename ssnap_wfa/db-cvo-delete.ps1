
param (
 
  [parameter(Mandatory=$True)]
  [string]$snow_request_id,
  [parameter(Mandatory=$True, HelpMessage="Existing storage path")]
  [string]$existing_storage_path,
 
  [parameter(Mandatory=$True)]
  [string]$service_level,
 
  [parameter(Mandatory=$True)]
  [string]$service_name,
 
  [parameter(Mandatory=$False)]
  [int]$storage_requirement,
 
  [parameter(Mandatory=$True)]
  [string]$correlation_id,
 
  [parameter(Mandatory=$True)]
  [string]$sys_id,
 
  [parameter(Mandatory=$False, HelpMessage="protocol (NFS|CIFS)")]
  [string]$protocol,
 
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
      [hashtable]$qtrees,
      [parameter(Mandatory=$true)]
      [string]$db_user,
      [parameter(Mandatory=$true)]
      [string]$db_pw
   )
 
   Get-WfaLogger -Info -Message "Entered chargeback function"
   Get-WfaLogger -Info -Message $request['existing_storage_path'].split('/')[2]
   $sql = "
      UPDATE playground.chargeback
      SET storage_requirement_gb = 0
      WHERE 1
         AND cluster_name =   '" + $qtrees['hostname'] + "'
         AND vserver_name =   '" + $qtrees['vserver'] + "'
         AND qtree_name =     '" + $request['existing_storage_path'].split('/')[2] + "'
   ;
   "
   Get-WfaLogger -Info -Message $sql
   Invoke-MySqlQuery -query $sql -user $db_user -password $db_pw
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
 
function update_cvo_chargeback_table(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$volume,
      [parameter(Mandatory=$true)]
      [string]$db_user,
      [parameter(Mandatory=$true)]
      [string]$db_pw
   )
 
   Get-WfaLogger -Info -Message "Entered cvo_chargeback function"
   Get-WfaLogger -Info -Message $request['existing_storage_path'].split('/')[1]
   $sql = "
      UPDATE playground.cvo_chargeback
      SET storage_requirement_gb = 0
      WHERE 1
         AND cluster_name =   '" + $volume['hostname'] + "'
         AND vserver_name =   '" + $volume['vserver'] + "'
         AND volume_name =    '" + $volume['from_name'] + "'
   ;
   "
   Get-WfaLogger -Info -Message $sql
   Invoke-MySqlQuery -query $sql -user $db_user -password $db_pw
 
}
 
function qtree_phase1(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   Get-WfaLogger -Info -Message "Entered qtree_phase1()"
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   ($null, $volume, $qtree) = $tmp.split('/')
 
   $qtrees        = @()
   $return_values = @()
 
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
   Get-WfaLogger -Info -Message "Getting cluster primary address from chargeback"
   $results = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
   Get-WfaLogger -Info -Message $( "results[0]: " + $results[0])
   if ( $results[0] -ne 1 ){
      return @{
         'success'         = $False;
         'reason'          = "Failed to find cluster for provided path: " + $request['existing_storage_path'];
         'return_values'   = $return_values;
         'ontap_qtree'     = $qtrees
      }
   }
   $hostname = $results[1].hostname
   $qtrees += @{
      'hostname'     = $hostname;
      'vserver'      = $vserver;
      'flexvol_name'       = $volume;
      'from_name'    = $qtree;
      'name'         = $qtree + '_to_be_deleted'
   }
 
   $return_values += `
   '__res_type=ontap_qtree;'                                                  + `
   'hostname='          + $hostname                       + ',' + `
   'vserver='           + $vserver                               + ',' + `
   'flexvol_name='            + $volume                               + ',' + `
   'from_name='         + $qtree                               + ',' + `
   'name='              + $qtree + '_to_be_deleted'
 
   return @{
      'success'         = $True;
      'reason'          = "successfully built qtree rename";
      'return_values'   = $return_values;
      'ontap_qtree'     = $qtrees
   }
 
}
 
function cvo_volume_phase1(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   Get-WfaLogger -Info -Message "Entered cvo_volume_phase1()"
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   ($null, $volume, $qtree) = $tmp.split('/')
 
   $vol_obj       = @{}
   $return_values = @()
 
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
   Get-WfaLogger -Info -Message $sql
   Get-WfaLogger -Info -Message "Getting cluster primary address from cvo_chargeback"
   $results = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
   Get-WfaLogger -Info -Message $( "results[0]: " + $results[0])
   if ( $results[0] -ne 1 ){
      return @{
         'success'         = $False;
         'reason'          = "Failed to find cluster for provided path: " + $request['existing_storage_path'];
         'return_values'   = $return_values;
         'ontap_volume'     = $vol_obj
      }
   }
   $hostname = $results[1].hostname
 
   $vol_obj += @{
      'hostname'     = $hostname;
      'vserver'      = $vserver;
      'from_name'    = $volume;
      'name'         = $volume + '_to_be_deleted'
   }
  
   $return_values += `
   '__res_type=cvo_ontap_volume;'                                                  + `
   'hostname='          + $hostname                       + ',' + `
   'vserver='           + $vserver                               + ',' + `
   'from_name='         + $volume                               + ',' + `
   'name='              + $volume + '_to_be_deleted'
 
   return @{
      'success'         = $True;
      'reason'          = "successfully built volume rename";
      'return_values'   = $return_values;
      'ontap_volume'    = $vol_obj
   }
}
 
function qtree_phase2(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   ($null, $volume, $qtree) = $tmp.split('/')
 
   $qtrees        = @()
   $return_values = @()
 
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
 
   $results = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
   if ( $results[0] -ne 1 ){
      return @{
         'success'         = $False;
         'reason'          = "Failed to find cluster for provided path: " + $request['existing_storage_path'];
         'return_values'   = $return_values;
         'ontap_qtree'     = $qtrees
      }
   }
   $hostname = $results[1].hostname
   $qtrees += @{
      'hostname'     = $hostname;
      'vserver'      = $vserver;
      'flexvol_name'       = $volume;
      'name'         = $qtree + '_to_be_deleted'
   }
 
   $return_values += `
   '__res_type=ontap_qtree;'                                                  + `
   'hostname='          + $hostname                       + ',' + `
   'vserver='           + $vserver                               + ',' + `
   'flexvol_name='            + $volume                               + ',' + `
   'name='              + $qtree + '_to_be_deleted'
 
   return @{
      'success'         = $True;
      'reason'          = "successfully deleted qtree";
      'return_values'   = $return_values;
      'ontap_qtree'     = $qtrees
   }
}
 
function cvo_volume_phase2(){
 
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   ($null, $volume, $qtree) = $tmp.split('/')
 
   $vol_obj        = @{}
   $return_values = @()
 
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
   Get-WfaLogger -Info -Message $sql
   $results = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
   if ( $results[0] -ne 1 ){
      return @{
         'success'         = $False;
         'reason'          = "Failed to find cluster for provided path: " + $request['existing_storage_path'];
         'return_values'   = $return_values;
         'ontap_volume'    = $vol_obj
      }
   }
   $hostname = $results[1].hostname
   $vol_obj += @{
      'hostname'     = $hostname;
      'vserver'      = $vserver;
      'name'         = $volume + '_to_be_deleted'
   }
 
   $return_values += `
   '__res_type=cvo_ontap_volume;'                                                  + `
   'hostname='          + $hostname                       + ',' + `
   'vserver='           + $vserver                               + ',' + `
   'name='              + $volume + '_to_be_deleted'
 
   return @{
      'success'         = $True;
      'reason'          = "successfully deleted qtree";
      'return_values'   = $return_values;
      'ontap_volume'    = $vol_obj
   }
 
}
 
function quota() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$True)]
      [array]$qtrees,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   Get-WfaLogger -Info -Message "Entering quota()"
 
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   $vserver       = $qtrees[0]['vserver']
   $volume        = $qtrees[0]['flexvol_name']
   $qtree_name    = $qtrees[0]['name']
   $hostname      = $qtrees[0]['hostname']
   #($null, $volume, $qree) = $tmp.split('/')
 
   $return_values = @()
   $quotas        = @()
 
   Get-WfaLogger -Info -Message $("Removing quota from qtree: " + $qtree_name)
   #---------------------------------------------------------------
   # The policy is set by standard so we specify it there and not
   # here.  Same for the state (absent)
   #---------------------------------------------------------------
   $quotas += @{
      'hostname'     = $hostname;
      'vserver'      = $vserver;
      'volume'       = $volume;
      'quota_target' = '/vol/' + $volume + '/' + $qtree_name;
   }
    Get-WfaLogger -Info -Message $( "Adding return values for qtree: " + $qtree_name)
    $return_values += `
        '__res_type=ontap_quota;'                                                     + `
        'hostname='          + $hostname                              + ',' + `
        'vserver='           + $vserver                               + ',' + `
        'volume='            + $volume                                  + ',' + `
        'quota_target='      + '/vol/' + $volume + '/' + $qtree_name
 
   return @{
      'success'         = $True;
      'reason'          = "successfully built qtree name";
      'return_values'   = $return_values;
      'ontap_quota'     = $quotas
   }
}
 
function nfs_export(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [array]$qtrees,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
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
 
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   $vserver = $qtrees[0]['vserver']
   $volume  = $qtrees[0]['flexvol_name']
   $qtree_name   = $qtrees[0]['name']
   $hostname = $qtrees[0]['hostname']
   $qtree_fields  = $qtree_name.split('_')
 
   $return_values = @()
   $export_policy = @()
 
   $sql = "
    SELECT
      cluster.primary_address     AS 'hostname',
      vserver.name                AS 'vserver.name',
      export_policy.name          AS 'name'
    FROM cm_storage.cluster
    JOIN cm_storage.vserver       ON (vserver.cluster_id = cluster.id)
    JOIN cm_storage.export_policy ON (export_policy.vserver_id = vserver.id)
    WHERE 1
      AND vserver.name  = '$vserver'
      AND export_policy.name = '" + $volume + '_' + $qtree_fields[2] + "'
   ;
   "
 
   $results = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
   if ( $results[0] -eq 0 ){
      return @{
         'success'         = $True;
         'reason'          = "No export policy associated with: " + $request['existing_storage_path'];
         'return_values'   = $return_values;
         'ontap_quota'     = $quotas
      }
   }
   elseif( $results[0] -eq 1 ){
      $export_policy += @{
         'hostname'     = $hostname;
         'vserver'      = $vserver;
         'name'         = $results[1]['name'];
      }
 
      $return_values += `
      '__res_type=ontap_export_policy;'                                          + `
      'hostname='          + $hostname                       + ',' + `
      'vserver='           + $vserver                               + ',' + `
      'name='              + $results[1]['name']
 
      return @{
         'success'         = $True;
         'reason'          = "No export policy associated with: " + $request['existing_storage_path'];
         'return_values'   = $return_values;
         'ontap_quota'     = $quotas
      }
   }
}
 
function cvo_nfs_export(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$vol,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   Get-WfaLogger -Info -Message "Entering cvo_nfs_export()"
   #------------------------------------------------------------
   # I pull the info from the passed path rather than the qtree
   # name because the path always refers to the original qtree
   # name.  The qtree name changes from phase 1 to phase 2 so to
   # be absolutely sure that I always refer to the correct name
   # I use the path.  This ensures that if we move this function
   # to Phase 2, it still works correctly.
   #------------------------------------------------------------
 
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   ($null, $volume, $qtree) = $tmp.split('/')
   $hostname = $vol['hostname']
 
   $return_values = @()
   $cvo_export_policy = @()
   Get-WfaLogger -Info -Message $volume
   $sql = "
    SELECT
      cluster.primary_address     AS 'hostname',
      vserver.name                AS 'vserver.name',
      export_policy.name          AS 'name'
    FROM cm_storage.cluster
    JOIN cm_storage.vserver       ON (vserver.cluster_id = cluster.id)
    JOIN cm_storage.export_policy ON (export_policy.vserver_id = vserver.id)
    WHERE 1
      AND vserver.name  = '$vserver'
      AND export_policy.name = '" + $volume + "'
   ;
   "
   Get-WfaLogger -Info -Message $sql
   $results = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
   if ( $results[0] -eq 0 ){
      return @{
         'success'         = $True;
         'reason'          = "No export policy associated with: " + $request['existing_storage_path'];
         'return_values'   = $return_values;
         'export_policy'   = $cvo_export_policy
      }
   }
   elseif( $results[0] -eq 1 ){
      $cvo_export_policy += @{
         'hostname'     = $hostname;
         'vserver'      = $vserver;
         'name'         = $results[1]['name'];
      }
 
      $return_values += `
      '__res_type=ontap_export_policy;'                                          + `
      'hostname='          + $hostname                       + ',' + `
      'vserver='           + $vserver                               + ',' + `
      'name='              + $results[1]['name']
 
      return @{
         'success'         = $True;
         'reason'          = "No export policy associated with: " + $request['existing_storage_path'];
         'return_values'   = $return_values;
         'ontap_export_policy'     = $cvo_export_policy
      }
   }
}
 
function cifs(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$True)]
      [array]$qtrees,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
   Get-WfaLogger -info -message "Entering cifs()"
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   ($null, $volume, $qtree) = $tmp.split('/')
   $hostname = $qtrees[0]['hostname']
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   ($null, $volume, $qtree_name) = $tmp.split('/')
   $qtree_fields  = $qtree_name.split('_')
   $return_values = @()
   $cifs_share    = @()
 
   Get-WfaLogger -Info -Message "Removing CIFS share"
   $sql = "
    SELECT
      cluster.primary_address     AS 'hostname',
      cifs_share.name             AS 'name'
    FROM cm_storage.cluster
    JOIN cm_storage.vserver       ON (vserver.cluster_id = cluster.id)
    JOIN cm_storage.cifs_share    ON (cifs_share.vserver_id = vserver.id)
    WHERE 1
      AND vserver.name  = '$vserver'
      AND cifs_share.path REGEXP '" + '^/' + $volume + '/' + $qtree_name + "'
   ;
   "
 
   Get-WfaLogger -Info -Message $("sql: " + $sql)
   $results = Invoke-MySqlQuery -query $sql -user 'root' -password $mysql_pw
   #---------------------------------------------------------------
   # The policy is set by standard so we specify it there and not
   # here.  Same for the state (absent)
   #---------------------------------------------------------------
   Get-WfaLogger -Info -Message $("results[0]: " + $results[0])
   if ( $results[0] -eq 0 ){
      Get-WfaLogger -Info -Message "No CIFS shares found"
      return @{
         'success'         = $True;
         'reason'          = "No CIFS share associated with: " + $request['existing_storage_path'];
         'return_values'   = $return_values;
         'ontap_cifs_share'     = $cifs_share
      }
   }
   elseif( $results[0] -eq 1 ){
      Get-WfaLogger -Info -Message "Removing CIFS shares found"
      $return_values += `
      '__res_type=ontap_cifs_share;'                                     + `
      'hostname='          + $results[1]['hostname']               + ',' + `
      'vserver='           + $vserver               + ',' + `
      'share_name='              + $results[1]['name']
 
      return @{
         'success'         = $True;
         'reason'          = "Removing cifs shares";
         'return_values'   = $return_values;
         'ontap_cifs_share'     = $cifs_share
      }
   }
 
}
 
function cvo_cifs(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$True)]
      [hashtable]$vol,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   Get-WfaLogger -info -message "Entering cifs()"
   # $request['path'] is expected to be of the form:
   # vserver:/volume/qtree
   ($vserver, $tmp) = $request['existing_storage_path'].split(':')
   ($null, $volume, $qtree) = $tmp.split('/')
   $hostname = $vol['hostname']
   $return_values = @()
   $cifs_share    = @()
 
   Get-WfaLogger -Info -Message "Removing CIFS share"
   $sql = "
    SELECT
      cluster.primary_address     AS 'hostname',
      cifs_share.name             AS 'name'
    FROM cm_storage.cluster
    JOIN cm_storage.vserver       ON (vserver.cluster_id = cluster.id)
    JOIN cm_storage.cifs_share    ON (cifs_share.vserver_id = vserver.id)
    WHERE 1
      AND vserver.name  = '$vserver'
      AND cifs_share.path REGEXP '" + '^/' + $volume + '$' + "'
   ;
   "
 
   Get-WfaLogger -Info -Message $("sql: " + $sql)
   $results = Invoke-MySqlQuery -query $sql -user 'root' -password $mysql_pw
   #---------------------------------------------------------------
   # The policy is set by standard so we specify it there and not
   # here.  Same for the state (absent)
   #---------------------------------------------------------------
   Get-WfaLogger -Info -Message $("results[0]: " + $results[0])
   Get-WfaLogger -Info -Message $($results[1]|out-string)
   if ( $results[0] -eq 0 ){
      Get-WfaLogger -Info -Message "No CIFS shares found"
      return @{
         'success'         = $True;
         'reason'          = "No CIFS share associated with: " + $request['existing_storage_path'];
         'return_values'   = $return_values;
         'ontap_cifs_share'     = $cifs_share
      }
   }
   elseif( $results[0] -eq 1 ){
      Get-WfaLogger -Info -Message "Removing CIFS shares found"
      $return_values += `
      '__res_type=ontap_cifs_share;'                                     + `
      'hostname='          + $results[1]['hostname']               + ',' + `
      'vserver='           + $vserver               + ',' + `
      'share_name='              + $results[1]['name']
 
      return @{
         'success'         = $True;
         'reason'          = "Removing cifs shares";
         'return_values'   = $return_values;
         'ontap_cifs_share'     = $cifs_share
      }
   }
}
 
function servicenow(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true, HelpMessage="placement solution")]
      [hashtable]$placement_solution
   )
   $return_values = @()
   Get-WfaLogger -Info -Message $( "ServieNow Request Inputs " + $request)
   $qtree   = $placement_solution['resources']['ontap_qtree'][0]  
   if(($request['phase'] -eq 1)){            
         $delete_required = "DELETION REQUIRED: Please Delete the Following Storage - "
         Get-WfaLogger -Info -Message $("DELETE Required Loggig is required")
         Get-WfaLogger -Info -Message $( "Adding DELETING details for " + $qtree['from_name'])
         $delete_required += " Volume: "+ $qtree['flexvol_name'] + " Vserver: "+  $qtree['vserver'] + " Qtree: " + $qtree['name']
         $return_values +=                                              `
            '__res_type=servicenow;'                                    +       `
            'work_notes='        + $delete_required  + ','              + `
            'correlation_id='    + $request['correlation_id']   + ','   + `
            'action='            + 'comment'      + ','                 + `
            'sys_id='            + $request['sys_id']
        
         $return_values +=                                              `
            '__res_type=servicenow;'                                    +       `
            'comment='           + $SERVICENOW_COMMENT_PHASE1  + ','              + `
            'correlation_id='    + $request['correlation_id']   + ','   + `
            'action='            + 'comment'      + ','                 + `
            'sys_id='            + $request['sys_id']
     
   }elseif($request['phase'] -eq 2){
        $return_values +=                                              `
            '__res_type=servicenow;'                                    +       `
            'work_notes='           + $SERVICENOW_COMMENT_PHASE2  + ','              + `
            'correlation_id='    + $request['correlation_id']   + ','   + `
            'action='            + 'completed'      + ','                 + `
            'sys_id='            + $request['sys_id']
   }
 
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
      [hashtable]$placement_solution
   )
 
   $return_values = @()
   Get-WfaLogger -Info -Message $( "ServieNow Request Inputs " + $request)
   $volume   = $placement_solution['resources']['ontap_volume']
   if(($request['phase'] -eq 1)){            
         $delete_required = "DELETION REQUIRED: Please Delete the Following Storage - "
         Get-WfaLogger -Info -Message $("DELETE Required Loggig is required")
         Get-WfaLogger -Info -Message $( "Adding DELETING details for " + $volume['from_name'])
         $delete_required += " Volume: "+ $volume['name'] + "  Vserver: "+  $volume['vserver']
         $return_values +=                                              `
            '__res_type=servicenow;'                                    +       `
            'work_notes='        + $delete_required  + ','              + `
            'correlation_id='    + $request['correlation_id']   + ','   + `
            'action='            + 'comment'      + ','                 + `
            'sys_id='            + $request['sys_id']
        
         $return_values +=                                              `
            '__res_type=servicenow;'                                    +       `
            'comment='           + $SERVICENOW_COMMENT_PHASE1  + ','              + `
            'correlation_id='    + $request['correlation_id']   + ','   + `
            'action='            + 'comment'      + ','                 + `
            'sys_id='            + $request['sys_id']
     
   }elseif($request['phase'] -eq 2){
        $return_values +=                                              `
            '__res_type=servicenow;'                                    +       `
            'work_notes='           + $SERVICENOW_COMMENT_PHASE2  + ','              + `
            'correlation_id='    + $request['correlation_id']   + ','   + `
            'action='            + 'completed'      + ','                 + `
            'sys_id='            + $request['sys_id']
   }
 
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
$SERVICENOW_COMMENT_PHASE1 = "Your $service_level request is now fully complete and access has been removed to your storage as requested. The storage will be completely deleted in 14 days."
$SERVICENOW_COMMENT_PHASE2  = "Your $service_level request is now fully complete and storage deleted as requested"
$CVO                = 'CVO'
 
########################################################################
# MAIN
########################################################################
Get-WfaLogger -Info -Message "##################### PRELIMINARIES #####################"
Get-WfaLogger -Info -Message "Get DB Passwords"
$playground_pass  = Get-WFAUserPassword -pw2get "WFAUSER"
$mysql_pass       = Get-WFAUserPassword -pw2get "MySQL"
 
#---------------------------------------------------------------
# GSSC-601 : Special case where NFS version is passed as v3/v4
#---------------------------------------------------------------
if($protocol.ToLower() -eq "nfsv3"){
   $protocol_version = "nfs3"
   $protocol_type = "nfs"
}
elseif($protocol.ToLower() -eq "nfsv4"){
   $protocol_version = "nfs4"
   $protocol_type = "nfs"
}
elseif($protocol.ToLower() -eq "smb"){
   $protocol_version = "smb"
   $protocol_type = "smb"
}
 
$request = @{
   'snow_request_id'          = $snow_request_id;
   'existing_storage_path'    = $existing_storage_path;
   'phase'                    = $phase;
   'service_level'            = $service_level;
   'service_name'             = $service_name;
   'correlation_id'           = $correlation_id;
   'sys_id'                   = $sys_id;
   'protocol'                 = $protocol_type;
 
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
   'operation'       = '';
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
if ( $request['phase'] -eq 1 ){
 
   if( $request['service_level'] -ne $CVO ){
 
      $placement_solution['operation']  = 'offline'
     
      Get-WfaLogger -Info -Message "##################### QTREE PHASE 1 #####################"
      $qtree = qtree_phase1  `
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
      $placement_solution['resources']['ontap_qtree'] = $qtree['ontap_qtree']
      $placement_solution['return_values'] += $qtree['return_values']
  
   }
 
   elseif( $request['service_level'] -eq $CVO ){
 
      $placement_solution['operation']  = 'offline'
     
      Get-WfaLogger -Info -Message "##################### VOLUME PHASE 1 #####################"
      $volume = cvo_volume_phase1  `
         -request    $request                      `
         -mysql_pw   $mysql_pass
      if ( -not $volume['success'] ){
         $fail_msg = $qtree['reason']
         Get-WfaLogger -Info -Message $fail_msg
         $placement_solution['success']   = 'FALSE'
         $placement_solution['reason']    = $fail_msg
         set_wfa_return_values $placement_solution
         exit
      }
      $placement_solution['resources']['ontap_volume'] = $volume['ontap_volume']
      $placement_solution['return_values'] += $volume['return_values']        
      Get-WfaLogger -Info -Message $($placement_solution|out-string)
      }
 
}
elseif( $request['phase'] -eq 2 ){
 
   if( $request['service_level'] -ne $CVO ){
 
      $placement_solution['operation']  = 'delete'
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
      $placement_solution['resources']['ontap_qtree'] = $qtree['ontap_qtree']
      $placement_solution['return_values'] += $qtree['return_values']
  
   }
 
   elseif( $request['service_level'] -eq $CVO ){
 
      $placement_solution['operation']  = 'delete'
      Get-WfaLogger -Info -Message "##################### VOLUME PHASE 2 #####################"
      $volume = cvo_volume_phase2  `
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
   }
}
else{
   $fail_msg = "Invalid phase passed: " + $request['phase']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
 
if ( $request['phase'] -eq 1 ){
   if( $request['service_level'] -ne $CVO ){
   Get-WfaLogger -Info -Message "##################### QUOTA RULE #####################"
   $quota = quota  `
      -request    $request                      `
      -qtrees     $qtree['ontap_qtree']       `
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
   }
}
if ( ($request['phase'] -eq 2) -and ($request['service_name'].ToLower() -ne 'fabric') -and ($request['protocol'] -eq 'nfs') ){
   if( $request['service_level'] -ne $CVO ){
   Get-WfaLogger -Info -Message "##################### NFS EXPORT #####################"
   $nfs = nfs_export  `
      -request    $request                      `                     `
      -qtrees     $qtree['ontap_qtree']       `
      -mysql_pw   $mysql_pass
   if ( -not $nfs['success'] ){
      $fail_msg = $nfs['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
   $placement_solution['resources']['ontap_export_policy'] = $nfs['ontap_export_policy']
   $placement_solution['return_values'] += $nfs['return_values']
   }
}
if ( $request['phase'] -eq 2 -and ($request['protocol'] -eq 'smb')){
   if( $request['service_level'] -ne $CVO ){
   Get-WfaLogger -Info -Message "##################### CIFS #####################"
   $cifs = cifs  `                     `
      -qtrees     $qtree['ontap_qtree']       `
      -request    $request                      `
      -mysql_pw   $mysql_pass
   if ( -not $cifs['success'] ){
      $fail_msg = $cifs['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
   $placement_solution['resources']['ontap_cifs_share'] = $cifs['ontap_cifs_share']
   $placement_solution['return_values'] += $cifs['return_values']
   }
}
 
if ( $request['phase'] -eq 2 ){
if ( $request['service_level'] -eq $CVO -and ($request['protocol'] -eq 'nfs' )){
   Get-WfaLogger -Info -Message "##################### CVO NFS EXPORT #####################"
   $nfs = cvo_nfs_export  `
      -request    $request                      `
      -vol        $volume['ontap_volume']       `
      -mysql_pw   $mysql_pass
   if ( -not $nfs['success'] ){
      $fail_msg = $nfs['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
   Get-WfaLogger -Info -Message $($nfs|out-string)
   $placement_solution['resources']['ontap_export_policy'] = $nfs['ontap_export_policy']
   $placement_solution['return_values'] += $nfs['return_values']
}
}
 
if ( $request['phase'] -eq 2 -and ($request['protocol'] -eq 'smb') ){
if ( $request['service_level'] -eq $CVO ){
   Get-WfaLogger -Info -Message "##################### CVO CIFS #####################"
   $cifs = cvo_cifs  `                     `
      -vol        $volume['ontap_volume']       `
      -request    $request                      `
      -mysql_pw   $mysql_pass
   if ( -not $cifs['success'] ){
      $fail_msg = $nfs['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
   $placement_solution['resources']['ontap_cifs_share'] = $cifs['ontap_cifs_share']
   $placement_solution['return_values'] += $cifs['return_values']
}
}
 
if ( $request['service_level'] -ne $CVO ){
Get-WfaLogger -Info -Message "##################### SET SERVICE NOW #####################"
   $snow = servicenow `
      -request $request      `
      -placement_solution   $placement_solution    
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
 
if ( $request['service_level'] -eq $CVO ){
Get-WfaLogger -Info -Message "##################### SET CVO SERVICE NOW #####################"
   $snow = cvo_servicenow `
      -request $request      `
      -placement_solution   $placement_solution    
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
if ( $request['service_level'] -ne $CVO ){
   update_chargeback_table `
      -qtrees $qtree['ontap_qtree'][0] `
      -request $request `
      -db_user 'root' `
      -db_pw $mysql_pass
}
 
if ( $request['service_level'] -eq $CVO ){
   update_cvo_chargeback_table `
      -volume $volume['ontap_volume'] `
      -request $request `
      -db_user 'root' `
      -db_pw $mysql_pass
}
 
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
 
Get-WfaLogger -Info -Message "##################### RETURN VALUES #####################"
set_wfa_return_values -placement_solution $placement_solution
 
