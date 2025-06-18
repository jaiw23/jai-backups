
param (
  [parameter(Mandatory=$True)]
  [string]$cluster_name,
  [parameter(Mandatory=$True)]
  [string]$service,
  [parameter(Mandatory=$False)]
  [string]$licenses,
  [parameter(Mandatory=$True)]
  [string]$RITM,
  [parameter(Mandatory=$True)]
  [string]$sys_id,
  [parameter(Mandatory=$True)]
  [string]$data_ip_list,
  [parameter(Mandatory=$False)]
  [string]$route_list,
  [parameter(Mandatory=$True)]
  [string]$rest_host
)
 
########################################################################
# FUNCTIONS
########################################################################
#-----------------------------------------------------------------------
# UTILITY FUNCTIONS
#-----------------------------------------------------------------------
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
  $result = Invoke-WebRequest -uri $($rest_cfg['host'] + '/api/v1/nas_provisioning/cluster')`
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
 
function get_cluster_cfg(){
  param(
    [parameter(Mandatory=$true)]
    [hashtable]$request,
    [parameter(Mandatory=$True)]
    [string]$mysql_pw
  )
 
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
    ORDER BY node.name ASC
    ;
  "
  $cfg = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
  get-wfalogger -info -message $( $cfg | out-string)
  #------------------------------------------------------------------
  # We should never see 0 here beause we selected the cluster in the
  # UI, but let's protect ourselves just in case something silly
# happens.
  #------------------------------------------------------------------
  if ( $cfg[0] -eq 0 ){
    return @{
      'success'   = $false;
      'reason'    = "Unable to find matching cluster"
    }
  }
 
  $cluster_cfg = @{
    'success'   = $True;
    'reason'    = "Success";
    'base'   = @{
      'name'            = $cfg[1].cluster_name;
      'model'           = $cfg[1].node_model;
      'mgmt_ip'         = $cfg[1].cluster_primary_address;
      'node_names'      = @();
      'nodes'           = @();
      'aggrs'           = @();
      'net_interfaces'  = @();
    }
  }
  get-wfalogger -info -message $( $cluster_cfg['base']['model'] | out-string)
  #---------------------------------------------------------------
  # Each returned row may contain a node that has already been
  # seen since > 1 aggr can be attached to each node.  node_by_name
  # is used to track those nodes that have been added to the node
  # list.
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
  #------------------------------------------------------------------
  # Now grab the interface list
  #------------------------------------------------------------------
  $sql = "
    SELECT *
    FROM db_cfg.cluster_interface
    WHERE 1 = 1
      AND model = '" + $cluster_cfg['base']['model'] + "'
      AND service = '" + $request['service'] + "'
    ;
  "
  get-wfalogger -Info -Message $sql
  $net_interfaces_cfg = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
  get-wfalogger -info -message $( $net_interfaces_cfg | out-string)
  $net_interfaces = @()
  if ( $net_interfaces_cfg[0] -ge 1 ){
  get-wfalogger -info -message $($net_interfaces_cfg.Count-1)
    foreach ( $net_interface_cfg in $net_interfaces_cfg[-($net_interfaces_cfg.Count-1) .. -1]){
      $net_interface = @{
        'name'            = $net_interface_cfg['name_pattern'];
        'role'            = $net_interface_cfg['role'];
        'protocols'       = $net_interface_cfg['protocols'];
        'failover_group'  = $net_interface_cfg['failover_group'];
        'home_port'       = $net_interface_cfg['home_port'];
        'home_node'       = $net_interface_cfg['home_node'];
        'failover_policy' = $net_interface_cfg['failover_policy'];
      }
      $net_interfaces += $net_interface
    }
  }
 
  $cluster_cfg['base']['net_interfaces'] = $net_interfaces
 
  return $cluster_cfg
}
#-----------------------------------------------------------------------
# STORAGE RESOURCE FUNCTIONS
#-----------------------------------------------------------------------
 
function ontap_net_port() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,
     [parameter(Mandatory=$true)]
     [string]$mysql_pw
  )
 
  $sql = "
    SELECT *
    FROM db_cfg.cluster_net_port
    WHERE
          model = '" + $cluster_cfg['base']['model'] + "'
      AND service = '" + $request['service'] + "'
  ;
  "
  $ontap_net_ports = @()
  $net_ports = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
  foreach ( $net_port in $net_ports[ 1 .. ($net_ports[0] ) ]){
    foreach ( $node_name in $cluster_cfg['base']['node_names'] ){
      Get-WfaLogger -Info -Message $( "node_name: " + $node_name )
      $new_port = @{
        'hostname'      = $cluster_cfg['base']['mgmt_ip'];
        'node'          = $node_name;
        'mtu'           = $net_port.mtu;
        'ports'         = $net_port.ports;
      }
      $ontap_net_ports += $new_port
    }
  }
 
  return @{
      'success'         = $True;
      'reason'          = "successfully found suitable volume";
      'ontap_net_port'  = $ontap_net_ports
  }
}
 
function ontap_ifgrp() {
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
    FROM db_cfg.cluster_ifgrp
    WHERE  1 = 1
      AND model         = '" + $cluster_cfg['base']['model']  + "'
      AND service       = '" + $request['service']            + "'
  ;
  "
  $net_ifgrp = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  $ontap_net_ifgrp = @{
    'success'     = $True;
    'reason'      = "success";
    'ontap_net_ifgrp' = @();
  }
  foreach( $ifgrp in $net_ifgrp[ -($net_ifgrp.Count-1) .. -1 ] ){
    foreach ( $node_name in $cluster_cfg['base']['node_names'] ){
      $tmp_ifgrp = @{
        'hostname'      = $cluster_cfg['base']['mgmt_ip'];
        'name'          = $ifgrp['ifgrp_name'];
        'node'          = $node_name;
        'mode'          = $ifgrp['mode'];
        'ports'         = $ifgrp['port_list'];
        'distribution_function' = $ifgrp['distribution_function'];
      }
      $ontap_net_ifgrp['ontap_net_ifgrp'] += $tmp_ifgrp
    }
  }
 
  return $ontap_net_ifgrp
}
 
function ontap_vlan() {
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
    FROM db_cfg.cluster_vlan
    WHERE  1 = 1
      AND model         = '" + $cluster_cfg['base']['model']  + "'
      AND service       = '" + $request['service']            + "'
  ;
  "
  $net_vlan = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  $ontap_net_vlan = @{
    'success'     = $True;
    'reason'      = "success";
    'ontap_net_vlan' = @();
  }
  foreach ( $vlan in $net_vlan[ -($net_vlan.Count-1) .. -1 ] ){
    foreach ( $port in $vlan['parent_interface'] ){
      foreach ( $node_name in $cluster_cfg['base']['node_names'] ){
        $tmp_vlan = @{
          'hostname'          = $cluster_cfg['base']['mgmt_ip'];
          'vlanid'            = $vlan['vlan_id'];
          'node'              = $node_name;
          'parent_interface'  = $port;
        }
      $ontap_net_vlan['ontap_net_vlan'] += $tmp_vlan
      }
    }
  }
  return $ontap_net_vlan
}
 
function ontap_net_interface() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg
  )
  get-wfalogger -info -message "in net interface"
  # lif_names in the cfg table may contain wildcards of the form
  # %node% or n# and similar.  The following % wildcard
  # substitutions are supported:
  #   node
  #   cluster
 
  $ontap_interface = @{
    'success'       = $True;
    'reason'        = "success";
    'ontap_net_interface' = @()
  }
 
  #------------------------------------------------------------------
  # The cluster cfg sorts aggrs in DESC order by available space,
  # so the one with the most available space is index 0.  That means
  # the node name @ index 0 matches the aggr with most space available
  #------------------------------------------------------------------
  $tmp_net_interface_list = @()
  $data_ip_idx = 0
  Get-WfaLogger -Info -message $($cluster_cfg['base']['net_interfaces'] | ConvertTo-Json -Depth 10)
  foreach ( $lif_def in $cluster_cfg['base']['net_interfaces'] ){  
    $node_list = @()
 
    $home_node_pattern = $lif_def['home_node'] -replace '%cluster%', $cluster_cfg['base']['name']
    foreach ( $node_name in $cluster_cfg['base']['node_names'] ){
        if ( $node_name -match $home_node_pattern ){
            $node_list += $node_name
        }
    }
 
    $lif_idx = 1
    $lif_name_pattern = $lif_def['name'] -replace '%cluster%', $cluster_cfg['base']['name']
 
    foreach ( $node_name in $node_list ){
      $old_name_pattern = $lif_name_pattern
      $lif_name_pattern = $lif_name_pattern -replace '#', $lif_idx
      if ( $old_name_pattern -ne $lif_name_pattern ){
        $lif_idx         += 1
      }
      $lif_name         = $lif_name_pattern -replace '%node%', $node_name
      $ip = $request['data_ip_list'][$data_ip_idx]
 
      $lif = @{
        'hostname'        = $cluster_cfg['base']['mgmt_ip'];
        'interface_name'  = $lif_name;
        'home_node'       = $node_name;
        'home_port'       = $lif_def['home_port'];
        'failover_group'  = $lif_def['failover_group'];
        #'failover_policy' = $lif_def['failover_policy'];
        'address'         = $ip['addr'];
        'netmask'         = $ip['netmask'];
        #'protocols'       = $lif_def['protocols'];
        'role'            = $lif_def['role'];
        'vserver'         = $cluster_cfg['base']['name'];
      }
      if( $lif_def.failover_policy ){ $lif['schedule']   += $lif_def.failover_policy }
      if( $lif_def.protocols )      { $lif['protocols']  += $lif_def.protocols }
      $data_ip_idx += 1
      $tmp_net_interface_list  += $lif
    }
  }
 
  $ontap_interface['ontap_net_interface'] = $tmp_net_interface_list
  return $ontap_interface
}
 
function ontap_net_route() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg
  )
 
  $ontap_net_route = @{
    'success'       = $True;
    'reason'        = "success";
    'ontap_net_route' = @()
  }
 
  foreach ( $route in $request['routes'] ){
    $tmp = @{
      'hostname'        = $cluster_cfg['base']['mgmt_ip'];
      'vserver'         = $cluster_cfg['base']['name'];
      'destination'     = $route['destination'];
      'gateway'         = $route['gateway'];
    }
 
    $ontap_net_route['ontap_net_route'] += $tmp
  }
  return $ontap_net_route
}
 
function ontap_failover_grp() {
param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg
  )
 
  $sql = "
    SELECT *
    FROM db_cfg.cluster_failover_grp
    WHERE
          model           = '" + $cluster_cfg['base']['model']  + "'
      AND service         = '" + $request['service']            + "'
  ;
  "
 
  $network_cfg  = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  $ontap_net_failover_grp = @{
    'success'       = $True;
    'reason'        = 'success';
    'ontap_failover_grp'  = @();
  }
  foreach ( $net_item in $network_cfg[ -($network_cfg.Count-1) .. -1 ] ){
    $ports    = $net_item['targets'] -split ','
    $targets  = ""
    foreach( $node_name in $cluster_cfg['base']['node_names'] ){
      foreach ( $port in $ports ){
        $targets += $( $node_name + ':' + $port )
        $targets += ","
      }
    }
    $targets = $targets -replace ",$", ""
    $failover_grp = @{
      'hostname'          = $cluster_cfg['base']['mgmt_ip'];
      'vserver'           = $cluster_cfg['base']['name'];
      'name'              = $net_item['name'];
      'targets'           = $targets;
    }
    $ontap_net_failover_grp['ontap_failover_grp'] += $failover_grp
 
  }
 
  return $ontap_net_failover_grp
}
 
function ontap_ipspace() {
  param(
    [parameter(Mandatory=$true)]
    [hashtable]$request,
    [parameter(Mandatory=$True)]
    [hashtable]$cluster_cfg,
    [parameter(Mandatory=$True)]
    [string]$mysql_pw
  )
 
  $ontap_ipspace = @{
    'success'     = $True;
    'reason'      = 'success';
    'ontap_ipspace'   = @();
  }
 
  $sql  = "
    SELECT
      model,
      service,
      name
    FROM db_cfg.cluster_ipspace
    WHERE 1 = 1
      AND model         = '" + $cluster_cfg['base']['model'] + "'
      AND service       = '" + $request['service'] + "'
  ;
  "
  $ipspace_cfg = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  if ( $ipspace_cfg[0] -eq 0 ){
    $ontap_ipspace['reason'] = 'No ipspace configurations for this config'
    return $ontap_ipspace
  }
 
  foreach( $ipspace in $ipspace_cfg[-($ipspace_cfg.Count-1) .. -1]){
    $new_ipspace = @{
      'hostname'      = $cluster_cfg['base']['mgmt_ip'];
      'name'          = $ipspace['name'];
    }
    $ontap_ipspace['ontap_ipspace'] += $new_ipspace
  }
 
  return $ontap_ipspace
}
 
function ontap_broadcast_domain_ports(){
  param(
    [parameter(Mandatory=$true)]
    [hashtable]$request,
    [parameter(Mandatory=$True)]
    [hashtable]$cluster_cfg,
    [parameter(Mandatory=$True)]
    [string]$mysql_pw
  )
 
  $ontap_broadcast_domain_ports = @{
    'success'     = $True;
    'reason'      = 'success';
    'ontap_broadcast_domain_ports'  = @();
  }
 
  $sql = "
    SELECT
       cluster_broadcast_domain.model          AS 'model',
       cluster_broadcast_domain.service        AS 'service',
       cluster_broadcast_domain.name           AS 'name',
       cluster_broadcast_domain.ipspace        AS 'ipspace',
       cluster_broadcast_domain.mtu            AS 'mtu',
       cluster_ifgrp.port_list                 AS 'ports'
    FROM db_cfg.cluster_broadcast_domain
    JOIN db_cfg.cluster_ifgrp   ON (cluster_ifgrp.model = cluster_broadcast_domain.model
    AND cluster_ifgrp.service = cluster_broadcast_domain.service
    AND cluster_broadcast_domain.ports REGEXP CONCAT('^', cluster_ifgrp.ifgrp_name)
    )
    WHERE 1 = 1
    AND cluster_broadcast_domain.model         = '" + $cluster_cfg['base']['model'] + "'
    AND cluster_broadcast_domain.service       = '" + $request['service']+ "'
    ;
  "
  $broadcast_domain_cfg = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
  get-wfalogger -info -message $($broadcast_domain_cfg | Out-String)
  foreach ( $broadcast_domain in $broadcast_domain_cfg[-($broadcast_domain_cfg.Count-1) .. -1] ){
    $ports    = $broadcast_domain['ports'] -split ','
    $targets  = ""
    foreach( $node_name in $cluster_cfg['base']['node_names'] ){
      foreach ( $port in $ports ){
        $targets += $( $node_name + ':' + $port )
        $targets += ","
      }
    }
    $targets = $targets -replace ",$", ""
    $rm_ports = @{
      'hostname'      = $cluster_cfg['base']['mgmt_ip'];
      'broadcast_domain'          = 'Default';
      'ports'         = $targets;
      'state'         = 'absent';
    }
    $ontap_broadcast_domain_ports['ontap_broadcast_domain_ports'] += $rm_ports
  }
 
  return $ontap_broadcast_domain_ports
}
 
function ontap_broadcast_domain(){
  param(
    [parameter(Mandatory=$true)]
    [hashtable]$request,
    [parameter(Mandatory=$True)]
    [hashtable]$cluster_cfg,
    [parameter(Mandatory=$True)]
    [string]$mysql_pw
  )
 
  $sql = "
    SELECT
      model,
      service,
      name,
      ipspace,
      mtu,
      ports
    FROM db_cfg.cluster_broadcast_domain
    WHERE 1 = 1
      AND model         = '" + $cluster_cfg['base']['model'] + "'
      AND service       = '" + $request['service'] + "'
  ;
  "
  $broadcast_domain_cfg = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  $ontap_broadcast_domain = @{
    'success'     = $True;
    'reason'      = 'success';
    'ontap_broadcast_domain'  = @();
  }
 
  foreach ( $broadcast_domain in $broadcast_domain_cfg[-($broadcast_domain_cfg.Count-1) .. -1] ){
    $ports = $broadcast_domain['ports'] -split ','
    $targets = ""
    foreach ( $node_name in $cluster_cfg['base']['node_names'] ){
      foreach ( $port in $ports ){
        $targets += $( $node_name + ':' + $port )
        $targets += ","
      }
    }
    $targets = $targets -replace ",$", ""
    $new_domain = @{
      'hostname'      = $cluster_cfg['base']['mgmt_ip'];
      'name'          = $broadcast_domain['name'];
      'ipspace'       = $broadcast_domain['ipspace'];
      'mtu'           = $broadcast_domain['mtu'];
      'ports'         = $targets;
    }
    $ontap_broadcast_domain['ontap_broadcast_domain'] += $new_domain
  }
 
  return $ontap_broadcast_domain
}
 
function licenses() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,
     [parameter(Mandatory=$true)]
     [string]$mysql_pw
  )
  #--------------------------------------------------------
  # The list of licenses is included in the request.
  # Build the request
  # pull cluster info from cm_storage.cluster
  #--------------------------------------------------------
  $ontap_license = @()
  foreach( $license in $request['licenses'].Split(',') ){
    $ontap_license += @{
      'hostname'      = $cluster_cfg['base']['mgmt_ip'];
      'license_codes'       = $license
    }
  }
 
  return @{
    'success'   = $True;
    'reason'    = 'success';
    'ontap_license' = $ontap_license
  }
}
 
function schedule() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,
     [parameter(Mandatory=$true)]
     [string]$mysql_pw
  )
 
  $ontap_job_schedule = @{
    'success'       = $True;
    'reason'        = 'success';
    'ontap_job_schedule'  = @();
  }
 
  $sql = "
    SELECT *
    FROM db_cfg.cluster_schedule
    WHERE 1 = 1
      AND service       = '" + $request['service'] + "'
  ;
  "
 
  $schedule_cfg = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
  foreach ( $schedule in $schedule_cfg[-($schedule_cfg.Count-1) .. -1]){
     $new_cfg = @{
      'hostname'            = $cluster_cfg['base']['mgmt_ip'];
      'name'                = $schedule['name'];
    }
    if ($schedule['month']){      $new_cfg['job_months']          = $schedule['month'] }
    if ($schedule['dayofweek']){  $new_cfg['job_days_of_week']    = $schedule['dayofweek'] }
    if ($schedule['day']){        $new_cfg['job_days_of_month']   = $schedule['day'] }
    if ($schedule['hour']){       $new_cfg['job_hours']           = $schedule['hour'] }
    if ($schedule['minute']){     $new_cfg['job_minutes']         = $schedule['minute'] }
  
   $ontap_job_schedule['ontap_job_schedule'] += $new_cfg
  }
 
  return $ontap_job_schedule
 
}
 
function snapshot_policy() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,
     [parameter(Mandatory=$true)]
     [string]$mysql_pw
  )
 
  $ontap_snapshot_policy = @{
    'success'       = $True;
    'reason'        = 'success';
    'ontap_snapshot_policy' = @();
  }
 
  $sql = "
    SELECT *
    FROM db_cfg.cluster_snapshot_policy
    WHERE 1 = 1
      AND service       = '" + $request['service'] + "'
  ;
  "
 
  $snapshot_cfg = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
   
  foreach ( $snap in $snapshot_cfg[-($snapshot_cfg.Count-1) .. -1]){
    $new_cfg = @{
      'hostname'      = $cluster_cfg['base']['mgmt_ip'];
      'name'          = $snap['name'];
      'vserver'       = $cluster_cfg['base']['name'];
      'enabled'       = 'True'
    }
    if( $snap.schedule1 ){          $new_cfg['schedule']          += @($snap.schedule1) }
    if( $snap.count1 ){             $new_cfg['count']             += @($snap.count1) }
    if( $snap.snapmirror_label1 ){  $new_cfg['snapmirror_label']  += @($snap.snapmirror_label1) }
    if( $snap.prefix1 ){            $new_cfg['prefix']            += @($snap.prefix1) }
 
    if( $snap.schedule2 ){          $new_cfg['schedule']          += @($snap.schedule2) }
    if( $snap.count2 ){             $new_cfg['count']             += @($snap.count2) }
    if( $snap.snapmirror_label2 ){  $new_cfg['snapmirror_label']  += @($snap.snapmirror_label2) }
    if( $snap.prefix2 ){            $new_cfg['prefix']            += @($snap.prefix2) }
 
    if( $snap.schedule3 ){          $new_cfg['schedule']          += @($snap.schedule3) }
    if( $snap.count3 ){             $new_cfg['count']             += @($snap.count3) }
    if( $snap.snapmirror_label3 ){  $new_cfg['snapmirror_label']  += @($snap.snapmirror_label3) }
    if( $snap.prefix3 ){            $new_cfg['prefix']            += @($snap.prefix3) }
 
    if( $snap.schedule4 ){          $new_cfg['schedule']          += @($snap.schedule4) }
    if( $snap.count4 ){             $new_cfg['count']             += @($snap.count4) }
    if( $snap.snapmirror_label4 ){  $new_cfg['snapmirror_label']  += @($snap.snapmirror_label4) }
    if( $snap.prefix4 ){            $new_cfg['prefix']            += @($snap.prefix4) }
 
    if( $snap.schedule5 ){          $new_cfg['schedule']          += @($snap.schedule5) }
    if( $snap.count5 ){             $new_cfg['count']             += @($snap.count5) }
   if( $snap.snapmirror_label5 ){  $new_cfg['snapmirror_label']   += @($snap.snapmirror_label5) }
    if( $snap.prefix5 ){            $new_cfg['prefix']            += @($snap.prefix5) }
 
   $ontap_snapshot_policy['ontap_snapshot_policy'] += $new_cfg
  }
  
  return $ontap_snapshot_policy
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
    FROM db_cfg.cluster_dns_domain
    WHERE 1 = 1
      AND model         = '" + $cluster_cfg['base']['model'] + "'
      AND service       = '" + $request['service'] + "'
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
      'vserver'     = $cluster_cfg['base']['name'];
    }
    if ( $dns_domain['domain'] ){              $dns_domain_obj['domains'] =            $dns_domain['domain'] }
    if ( $dns_domain['name_servers'] ){        $dns_domain_obj['nameservers'] =      $dns_domain['name_servers'] }
 
    $ontap_dns_domain['ontap_dns_domain'] += $dns_domain_obj
  }
 
  return $ontap_dns_domain 
}
 
function ontap_ntp() {
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
    FROM db_cfg.cluster_ntp
    WHERE 1 = 1
      AND model         = '" + $cluster_cfg['base']['model'] + "'
      AND service       = '" + $request['service'] + "'
      AND location REGEXP '" + $location + "'
  ;
  "
  get-wfalogger -info -message $sql
  $sql_data = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  $ontap_ntp = @{
    'success'     = $True;
    'reason'      = 'success';
    'ontap_ntp'   = @();
  }
  foreach ( $ntp_server in $sql_data[-($sql_data.Count-1) .. -1]){
    $ntp_server_obj = @{
      'hostname'    = $cluster_cfg['base']['mgmt_ip'];
      'vserver'     = $cluster_cfg['base']['name'];
    }
    if ( $ntp_server['server_name'] ){  $ntp_server_obj['server_name'] = $ntp_server['server_name'] }
    if ( $ntp_server['timezone'] ){  $ntp_server_obj['timezone'] = $ntp_server['timezone'] }
 
    $ontap_ntp['ontap_ntp'] += $ntp_server_obj
  }
 
  return $ontap_ntp
}
 
function ontap_snmp_community() {
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
    FROM db_cfg.cluster_snmp_community
    WHERE 1 = 1
      AND model         = '" + $cluster_cfg['base']['model'] + "'
      AND service       = '" + $request['service'] + "'
      AND location REGEXP '" + $location + "'
  ;
  "
  get-wfalogger -info -message $sql
  $sql_data = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  $ontap_snmp_community = @{
    'success'     = $True;
    'reason'      = 'success';
    'ontap_snmp' = @();
  }
  foreach ( $snmp in $sql_data[-($sql_data.Count-1) .. -1]){
    $snmp_obj = @{
      'hostname'    = $cluster_cfg['base']['mgmt_ip'];
    }
    if ( $snmp['community_name'] ){  $snmp_obj['community_name'] = $snmp['community_name'] }
 
    $ontap_snmp_community['ontap_snmp'] += $snmp_obj
  }
 
  return $ontap_snmp_community
}
 
function ontap_snmp_traphosts() {
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
    FROM db_cfg.cluster_snmp_traphosts
    WHERE 1 = 1
      AND model         = '" + $cluster_cfg['base']['model'] + "'
      AND service       = '" + $request['service'] + "'
      AND location REGEXP '" + $location + "'
  ;
  "
  get-wfalogger -info -message $sql
  $sql_data = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
 
  $ontap_snmp_traphosts = @{
    'success'     = $True;
    'reason'      = 'success';
    'ontap_snmp_traphosts' = @();
  }
  foreach ( $snmp_traphosts in $sql_data[-($sql_data.Count-1) .. -1]){
   $snmp_traphost_list = $snmp_traphosts['ip_address'] -split ','
    foreach( $snmp_traphost in $snmp_traphost_list){
        $snmp_traphost_obj = @{
        'hostname' = $cluster_cfg['base']['mgmt_ip'];
        'ip_address' = $snmp_traphost
        }
    $ontap_snmp_traphosts['ontap_snmp_traphosts'] += $snmp_traphost_obj
    }
  }
 
  return $ontap_snmp_traphosts
}
 
function ontap_autosupport() {
  param(
     [parameter(Mandatory=$true)]
     [hashtable]$request,
     [parameter(Mandatory=$True)]
     [hashtable]$cluster_cfg,
     [parameter(Mandatory=$true)]
     [string]$mysql_pw
  )
 
  $location = $cluster_cfg['base']['name'].Substring(0,3)
 
  $sql = "
    SELECT *
    FROM db_cfg.cluster_autosupport
    WHERE
          model = '" + $cluster_cfg['base']['model'] + "'
      AND service = '" + $request['service'] + "'
      AND location REGEXP '" + $location + "'
  ;
  "
  $ontap_autosupport = @()
  $asups = Invoke-MySqlQuery -query $sql -user root -password $mysql_pw
  foreach ( $asup in $asups[ 1 .. ($asups[0] ) ]){
    foreach ( $node_name in $cluster_cfg['base']['node_names'] ){
      Get-WfaLogger -Info -Message $( "node_name: " + $node_name )
      $tmp = @{
        'hostname'      = $cluster_cfg['base']['mgmt_ip'];
        'node_name'     = $node_name;
        'mail_hosts'    = $asup.mail_hosts;
        'from_address'  = $asup.from_address;
        'to_addresses'  = $asup.to_address;
        'transport'     = $asup.transport;
        'proxy_url'     = $asup.proxy_url;
      }
      $ontap_autosupport += $tmp
    }
  }
 
  return @{
      'success'         = $True;
      'reason'          = "successfully found suitable volume";
      'ontap_autosupport'  = $ontap_autosupport
  }
}
 
function servicenow(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request
   )
   $return_values = @()
   Get-WfaLogger -Info -Message $( "ServieNow Request Inputs " + $request)
 
   $comment = "Cluster configuration has been completed for: " + $request['cluster_name']
 
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
  'service'                     = $service;
  'licenses'                    = $licenses;
  'data_ip_list'                = @();
  'routes'                      = @();
}
 
#---------------------------------------------------------------
# FIXME: RTU 11 May 2021
# Verify that each LIF type has the correct number of IPs
# available
#---------------------------------------------------------------
foreach( $ip_row in $data_ip_list.Split(',') ){
  $addr, $netmask, $gw = $ip_row.Split('~')
  $lif = @{
    "addr"    = $addr;
    "netmask" = $netmask;
    "gateway" = $gw;
  }
  $request['data_ip_list'] += $lif
}
 
<#Get-Wfalogger -Info -Message "getting network routes"
foreach( $ip_row in $route_list.Split(',') ){
  $dest, $gw = $ip_row.Split('~')
  $request['routes'] += @{
    "destination"    = $dest;
    "gateway"       = $gw;
  }
}#>
 
$raw_service_request = @{
  'service'     = 'cluster_build';
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
 
Get-WfaLogger -Info -Message $( $cluster_cfg | ConvertTo-Json -Depth 10)
 
Get-WfaLogger -Info -Message "##################### NETWORKPORTS #####################"
$ontap_net_port = ontap_net_port  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_net_port['success'] ){
  $fail_msg = $ontap_net_port['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_net_port'] = $ontap_net_port['ontap_net_port']
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
Get-WfaLogger -Info -Message "##################### NET IFGRP #####################"
$ontap_ifgrp = ontap_ifgrp  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_ifgrp['success'] ){
  $fail_msg = $ontap_ifgrp['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_net_ifgrp'] = $ontap_ifgrp['ontap_net_ifgrp']
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
Get-WfaLogger -Info -Message "##################### NET VLAN #####################"
$ontap_vlan = ontap_vlan  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_vlan['success'] ){
  $fail_msg = $ontap_vlan['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_net_vlan'] = $ontap_vlan['ontap_net_vlan']
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
Get-WfaLogger -Info -Message "##################### NET INTERFACE #####################"
$ontap_interface = ontap_net_interface  `
              -request $request `
              -cluster_cfg $cluster_cfg
if( -not $ontap_interface['success'] ){
  $fail_msg = $ontap_interface['reason']
Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_net_interface'] = $ontap_interface['ontap_net_interface']
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
<#Get-WfaLogger -Info -Message "##################### NET ROUTE #####################"
$ontap_net_route = ontap_net_route  `
              -request $request `
              -cluster_cfg $cluster_cfg
if( -not $ontap_net_route['success'] ){
  $fail_msg = $ontap_net_route['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_net_route'] = $ontap_net_route['ontap_net_route']
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)#>
 
<#Get-WfaLogger -Info -Message "##################### NET FAILOVER GRP #####################"
$ontap_failover_grp = ontap_failover_grp  `
              -request $request `
              -cluster_cfg $cluster_cfg            
if( -not $ontap_failover_grp['success'] ){
  $fail_msg = $ontap_failover_grp['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_failover_grp'] = $ontap_failover_grp['ontap_failover_grp']
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)#>
 
Get-WfaLogger -Info -Message "##################### IPSPACE #####################"
$ontap_ipspace = ontap_ipspace  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_ipspace['success'] ){
  $fail_msg = $ontap_ipspace['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_ipspace'] = $ontap_ipspace['ontap_ipspace']
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
<#Get-WfaLogger -Info -Message "##################### BROADCAST DOMAIN PORTS #####################"
$ontap_broadcast_domain_ports = ontap_broadcast_domain_ports  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_broadcast_domain_ports['success'] ){
  $fail_msg = $ontap_broadcast_domain_ports['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_broadcast_domain_ports'] = $ontap_broadcast_domain_ports['ontap_broadcast_domain_ports']
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)#>
 
Get-WfaLogger -Info -Message "##################### BROADCAST DOMAIN #####################"
$ontap_broadcast_domain = ontap_broadcast_domain  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_broadcast_domain['success'] ){
  $fail_msg = $ontap_broadcast_domain['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_broadcast_domain'] = $ontap_broadcast_domain['ontap_broadcast_domain']
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
if(-not ($licenses -eq "")){
Get-WfaLogger -Info -Message "##################### LICENSES #####################"
$ontap_license = licenses  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_license['success'] ){
  $fail_msg = $ontap_license['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
 
$raw_service_request['req_details']['ontap_licenses'] = $ontap_license['ontap_license']
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
}
 
Get-WfaLogger -Info -Message "##################### SCHEDULE #####################"
$ontap_job_schedule = schedule  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_job_schedule['success'] ){
  $fail_msg = $ontap_job_schedule['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_job_schedule'] = $ontap_job_schedule['ontap_job_schedule']
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
Get-WfaLogger -Info -Message "##################### SNAPSHOT POLICY #####################"
$ontap_snapshot_policy = snapshot_policy  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_snapshot_policy['success'] ){
  $fail_msg = $ontap_snapshot_policy['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_snapshot_policy'] = $ontap_snapshot_policy['ontap_snapshot_policy']
Get-WfaLogger -Info -Message $($raw_service_request | ConvertTo-Json -Depth 10)
 
<#Get-WfaLogger -Info -Message "##################### DNS DOMAIN #####################"
$ontap_dns_domain = ontap_dns_domain  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_dns_domain['success'] ){
  $fail_msg = $ontap_dns_domain['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_dns_domain'] = $ontap_dns_domain['ontap_dns_domain']
Get-WfaLogger -Info -Message $($raw_service_request | ConvertTo-Json -Depth 10)
 
Get-WfaLogger -Info -Message "##################### NTP SERVER #####################"
$ontap_ntp = ontap_ntp  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_ntp['success'] ){
  $fail_msg = $ontap_ntp['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_ntp'] = $ontap_ntp['ontap_ntp']
Get-WfaLogger -Info -Message $($raw_service_request | ConvertTo-Json -Depth 10)
 
Get-WfaLogger -Info -Message "##################### SNMP #####################"
$ontap_snmp = ontap_snmp_community  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_snmp['success'] ){
  $fail_msg = $ontap_snmp['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_snmp'] = $ontap_snmp['ontap_snmp']
Get-WfaLogger -Info -Message $($raw_service_request | ConvertTo-Json -Depth 10)
 
Get-WfaLogger -Info -Message "##################### SNMP TRAPHOSTS #####################"
$ontap_snmp_traphosts = ontap_snmp_traphosts  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_snmp_traphosts['success'] ){
  $fail_msg = $ontap_snmp_traphosts['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_snmp_traphosts'] = $ontap_snmp_traphosts['ontap_snmp_traphosts']
Get-WfaLogger -Info -Message $($raw_service_request | ConvertTo-Json -Depth 10)
 
Get-WfaLogger -Info -Message "##################### AUTOSUPPORT #####################"
$ontap_autosupport = ontap_autosupport  `
              -request $request `
              -cluster_cfg $cluster_cfg `
              -mysql_pw $mysql_pw
if( -not $ontap_autosupport['success'] ){
  $fail_msg = $ontap_autosupport['reason']
  Get-WfaLogger -Info -Message $fail_msg
  Throw $fail_msg
}
 
$raw_service_request['req_details']['ontap_autosupport'] = $ontap_autosupport['ontap_autosupport']
Get-WfaLogger -Info -Message $($raw_service_request | ConvertTo-Json -Depth 10)#>
 
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

