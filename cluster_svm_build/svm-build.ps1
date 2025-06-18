


param(
  [parameter(Mandatory=$True)]
  [string]$cluster_name,
  [parameter(Mandatory=$True)]
  [string]$svm_name,
  [parameter(Mandatory=$true)]
  [string]$service,
  [parameter(Mandatory=$True)]
  [string]$service_name,
  [parameter(Mandatory=$True)]
  [string]$environment,
  [parameter(Mandatory=$True)]
  [string]$data_ip_list,
  [parameter(Mandatory=$False)]
  [string]$backup_ip_list,
  [parameter(Mandatory=$False)]
  [string]$route_list,
  [parameter(Mandatory=$True)]
  [string]$RITM,
  [parameter(Mandatory=$True)]
  [string]$sys_id,
  [parameter(Mandatory=$True)]
  [string]$rest_host,
  [parameter(Mandatory=$True)]
  [string]$svm_node
)
########################################################################
# FUNCTIONS
########################################################################
#-----------------------------------------------------------------------
# UTILITY FUNCTIONS
#-----------------------------------------------------------------------
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
 
function submit_request() {
  param(
    [parameter(Mandatory=$True)]
    [hashtable]$raw_service_request,
    [parameter(Mandatory=$True)]
    [hashtable]$rest_cfg
  )
 
  #--------------------------------------------------------
  # REST API call to submit the request
  #--------------------------------------------------------
  [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} ;
  $result = Invoke-WebRequest -uri $($rest_cfg['host'] + '/api/v1/nas_provisioning/svm')`
            -Method POST `
            -body $( ConvertTo-Json @{"raw_service_request" = $raw_service_request} -Depth 10 )  `
            -Headers @{ "Content-Type" = "application/json" }
  if ( $result.StatusCode -ne 201 ){
    Get-WfaLogger -Info -Message "Status code not 201"
    Get-WfaLogger -Info -Message $($result.StatusDescription)
    Throw $result.StatusDescription
  }
  Get-WfaLogger -Info -Message "Request successfully submitted"
}
 
function get_cluster_cfg(){
  param(
    [parameter(Mandatory=$true)]
    [hashtable]$request,
    [parameter(Mandatory=$True)]
    [string]$mysql_pw
  )
  get-wfalogger -info -message $($request['cluster_name'])
  $sql = "
    SELECT
      cluster.name                AS 'cluster_name',
      cluster.primary_address     AS 'cluster_primary_address',
      cluster.version             AS 'cluster_version',
      cluster.uuid                AS 'cluster_uuid',
      cluster.serial_number       AS 'cluster_sn',
      node.name                   AS 'node_name',
      node.model                  AS 'node_model',
      aggregate.name              AS 'aggr_name',
      aggregate.available_size_mb AS 'aggr_available_size_mb'
    FROM cm_storage.cluster
    JOIN cm_storage.node      ON (node.cluster_id = cluster.id)
    JOIN cm_storage.aggregate ON (aggregate.node_id = node.id)
    WHERE 1 = 1
      AND (
        cluster.name = '" + $request['cluster_name'] + "'
        OR
        cluster.primary_address = '" + $request['cluster_name'] + "'
      )
      AND node.name = '" + $request['svm_node'] + "'
      AND NOT aggregate.has_local_root
      AND NOT aggregate.has_partner_root
      AND NOT aggregate.name LIKE 'aggr0%'
    ORDER BY aggregate.available_size_mb DESC
    ;
  "
  get-wfalogger -info -message $sql
  $cfg = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
  get-wfalogger -info -message $($cfg | Out-String)
  if ( $cfg[0] -eq 0 ){
    return @{
      'success'   = $false;
      'reason'    = "Unable to find matching cluster"
    }
  }
  #---------------------------------------------------------------
  # Not all of the fields we track are currently used but I thought
  # they may be useful at some point so I added them.
  #---------------------------------------------------------------
  $cluster_cfg = @{
    'success'   = $True;
    'reason'    = "Success";
    'base'   = @{
      'name'        = $cfg[1].cluster_name;
      'mgmt_ip'     = $cfg[1].cluster_primary_address;
      'model'       = $cfg[1].node_model;
      'version'     = $cfg[1].cluster_version;
      'uuid'        = $cfg[1].cluster_uuid;
      'sn'          = $cfg[1].cluster_sn;
      'node_names'  = @();
      'nodes'       = @();
      'aggrs'       = @();
    }
  }
  #---------------------------------------------------------------
  # Since we use a query in the UI to present possible clusters
  # we don't need to check for an empty return here.
  #---------------------------------------------------------------
  $node_by_name = @{}
  foreach ($cfg_item in $cfg[-($cfg.Count-1) .. -1]){
    if ( -not $node_by_name.ContainsKey($cfg_item['node_name']) ){
      $node = @{
        'name'          = $cfg_item['node_name'];
        'model'         = $cfg_item['node_model'];
      }
      $cluster_cfg['base']['nodes']                += $node
      $cluster_cfg['base']['node_names']           += $cfg_item['node_name']
      $node_by_name[$cfg_item['node_name']] = 1
    }
 
    $aggr = @{
      'name'              = $cfg_item['aggr_name'];
      'available_size_mb' = $cfg_item['aggr_available_size_mb'];
      'node_name'         = $cfg_item['node_name'];
    }
    $cluster_cfg['base']['aggrs']   += $aggr
  }
 
  return $cluster_cfg
}
 
function ontap_vserver(){
  param(
    [parameter(Mandatory=$true)]
    [hashtable]$request,
    [parameter(Mandatory=$True)]
    [hashtable]$cluster_cfg,
    [parameter(Mandatory=$True)]
    [string]$mysql_pw
  )
 
  #------------------------------------------------------------------
  # Grab the base SVM cfg
  #------------------------------------------------------------------
  $sql = "
    SELECT *
    FROM db_cfg.svm_base
    WHERE 1 = 1
      AND service = '" + $request['service'] + "'
      AND service_name  = '" + $request['service_name'] + "'
      AND environment = '" + $request['environment'] + "'
    ;
  "
  get-wfalogger -info -message $sql
  $svm_cfg = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
  if ( $svm_cfg[0] -eq 0 ){
    return @{
      'success'   = $False
      'reason'    = "Unable to find matching SVM cfg for request"
    }
  }
  elseif( $svm_cfg[0] -ne 1 ){
    if ( $svm_cfg[0] -gt 1 ){
      $reason = "Found >1 matching entry for request"
    }
    else{
      $reason = "Found no matching entry for request"
    }
    return @{
      'success'   = $False
      'reason'    = $reason
    }
  }
 
  #------------------------------------------------------------------
  # Define the return value
  #------------------------------------------------------------------
  $return_ontap_vserver = @{
    'success'           = $true;
    'reason'            = "Success";
    'ontap_vserver'     = @()
  }
  $tmp = @{
      'name'                  = $request['svm_name'];
      'ipspace'               = $svm_cfg[1].ipspace;
      'allowed_protocols'     = $svm_cfg[1].allowed_protocols;
      'root_volume'           = $svm_cfg[1].root_vol_name -replace '^%svm%', $request['svm_name'];
      'root_volume_aggregate' = $cluster_cfg['base']['aggrs'][0]['name'];
      'language'              = $svm_cfg[1].root_vol_language;
      'security_style'        = $svm_cfg[1].root_vol_security_style;
      'hostname'              = $cluster_cfg['base']['mgmt_ip'];
  }
 
  $return_ontap_vserver['ontap_vserver'] += $tmp
 
  return $return_ontap_vserver
}
#-----------------------------------------------------------------------
# STORAGE RESOURCE FUNCTIONS
#-----------------------------------------------------------------------
 
function ontap_export_policy() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,    
     [parameter(Mandatory=$True)]
     [string]$mysql_pw
  )
 
  $sql = "
    SELECT *
    FROM db_cfg.svm_export_policy
    WHERE 1 = 1
      AND service = '" + $request['service'] + "'
      AND service_name  = '" + $request['service_name'] + "'
      AND environment REGEXP '" + $request['environment'] + "|ALL'
  ;
  "
 
  $sql_data = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  if($sql_data[0] -ge 1){
  $ontap_export_policy = @{
    'success'     = $True;
    'reason'      = 'success';
    'ontap_export_policy' = @();
  }
  foreach ( $export_policy in $sql_data[-($sql_data.Count-1) .. -1]){
    $new_policy = @{
      'hostname'    = $cluster_cfg['base']['mgmt_ip'];
      'vserver'     = $request['svm_name'];
      'name'        = $export_policy['name'];
    }
    $ontap_export_policy['ontap_export_policy'] += $new_policy
  }
 
  return $ontap_export_policy
}
  else{
     $ontap_export_policy = @{
            'success'     = $False;
            'reason'      = 'No standard policy to add';
            }
     return $ontap_export_policy
  }
}
 
function ontap_export_policy_rule() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,
     [parameter(Mandatory=$True)]
     [string]$mysql_pw
  )
 
  $sql = "
    SELECT *
    FROM db_cfg.svm_export_policy_rule
    WHERE 1 = 1
      AND service = '" + $request['service'] + "'
      AND service_name  = '" + $request['service_name'] + "'
      AND environment REGEXP '" + $request['environment'] + "|ALL'
  ;
  "
 
  $sql_data = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  $ontap_export_policy_rule = @{
    'success'     = $True;
    'reason'      = 'success';
    'ontap_export_policy_rule' = @();
  }
  foreach ( $export_policy_rule in $sql_data[-($sql_data.Count-1) .. -1]){
    $new_policy_rule = @{
      'hostname'    = $cluster_cfg['base']['mgmt_ip'];
      'vserver'     = $request['svm_name'];
      'name'        = $export_policy_rule['name'];
    }
    if ( $export_policy_rule['ro_rule'] ){              $new_policy_rule['ro_rule'] =             $export_policy_rule['ro_rule'] }
    if ( $export_policy_rule['rw_rule'] ){              $new_policy_rule['rw_rule'] =             $export_policy_rule['rw_rule'] }
    if ( $export_policy_rule['super_user_security'] ){  $new_policy_rule['super_user_security'] = $export_policy_rule['super_user_security'] }
    if ( $export_policy_rule['client_match'] ){         $new_policy_rule['client_match'] =        $export_policy_rule['client_match'] }
    if ( $export_policy_rule['allow_suid'] ){           $new_policy_rule['allow_suid'] =          $export_policy_rule['allow_suid'] }
    if ( $export_policy_rule['anonymous_user_id'] ){    $new_policy_rule['anonymous_user_id'] =   $export_policy_rule['anonymous_user_id'] }
    if ( $export_policy_rule['protocol'] ){             $new_policy_rule['protocol'] =            $export_policy_rule['protocol'] }
    if ( $export_policy_rule['rule_index'] ){           $new_policy_rule['rule_index'] =          $export_policy_rule['rule_index'] }
 
    $ontap_export_policy_rule['ontap_export_policy_rule'] += $new_policy_rule
  }
 
  return $ontap_export_policy_rule
 
}
 
function ontap_net_interface() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,
     [parameter(Mandatory=$True)]
     [string]$mysql_pw
  )
 
  $ontap_interface = @{
    'success'       = $True;
    'reason'        = "success";
    'ontap_net_interface' = @()
  }
 
  $sql = "
    SELECT *
    FROM db_cfg.svm_interface
    WHERE 1 = 1
      AND service = '" + $request['service'] + "'
      AND service_name  = '" + $request['service_name'] + "'
      AND environment = '" + $request['environment'] + "'
      AND model = '" + $cluster_cfg['base']['model'] + "'
    ;
  "
  $interface_cfg = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
  get-wfalogger -info -message $sql
  #------------------------------------------------------------------
  # We assume that all node names end in 'n[0-9]+$'.  The node name
  # in the table is of the form %cluster%n[0-9]+$, so we can just
  # take the node name out of the table, do a substitution on
  # %cluster% and have our node name.
  #------------------------------------------------------------------
  if ( $interface_cfg[0] -eq 0 ){
    return $ontap_interface
  }
  get-wfalogger -info -message $('data ip count= ' +$request['data_ip_list'].Count)
  get-wfalogger -info -message $('backup ip count= ' +$request['bkup_ip_list'].Count)
  $data_ip_idx = 0
  $bkup_ip_idx = 0
  foreach ( $lif_def in $interface_cfg[ 1 .. $interface_cfg[0] ] ){
    get-wfalogger -info -message $($lif_def | Out-String)
    $lif_name_pattern = $lif_def['name_pattern'] -replace '%svm%', $request['svm_name']
    get-wfalogger -info -message $($lif_name_pattern)
    if( $lif_def['name_pattern'] -match 'bkup' ){
      $ip = $request['bkup_ip_list'][$bkup_ip_idx]
      $lif_name = $lif_name_pattern -replace '#', $( $bkup_ip_idx + 1 )
      $bkup_ip_idx += 1
    }
    else{     
      $ip = $request['data_ip_list'][$data_ip_idx]
      $lif_name = $lif_name_pattern -replace '#', $( $data_ip_idx + 1 )
      $data_ip_idx += 1
    }
    get-wfalogger -info -message $('Lif name= ' + $lif_name)
    get-wfalogger -info -message $($ip | Out-String)
    $lif = @{
      'hostname'        = $cluster_cfg['base']['mgmt_ip'];
      'vserver'         = $request['svm_name'];
      'interface_name'  = $lif_name;
      'home_node'       = $cluster_cfg['base']['nodes'][0]['name'];
      'home_port'       = $lif_def['home_port'];
      'failover_group'  = $lif_def['failover_group'];
      'failover_policy' = $lif_def['failover_policy'];
      'address'         = $ip['addr'];
      'netmask'         = $ip['netmask'];
      'protocols'       = $lif_def['protocols'];
      'role'            = $lif_def['role'];
    }
    $ontap_interface['ontap_net_interface']  += $lif
  }
 
  return $ontap_interface
}
 
function ontap_net_route() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,
     [parameter(Mandatory=$True)]
     [string]$mysql_pw
  )
 
  $ontap_net_route = @{
    'success'       = $True;
    'reason'        = "success";
    'ontap_net_route' = @()
  }
 
  foreach ( $route in $request['routes'] ){
    $tmp = @{
      'hostname'        = $cluster_cfg['base']['mgmt_ip'];
      'vserver'         = $request['svm_name'];
      'destination'     = $route['destination'];
      'gateway'         = $route['gateway'];
    }
 
    $ontap_net_route['ontap_net_route'] += $tmp
  }
  return $ontap_net_route
}
 
function ontap_nfs(){
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg
  )
   $ontap_nfs = @{
    'success'           = $true;
    'reason'            = "Success";
    'ontap_nfs'     = @()
  }
 
  $tmp = @{
      'hostname'          = $cluster_cfg['base']['mgmt_ip'];
      'service_state'     = 'started';
      'vserver'           = $request['svm_name'];
      'nfsv3'             = 'enabled';
      'nfsv4'             = 'enabled';
  }
  $ontap_nfs['ontap_nfs'] += $tmp
  return $ontap_nfs
}
function ontap_nis_domain() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,
     [parameter(Mandatory=$True)]
     [string]$mysql_pw
  )
 
  $location = $cluster_cfg['base']['name'].Substring(0,3)
 
  $sql = "
    SELECT *
    FROM db_cfg.svm_nis_domain
    WHERE 1 = 1
      AND service = '" + $request['service'] + "'
      AND service_name  = '" + $request['service_name'] + "'
      AND environment REGEXP '" + $request['environment'] + "'
      AND location REGEXP '" + $location + "'
  ;
  "
  get-wfalogger -info -message $sql
  $sql_data = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  $ontap_nis_domain = @{
    'success'     = $True;
    'reason'      = 'success';
    'ontap_nis_domain' = @();
  }
  foreach ( $nis_domain in $sql_data[-($sql_data.Count-1) .. -1]){
    $nis_domain_obj = @{
      'hostname'    = $cluster_cfg['base']['mgmt_ip'];
      'vserver'     = $request['svm_name'];
    }
    if ( $nis_domain['domain'] ){              $nis_domain_obj['domain'] =            $nis_domain['domain'] }
    if ( $nis_domain['name_servers'] ){        $nis_domain_obj['name_servers'] =      $nis_domain['name_servers'] }
 
    $ontap_nis_domain['ontap_nis_domain'] += $nis_domain_obj
  }
 
  return $ontap_nis_domain
}
function ontap_dns_domain() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,
     [parameter(Mandatory=$True)]
     [string]$mysql_pw
  )
 
  $location = $cluster_cfg['base']['name'].Substring(0,3)
 
  $sql = "
    SELECT *
    FROM db_cfg.svm_dns_domain
    WHERE 1 = 1
      AND service = '" + $request['service'] + "'
      AND service_name  = '" + $request['service_name'] + "'
      AND environment REGEXP '" + $request['environment'] + "'
      AND location REGEXP '" + $location + "'
  ;
  "
  get-wfalogger -info -message $sql
  $sql_data = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  $ontap_dns_domain = @{
    'success'     = $True;
    'reason'      = 'success';
    'ontap_dns_domain' = @();
  }
  foreach ( $dns_domain in $sql_data[-($sql_data.Count-1) .. -1]){
    $dns_domain_obj = @{
      'hostname'    = $cluster_cfg['base']['mgmt_ip'];
      'vserver'     = $request['svm_name'];
    }
    if ( $dns_domain['domain'] ){              $dns_domain_obj['domains'] =            $dns_domain['domain'] }
    if ( $dns_domain['name_servers'] ){        $dns_domain_obj['nameservers'] =      $dns_domain['name_servers'] }
 
    $ontap_dns_domain['ontap_dns_domain'] += $dns_domain_obj
  }
 
  return $ontap_dns_domain
}
 
 
function ontap_cifs_server() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,
     [parameter(Mandatory=$True)]
     [string]$mysql_pw
  )
 
  $location = $cluster_cfg['base']['name'].Substring(0,3)
 
  $sql = "
    SELECT *
    FROM db_cfg.svm_cifs_server
    WHERE 1 = 1
      AND service = '" + $request['service'] + "'
      AND service_name  = '" + $request['service_name'] + "'
      AND location REGEXP '" + $location + "'
  ;
  "
  get-wfalogger -info -message $sql
  $sql_data = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  $ontap_cifs_server = @{
    'success'     = $True;
    'reason'      = 'success';
    'ontap_cifs_server' = @();
  }
  foreach ( $cifs_server in $sql_data[-($sql_data.Count-1) .. -1]){
    $cifs_server_obj = @{
      'hostname'    = $cluster_cfg['base']['mgmt_ip'];
      'vserver'     = $request['svm_name'];
      'name'  =  $request['svm_name'];
      'service_state'  =  'started';
    }
    if ( $cifs_server['domain'] ){  $cifs_server_obj['domain']    =  $cifs_server['domain'] }
    if ( $cifs_server['ou'] )    {  $cifs_server_obj['ou']        =  $cifs_server['ou']     }
 
    $ontap_cifs_server['ontap_cifs_server'] += $cifs_server_obj
  }
 
  return $ontap_cifs_server
}
function servicenow(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request
   )
   $return_values = @()
   Get-WfaLogger -Info -Message $( "ServieNow Request Inputs " + $request)
 
   $comment = "SVM configuration has been completed for: " + $request['svm_name']
 
   $snow = @{
      'success'         = $True;
      'reason'          = "Connecting to ServiceNow";
      'servicenow'   = @(
        @{
          'comment'         = $comment;
          'correlation_id'  = $request['correlation_id'];
          'action'          = 'completed';
          'sys_id'          = $request['snow_request_id'];
        },
        @{
          'correlation_id'  = $request['correlation_id'];
          'action'          = 'logging';
          'sys_id'          = $request['snow_request_id'];
        }
      )
   }  
   return $snow
}
 
########################################################################
# VARIABLES & CONSTANTS
########################################################################
 
########################################################################
# MAIN
########################################################################
 
$request = @{
  'cluster_name'                = $cluster_name;
  'snow_request_id'             = $sys_id;
  'correlation_id'              = $RITM;
  'svm_name'                    = $svm_name;
  'svm_node'                    = $svm_node;
  'service'                     = $service;
  'service_name'                = $service_name;
  'environment'                 = $environment;
  'data_ip_list'                = @();
  'bkup_ip_list'                = @();
  'routes'                      = @();
 
}
#---------------------------------------------------------------
# FIXME: RTU 11 May 2021
# Verify that each LIF type has the correct number of IPs
# available
#---------------------------------------------------------------
Get-Wfalogger -Info -Message "getting Data IP"
foreach( $ip_row in $data_ip_list.Split(',') ){
  $addr, $netmask = $ip_row.Split('~')
  Get-Wfalogger -Info -Message $('addr= ' + $addr)
  $lif = @{
    "addr"    = $addr;
    "netmask" = $netmask;
  }
  $request['data_ip_list'] += $lif
}
 
Get-Wfalogger -Info -Message "getting Bkp IP"
foreach( $ip_row in $backup_ip_list.Split(',') ){
  $addr, $netmask = $ip_row.Split('~')
  Get-Wfalogger -Info -Message $('addr= ' + $addr)
  $lif = @{
    "addr"    = $addr;
    "netmask" = $netmask;
  }
  $request['bkup_ip_list'] += $lif
}
 
Get-Wfalogger -Info -Message "getting network routes"
foreach( $ip_row in $route_list.Split(',') ){
  $dest, $gw = $ip_row.Split('~')
  $route = @{
    "destination"    = $dest;
    "gateway"       = $gw;
  }
  $request['routes'] += $route
}
 
$raw_service_request = @{
  'service'     = 'svm_build';
  'operation'   = 'create';
  'std_name'    = 'none';
  'req_details' = @{}
}
 
$mysql_pw = Get-WFAUserPassword -pw2get 'MySQL'
 
Get-WfaLogger -Info -Message "##################### CLUSTER CFG #####################"
$cluster_cfg = get_cluster_cfg      `
    -request    $request    `
    -mysql_pw   $mysql_pw
if ( -not $cluster_cfg['success'] ){
  $fail_msg = $cluster_cfg['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
Get-WfaLogger -Info -Message "##################### SVM CFG #####################"
$ontap_vserver = ontap_vserver      `
    -request    $request    `
    -cluster_cfg $cluster_cfg `
    -mysql_pw   $mysql_pw
if ( -not $ontap_vserver['success'] ){
  $fail_msg = $ontap_vserver['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
$raw_service_request['req_details']['ontap_vserver'] = $ontap_vserver['ontap_vserver']
#---------------------------------------------------------------
# Now we start to define the resources based upon the cfg
# info obtained above.
#---------------------------------------------------------------
 
#if(-not $request['service_name'] -eq "FSU"){
Get-WfaLogger -Info -Message "##################### EXPORT POLICY #####################"
$ontap_export_policy = ontap_export_policy          `
              -request      $request      `
              -cluster_cfg  $cluster_cfg  `
              -mysql_pw     $mysql_pw
if ( -not $ontap_export_policy['success'] ){
  $fail_msg = $ontap_vserver['reason']
  Get-WfaLogger -Info -Message $fail_msg
}
else{
  $raw_service_request['req_details']['ontap_export_policy'] = $ontap_export_policy['ontap_export_policy']
  Get-WfaLogger -Info -Message $(ConvertTo-Json $raw_service_request -Depth 10)
}
#}
 
Get-WfaLogger -Info -Message "##################### EXPORT POLICY RULE #####################"
$ontap_export_policy_rule = ontap_export_policy_rule          `
              -request      $request      `
              -cluster_cfg  $cluster_cfg  `
              -mysql_pw     $mysql_pw
if( -not $ontap_export_policy_rule['success'] ){
$fail_msg = $ontap_export_policy_rule['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
 
$raw_service_request['req_details']['ontap_export_policy_rule'] = $ontap_export_policy_rule['ontap_export_policy_rule']
Get-WfaLogger -Info -Message $(ConvertTo-Json $raw_service_request -Depth 10)
 
 
Get-WfaLogger -Info -Message "##################### ONTAP_NET_INTERFACE #####################"
$ontap_net_interface = ontap_net_interface          `
              -request      $request      `
              -cluster_cfg  $cluster_cfg  `
              -mysql_pw     $mysql_pw
if( -not $ontap_net_interface['success'] ){
  $fail_msg = $ontap_net_interface['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_net_interface'] = $ontap_net_interface['ontap_net_interface']
Get-WfaLogger -Info -Message $(ConvertTo-Json $raw_service_request -Depth 10)
 
if(-not ($request['routes']['destination'] -eq "")){
Get-WfaLogger -Info -Message "##################### NET ROUTE #####################"
$ontap_net_route = ontap_net_route  `
              -request      $request `
              -cluster_cfg  $cluster_cfg `
              -mysql_pw     $mysql_pw
if( -not $ontap_net_route['success'] ){
  $fail_msg = $ontap_net_route['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_net_route'] = $ontap_net_route['ontap_net_route']
Get-WfaLogger -Info -Message $raw_service_request
}
 
Get-WfaLogger -Info -Message "##################### ONTAP_NFS #####################"
$ontap_nfs = ontap_nfs          `
              -request      $request      `
              -cluster_cfg  $cluster_cfg
if( -not $ontap_nfs['success'] ){
  $fail_msg = $ontap_nfs['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_nfs'] = $ontap_nfs['ontap_nfs']
Get-WfaLogger -Info -Message $(ConvertTo-Json $raw_service_request -Depth 10)
 
Get-WfaLogger -Info -Message "##################### NIS DOMAIN #####################"
$ontap_nis_domain = ontap_nis_domain  `
              -request      $request `
              -cluster_cfg  $cluster_cfg `
              -mysql_pw     $mysql_pw
if( -not $ontap_nis_domain['success'] ){
  $fail_msg = $ontap_nis_domain['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_nis_domain'] = $ontap_nis_domain['ontap_nis_domain']
Get-WfaLogger -Info -Message $(ConvertTo-Json $raw_service_request -Depth 10)
Get-WfaLogger -Info -Message "##################### DNS DOMAIN #####################"
$ontap_dns_domain = ontap_dns_domain  `
              -request      $request `
              -cluster_cfg  $cluster_cfg `
              -mysql_pw     $mysql_pw
if( -not $ontap_dns_domain['success'] ){
  $fail_msg = $ontap_dns_domain['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
$raw_service_request['req_details']['ontap_dns_domain'] = $ontap_dns_domain['ontap_dns_domain']
Get-WfaLogger -Info -Message $(ConvertTo-Json $raw_service_request -Depth 10)
Get-WfaLogger -Info -Message "##################### CIFS SERVER #####################"
$ontap_cifs_server = ontap_cifs_server  `
              -request      $request `
              -cluster_cfg  $cluster_cfg `
              -mysql_pw     $mysql_pw
if( -not $ontap_cifs_server['success'] ){
  $fail_msg = $ontap_cifs_server['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
$raw_service_request['req_details']['ontap_cifs_server'] = $ontap_cifs_server['ontap_cifs_server']
Get-WfaLogger -Info -Message $(ConvertTo-Json $raw_service_request -Depth 10)
 
Get-WfaLogger -Info -Message "##################### SERVICENOW #####################"
$servicenow = servicenow  `
              -request $request
if( -not $servicenow['success'] ){
  $fail_msg = $servicenow['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['servicenow'] = $servicenow['servicenow']
Get-WfaLogger -Info -Message $(ConvertTo-Json $raw_service_request -Depth 10)
#$creds = Get-WfaCredentials -HostName $rest_host
#$rest_cfg = @{'uri' = 'http://loninstorpc1.uk.db.com:5001/api/v1/nas_provisioning/cluster'}
$rest_cfg = @{
  'host' = $rest_host;
  'creds' = $creds;
}
submit_request -raw_service_request $raw_service_request -rest_cfg $rest_cfg

