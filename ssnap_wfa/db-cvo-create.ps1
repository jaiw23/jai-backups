
param (
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
   
   [parameter(Mandatory=$False, HelpMessage="NIS Netgroup")]
   [string]$netgroup_ro,
  
   [parameter(Mandatory=$False, HelpMessage="NIS Netgroup")]
   [string]$netgroup_rw,
 
   [parameter(Mandatory=$False, HelpMessage="NIS Domain")]
   [string]$nis_domain, 
 
   [parameter(Mandatory=$False, HelpMessage="protocol (NFS|CIFS)")]
   [string]$protocol,
 
   [parameter(Mandatory=$True)]
   [string]$service_level,
 
   [parameter(Mandatory=$True)]
   [string]$service_name,
  
   [parameter(Mandatory=$True)]
   [string]$snow_request_id,
 
   [parameter(Mandatory=$False)]
   [int]$storage_instance_count,
 
   [parameter(Mandatory=$False)]
   [int]$storage_requirement,
 
   [parameter(Mandatory=$True)]
   [string]$correlation_id,
 
   [parameter(Mandatory=$False)]
   [string]$smb_acl_group_contact,
 
   [parameter(Mandatory=$False)]
   [string]$smb_acl_group_delegate,
 
   [parameter(Mandatory=$False)]
   [string]$smb_acl_group_approver_1,
 
   [parameter(Mandatory=$False)]
   [string]$smb_acl_group_approver_2,
 
   [parameter(Mandatory=$False)]
   [string]$dfs_root_path,
 
   [parameter(Mandatory=$False)]
   [string]$dfs_path_1,
 
   [parameter(Mandatory=$False)]
   [string]$dfs_path_2,
 
   [parameter(Mandatory=$False)]
   [string]$dfs_new_folder,
 
   [parameter(Mandatory=$False)]
   [string]$dfs_folder,
 
   [parameter(Mandatory=$True)]
   [string]$sys_id,
 
   [parameter(Mandatory=$False)]
   [string]$landing_zone,
 
   [parameter(Mandatory=$False)]
   [string]$platform,
 
   [parameter(Mandatory=$False)]
   [string]$ekm
)
 
#---- Set the Security Protocol to TLS1.1 and TLS1.2 -----#
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
public bool CheckValidationResult(
ServicePoint srvPoint, X509Certificate certificate,
WebRequest request, int certificateProblem) {
return true;
}
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
 
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
#-----------------------------------------------------------------
# Function: svm_selection_logic()
# INPUT - Request which came as input to WFA
# In this Fuction we are dynamically creating the SQL statment for selction of Verver.
# Line 110 - we are creating a regular regex to be used everywhere. depending upon the location passed in request
# Line 113 - This is a base sql statment to be used every where.
# Line 125:127 - We are changing the environment in request to dev for all env coming as INT in request.
#                as we don't have any env int.
# We have structured the complete function in two major If conditons and under them we have checks and coditions for
# for all the service names
# Inside each and every scenario, we are creating the the Cluster and svm regex depending updon the selection logic
# provided on teams by DB under svm_selection_logic folder.
# there are some data tweeking happening that make no sense in logic, but that is added as part of ability to handle
# old and inconsistent data. which is not as per namespace used to implement this project.
# Also there are some custers which are for different locations, but they actually reside in some other location.
# So some checks are added for that work too.
#-----------------------------------------------------------------
 
function svm_selection_logic() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request
   )
 
   Get-WfaLogger -Info -Message "Entered svm_selection_logic with request =="
   #------- NETAPPMS-161  : SSNAP - NAS Premium India DC logic ----
   if($request['site'] -ne $null){
   $regular_regex = $request['location'].ToLower() + $request['site'].ToLower()}
   else {$regular_regex = $request['location'].ToLower() + '[a-zA-Z0-9]{3}'}
   $cluster_env = ""
   $sql = "
      SELECT
         vserver.name            AS 'name',
         cluster.name            AS 'cluster_name',
         cluster.primary_address AS 'cluster_primary_address',
         cluster.is_metrocluster AS 'is_metrocluster',
         count(volume.name) as 'vserver_volume_count'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver             ON (vserver.cluster_id = cluster.id)
      JOIN cm_storage.volume              ON (volume.vserver_id = vserver.id)
      WHERE vserver.name NOT LIKE '%-mc' AND vserver.name NOT LIKE '%-dr'"
   if($request['environment'].ToLower() -eq $INT){
      $request['environment'] = $DEV
   }
 
   if($request['service_level'].ToLower() -eq $NAS_PREMIUM){
     
      #TODO - Create a function
      #----Tidying up redundant code - MC3 has different naming convention----#
 
       
      # Added logic for gatehall exit - MC3
      #---- JIRA GSSC-406 (Add logic for NYC DEV goes to UAT svm) -----
      #------- NETAPPMS-140  : Include FRA MC3 and SV and Re-group MC3 logic ----     
      #------- NETAPPMS-167  : SSNAP - SIN MC3 and SIN SnapVault ----       
      #------ NETAPPMS-186 : SSNAP - Support for UK MC3 with split datacentre -----#                                             
      if($MC3_SITE.Contains($request['location'].ToLower())){    #covers : NYC | FRA | IND | SIN | LON
         $cluster_env = $PROD
         #---NETAPPMS-139 INDIA Fabric Selection logic----------
         if($request['location'].ToLower() -eq "ind"){      
            $regular_regex = $request['site'].ToLower() + '[a-zA-Z]{3}'     
         }
         else{
               $regular_regex = $request['location'].ToLower() + '[a-zA-Z0-9]{3}'
             }
         $cluster_name_regex = $regular_regex +`
                              $cluster_service_map[$service_level]['platform_code'] + `
                              $cluster_env[0] + '[0-9]+'
 
         $svm_name_regex = $regular_regex +`
                        $cluster_service_map[$service_level]['platform_code']  + `
                        $request['environment'][0] +'[0-9]+'                   + `
                        'svm' + '[0-8]+'
                        
         if($request['environment'] -eq $DEV){
              $svm_name_regex = $regular_regex +`
                        $cluster_service_map[$service_level]['platform_code']  + `
                        'u' +'[0-9]+'                   + `
                        'svm' + '[0-8]+'
                        }
      }
                
      
      if($request['service_name'].ToLower() -eq $GFS){
         if($request['protocol'].ToLower() -eq $NFS){
            $sql+=   " AND vserver.nis_domain = '" + $request['nis_domain'] + "'" +`
                     " AND cluster.name REGEXP '" + $cluster_name_regex + "'" +`
                     " AND vserver.name REGEXP '" + $svm_name_regex + "'"
         }elseif($request['protocol'].ToLower() -eq $SMB){
             $sql+=   "AND vserver.cifs_domain = '" + $CIFS_DOMIAN  + "'" +`
                     " AND cluster.name REGEXP '" + $cluster_name_regex + "'" +`
                     " AND vserver.name REGEXP '" + $svm_name_regex + "'"      
         }
      }elseif ($request['service_name'].ToLower() -eq $FABRIC){
 
             $sql+=  " AND cluster.name REGEXP '" + $cluster_name_regex + "'" +`
                     " AND vserver.name REGEXP '" + $svm_name_regex + "'"              
      }
   }
   if($request['service_level'].ToLower() -eq $NAS_SHARED){
     
      if($request['location'].ToLower() -eq "ind"){      
        $regular_regex = '(mum|pnq)' + '[a-zA-Z]{3}'     
      }
 
      #---- JIRA GSSC-415 (Tokyo and HongKong to svm selection criteria) -----
 
      if($request['location'].ToLower() -eq "tko"){      
        $regular_regex = '(tok)' + '[a-zA-Z]{3}'    
      }
 
      $cluster_name_regex = $regular_regex +`
                           $cluster_service_map[$service_level]['platform_code']  + `
                           'p'                   + `
                           '[0-9]+'
      $svm_name_regex = $regular_regex +`
                       $cluster_service_map[$service_level]['platform_code']  + `
                        $request['environment'][0] +'[0-9]+'                   + `
                        'svm' + $cluster_service_map[$service_level][$service_name]['prefix'] + '[0-9]+'
      
      if ($request['service_name'].ToLower() -eq $FSU){
         $sql+=   " AND vserver.cifs_domain = '" + $CIFS_DOMIAN  + "'" +`
                  " AND cluster.name REGEXP '" + $cluster_name_regex + "'" +`
                  " AND vserver.name REGEXP '" + $svm_name_regex + "'"
      }elseif ($request['service_name'].ToLower() -eq $VFS ){
            if($request['protocol'].ToLower() -eq $NFS){ 
                $sql+=   " AND vserver.nis_domain = '" + $request['nis_domain'] + "'" +`
                         " AND cluster.name REGEXP '" + $cluster_name_regex + "'" +`
                         " AND vserver.name REGEXP '" + $svm_name_regex + "'"           
            }elseif($request['protocol'].ToLower() -eq $SMB){
               $sql+=   " AND vserver.cifs_domain = '" + $CIFS_DOMIAN  + "'" +`
                        " AND cluster.name REGEXP '" + $cluster_name_regex + "'" +`
                        " AND vserver.name REGEXP '" + $svm_name_regex + "'"
            }    
      }elseif ($request['service_name'].ToLower() -eq $Ediscovery){
          $sql+=   " AND vserver.cifs_domain = '" + $CIFS_DOMIAN  + "'" +`
                   " AND cluster.name REGEXP '" + $cluster_name_regex + "'" +`
                   " AND vserver.name REGEXP '" + $svm_name_regex + "'"
      }
 
   }
 
   #--------- Adding CVO related selection logic ---------
   if($request['service_level'].ToLower() -eq $CVO){
      $cluster_env = $request['environment']
      $regular_regex = $request['location'].ToLower() + $cluster_service_map[$service_level][$service_name.ToLower()]['prefix']
 
      if($request['platform'].ToLower() -eq "shared"){
      #----NETAPP-MS-204 : Modify FRA EKM Selection logic----#  
         
            $cluster_name_regex = $regular_regex +`
                              $cluster_service_map[$service_level]['platform_code'][$landing_zone.ToLower()] + `
                              'cvo' + `
                              $cluster_env[0] + '[0-9]{3}'
                 
      }
      else {
 
         $cvo_platform = $request['platform'].ToLower().Substring(0,3)
 
         $cluster_name_regex = $regular_regex +`
                              $cluster_service_map[$service_level]['platform_code'][$landing_zone.ToLower()] + `
                              $cvo_platform + `
                              $cluster_env[0] + '[0-9]{3}'
      }
                             
      $svm_name_regex = $regular_regex +`
                     $cluster_service_map[$service_level]['platform_code'][$landing_zone.ToLower()] + `
                     $cluster_env[0] +'[0-9]{3}'                   + `
                     'svm' + '[0-8]'
 
      if($request['protocol'].ToLower() -eq $NFS){
            $sql+=   " AND vserver.nis_domain = '" + $request['nis_domain'] + "'" +`
                     " AND cluster.name REGEXP '" + $cluster_name_regex + "'" +`
                     " AND vserver.name REGEXP '" + $svm_name_regex + "'"
                    
      }
     
      elseif($request['protocol'].ToLower() -eq $SMB){
             $sql+=   "AND vserver.cifs_domain = '" + $CIFS_DOMIAN  + "'" +`
                     " AND cluster.name REGEXP '" + $cluster_name_regex + "'" +`
                     " AND vserver.name REGEXP '" + $svm_name_regex + "'"      
      }
 
   }
   $sql+=" GROUP BY vserver.id ORDER BY vserver_volume_count ASC;"
 
   #----------------------------------------------------------------
   #  For testing we use below query
   #----------------------------------------------------------------
 
   <# $sql = $sql = "
      SELECT
         vserver.name            AS 'name',
         cluster.name            AS 'cluster_name',
         cluster.primary_address AS 'cluster_primary_address',
         cluster.is_metrocluster AS 'is_metrocluster',
         count(volume.name) as 'vserver_volume_count'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver             ON (vserver.cluster_id = cluster.id)
      JOIN cm_storage.volume              ON (volume.vserver_id = vserver.id)
      WHERE vserver.name NOT LIKE '%-mc' AND vserver.name NOT LIKE '%-dr'
                         AND cluster.name REGEXP 'loninengcl'" +`
                         "AND vserver.cifs_domain = '" + $CIFS_DOMIAN  + "'" +`
                         "GROUP BY vserver.id ORDER BY vserver_volume_count ASC;" #>
 
   <# $sql = $sql = "
      SELECT
         vserver.name            AS 'name',
         cluster.name            AS 'cluster_name',
         cluster.primary_address AS 'cluster_primary_address',
         cluster.is_metrocluster AS 'is_metrocluster',
         count(volume.name) as 'vserver_volume_count'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver             ON (vserver.cluster_id = cluster.id)
      JOIN cm_storage.volume              ON (volume.vserver_id = vserver.id)
      WHERE vserver.name NOT LIKE '%-mc' AND vserver.name NOT LIKE '%-dr'
                         AND cluster.name REGEXP 'loninengcl'" +`
                         "AND vserver.name REGEXP 'loneng'" +`
                         "GROUP BY vserver.id ORDER BY vserver_volume_count ASC;" #>
 
    #---------- End of test query------------------------------------
 
   Get-WfaLogger -Info -Message "END svm_selection_logic with SQL == $sql"
   return $sql
}
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
   Add-WfaWorkflowParameter -Name 'raw_req_003' -Value $("__res_type='';operation=" + 'create') -AddAsReturnParameter $True
 
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
      [array]$qtrees,
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$db_user,
      [parameter(Mandatory=$true)]
      [string]$db_pw,
      [parameter(Mandatory=$true, HelpMessage="placement solution")]
      [hashtable]$placement_solution
   )
   Get-WfaLogger -Info -Message "Entered update_chargeback_table()"
 
   #---- JIRA GSSC-722 (DFS path and ACL in chargeback report) ----
   # We will add RW/RO ACL to netgroup_ro and netgroup_rw column of
   # chargeback table for SMB requests
 
   if( $request['protocol'].ToLower() -eq $NFS )
   {
      $RW_group = $request['netgroup_rw']
      $RO_group = $request['netgroup_ro']
   }
   elseif( $request['protocol'].ToLower() -eq $SMB )
   {
      $RW_group = $placement_solution['resources']['ontap_cifs'][0]['write_acl']
      $RO_group = $placement_solution['resources']['ontap_cifs'][0]['read_acl']
   }
  
   foreach ( $qtree in $qtrees ){
      $new_row = "
         INSERT INTO playground.chargeback
         VALUES (
            NULL,
            '" + $qtree['hostname'] + "',
            '" + $qtree['vserver'] + "',
            '" + $qtree['flexvol_name']  + "',
            '" + $qtree['name']   + "',
            '" + $request['cost_centre']                                   + "',
            '" + $request['protocol']                                      + "',
            "  + $request['storage_requirement']                           + ",
            '" + $request['nar_id']                                        + "',
            '" + $request['app_short_name']                                + "',
            '" + $request['service_name']                                  + "',
            '" + $request['nis_domain']                                    + "',
            '" + $RO_group                                                 + "',
            '" + $RW_group                                                 + "',
            '" + $request['email_address']                                 + "',           
            '" + $qtree['hostname']                                        + "',
            NULL,
            '" + $request['environment']                                   + "',
            '" + $request['snow_request_id']                               + "',
            '" + $request['dfs_path']                                      + "',
            '" + $request['location'].ToUpper()                            + "'
         )
         ;
      "
      Get-WfaLogger -Info -Message $new_row
      Invoke-MySqlQuery -query $new_row -user $db_user -password $db_pw
   }
}
 
#-----------------------------------------------------------------------
# CVO CHARGEBACK
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# We decided to create a seperate chargeback table for CVO as there
# are additional fields specific to CVO which doesnt fit for on-prem
# systems. This way we keep cloud and on-prem data on seperate tables
#-----------------------------------------------------------------------
 
function update_cvo_chargeback_table(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$volume,
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$db_user,
      [parameter(Mandatory=$true)]
      [string]$db_pw,
      [parameter(Mandatory=$true, HelpMessage="placement solution")]
      [hashtable]$placement_solution
   )
   Get-WfaLogger -Info -Message "Entered update_cvo_chargeback_table()"
 
   $RW_group = ''
   $RO_group = ''
 
   if( $request['protocol'].ToLower() -eq $NFS )
   {
      $RW_group = $request['netgroup_rw']
      $RO_group = $request['netgroup_ro']
   }
   elseif( $request['protocol'].ToLower() -eq $SMB )
   {
      $RW_group = $placement_solution['resources']['ontap_cifs'][0]['write_acl']
      $RO_group = $placement_solution['resources']['ontap_cifs'][0]['read_acl']
   }
 
      $new_row = "
         INSERT INTO playground.cvo_chargeback
         VALUES (
            NULL,
            '" + $volume['hostname'] + "',
            '" + $volume['vserver'] + "',
            '" + $volume['name']  + "',
            '" + $request['cost_centre']                                   + "',
            '" + $request['protocol']                                      + "',
            "  + $request['storage_requirement']                           + ",
            '" + $request['nar_id']                                        + "',
            '" + $request['app_short_name']                                + "',
            '" + $request['service_name']                                  + "',
            '" + $request['nis_domain']                                    + "',
            '" + $RO_group                                                 + "',
            '" + $RW_group                                                 + "',
            '" + $request['email_address']                                 + "',           
            '" + $volume['hostname']                                        + "',
            NULL,
            '" + $request['environment']                                   + "',
            '" + $request['snow_request_id']                               + "',
            '" + $request['landing_zone']                                  + "',
            '" + $request['platform']                                      + "',
            '" + $request['ekm']                                           + "'
         )
         ;
      "
      Get-WfaLogger -Info -Message $new_row
      Invoke-MySqlQuery -query $new_row -user $db_user -password $db_pw
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
 
function aggregate(){
   param(
      [parameter(Mandatory=$true)]
      [array]$vservers,
      [parameter(Mandatory=$true)]
      [string]$vol_size,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   $clusters = @()
   foreach ($vserver in $vservers){
      $clusters += $vserver['hostname']
   }
   $unique_clusters = $clusters | Sort-Object | Get-Unique
   $cluster_regex = '^(' + ($unique_clusters -join '|') + ')$'
 
   #------------------------------------------------------------
   # If we want to emulate the "WFA Finder" operation, we can
   # use INNER JOIN to emulate set intersection so we can use
   # multiple criteria to define multiple return sets then take
   # only what is common among all the results.
   #------------------------------------------------------------
 
   #--- GSSC-646 - Exclude SnapLock aggegates from selection criteria ---#
   #--- NETAPPMS-144 CVO SSNAP - add performance based selection criteria during volume creation ---#
   if ($request['service_level'].ToLower() -eq $CVO){
      Get-WfaLogger -Info -Message $("Looking for an CVO aggr")
      $aggr_select_sql = "
         SELECT
         cluster.name         AS 'cluster_name',
         cluster.primary_address AS 'hostname',
         node.name            AS 'node_name',
         aggregate.name       AS 'name',
         node_utilization.nodeutilization
         FROM cm_storage.cluster
         JOIN cm_storage.node ON (node.cluster_id = cluster.id)
         JOIN cm_storage.aggregate ON (aggregate.node_id = node.id)
         JOIN ontap_node_performance.node_utilization ON (node_utilization.nodename = node.name)
         WHERE 1
         AND cluster.primary_address REGEXP '$cluster_regex'
         AND aggregate.name NOT LIKE 'aggr0%'
         AND aggregate.name NOT LIKE '%root%'
         AND aggregate.is_snaplock = 'false'
         AND (aggregate.used_size_mb/aggregate.size_mb) <= 0.9
         AND node_utilization.nodeutilization < 50
         ORDER BY aggregate.available_size_mb DESC
         ;"
   }
   #------ NETAPPMS-186 : SSNAP - Support for UK MC3 with split datacentre -----#
   elseif($request['service_level'].ToLower() -eq $NAS_PREMIUM -and $request['location'].ToLower() -eq "lon" -and $request['Environment'].ToLower() -eq $PROD)
         { Get-WfaLogger -Info -Message $("Looking for an UK MC3 PROD aggr")     
         $aggr_select_sql = "
         SELECT
            cluster.name         AS 'cluster_name',
            cluster.primary_address AS 'hostname',
            node.name            AS 'node_name',
            aggregate.name       AS 'name'
         FROM cm_storage.cluster
         JOIN cm_storage.node ON (node.cluster_id = cluster.id)
         JOIN cm_storage.aggregate ON (aggregate.node_id = node.id)
         WHERE 1
            AND cluster.primary_address REGEXP '$cluster_regex'
            AND aggregate.name NOT LIKE 'aggr0%'
            AND aggregate.name NOT LIKE '%root%'
            AND (aggregate.name LIKE '%n1%' OR aggregate.name LIKE '%n2%')
            AND aggregate.is_snaplock = 'false'
            AND (aggregate.used_size_mb/aggregate.size_mb) <= 0.9
         ORDER BY aggregate.available_size_mb DESC
         ;"
 
         }
   elseif($request['service_level'].ToLower() -eq $NAS_PREMIUM -and $request['location'].ToLower() -eq "lon" -and $request['Environment'].ToLower() -ne $PROD)
         { Get-WfaLogger -Info -Message $("Looking for an UK MC3 Non-PROD aggr")     
         $aggr_select_sql = "
         SELECT
            cluster.name         AS 'cluster_name',
            cluster.primary_address AS 'hostname',
            node.name            AS 'node_name',
            aggregate.name       AS 'name'
         FROM cm_storage.cluster
         JOIN cm_storage.node ON (node.cluster_id = cluster.id)
         JOIN cm_storage.aggregate ON (aggregate.node_id = node.id)
         WHERE 1
            AND cluster.primary_address REGEXP '$cluster_regex'
            AND aggregate.name NOT LIKE 'aggr0%'
            AND aggregate.name NOT LIKE '%root%'
            AND (aggregate.name LIKE '%n3%' OR aggregate.name LIKE '%n4%')
            AND aggregate.is_snaplock = 'false'
            AND (aggregate.used_size_mb/aggregate.size_mb) <= 0.9
         ORDER BY aggregate.available_size_mb DESC
         ;"
         }
   else{
      $aggr_select_sql = "
         SELECT
            cluster.name         AS 'cluster_name',
            cluster.primary_address AS 'hostname',
            node.name            AS 'node_name',
            aggregate.name       AS 'name'
         FROM cm_storage.cluster
         JOIN cm_storage.node ON (node.cluster_id = cluster.id)
         JOIN cm_storage.aggregate ON (aggregate.node_id = node.id)
         WHERE 1
            AND cluster.primary_address REGEXP '$cluster_regex'
            AND aggregate.name NOT LIKE 'aggr0%'
            AND aggregate.name NOT LIKE '%root%'
            AND aggregate.is_snaplock = 'false'
            AND (aggregate.used_size_mb/aggregate.size_mb) <= 0.9
         ORDER BY aggregate.available_size_mb DESC
         ;"
      }
 
   Get-WfaLogger -Info -Message $aggr_select_sql
   Get-WfaLogger -Info -Message $("Looking for an aggr" )
   $aggrs = Invoke-MySqlQuery -query $aggr_select_sql -user root -password $mysql_pw
 
   if ( $aggrs[0] -ge 1 ){
      Get-WfaLogger -Info -Message $("Found aggr: " + $aggrs[1].name )
      Get-WfaLogger -Info -Message $("Node Utilization : " + $aggrs[1].nodeutilization )
      return @{
         'success'      = $True;
         'reason'       = "Found suitable aggregate";
         'ontap_aggr'   = @{
            'name'      = $aggrs[1].name;
            'cluster'   = $aggrs[1].cluster_name;
            'node'      = $aggrs[1].node_name;
           'hostname'  = $aggrs[1].hostname
         }
      }
   }
   else{
      return @{
         'success'      = $False;
         'reason'       = "Failed to find aggregate with sufficient free space"
         'ontap_aggr'   = @{}
      }
   }
}
 
function vserver() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
   Get-WfaLogger -Info -Message "Entered vserver()"
#-----------------------------------------------------------------------
# Function: svm_selection_logic()
# added to perform and collect all the selection logic in one function
#-----------------------------------------------------------------------
   [string]$query = svm_selection_logic -request $request
   get-wfalogger -info -message $query.GetType().name        
   Get-WfaLogger -Info -Message "Ready to query"
   $vservers = Invoke-MySqlQuery -Query $query -user 'root' -password $mysql_pass
   Get-WfaLogger -info -message "Executed vserver query"
   if ($vservers[0] -ge 1 ){
      $last_idx = $vservers[0]
      foreach ( $vserver in $vservers[1..$last_idx] ){
         Get-WfaLogger -Info -Message $($vservers[1]['name'])
      }
     
      $vserver_return = @{
         'success'      = $True;
         'reason'       = "Successfully found vserver(s)";
         'ontap_vserver'   = @()
      }
 
      foreach ( $vserver in $vservers[1..$last_idx] ){
         Get-WfaLogger -Info -Message $("Adding vserver: " + $vserver['name'])
         $vserver_return['ontap_vserver'] += @{
            'name'         = $vserver['name'];
            'hostname'     = $vserver['cluster_primary_address'];
         }
      }
   }
   else{
      $vserver_return = @{
         'success'      = $False;
         'reason'       = "Failed to find suitable vserver";
      }
   }
   Get-WfaLogger -Info -Message $("number of vservers: " + $vserver_return['ontap_vserver'].length)
   return $vserver_return
}
#-----------------------------------------------------------------------
# All of these storage objects are returned by WFA as part of the
# placement solution.  Also, some of them are used by other resources
# so we define both the return values and the objects themselves.
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
# REF:   Phone call between RTU & Bryce Harper 05 Jan 2021 to discuss how
#        best to approach the below problem.
#
# PROBLEM:     RTU 05 Jan 2021
#  Given that I am using custom WFA commands for everything and all
#  provisioning is executed outside of WFA, we do not have the advantage
#  of WFA's reservation system.  This means that when a new volume is
#  provisioned, that volume will not show up in WFA's database until
#  after the volume is provisioned by the Execution Layer then the entire
#  discovery process executes via AIQUM/WFA.  This likely means a min of
#  a 30-40 min delay between when this custom command determines that a
#  a new volume is required and that volume has been provisioned and
#  shows up in the WFA tables used by this command for subsquent requests.
#  This leaves a window of opportunity where we may have multiple follow
#  on requests before the discovery cycle completes. The end result is
#  that this command would then determine that another new volume is
#  required and multiple, unneeded volumes would then be provisioned.
#
# CONSIDERATIONS:
#  Current estimates are that we will see ~10-15 requests / wk.  This
#  makes it unlikely that we will see many back to back requests where
#  we will be waiting on the discovery of a newly provisioned volume.
#  This makes the above problem unlikely in practice, but not impossible.
#
#  Per Bryce, the approval process for these requests is currently
#  running on the order of 2-3 weeks.  Even if this is drastically
#  reduced the odds of even 5 back to back requests is remote at best.
#
#  The majority of the requests are on the order of 500GB or so per Bryce.
#  Therefore, 5 of them would total ~2.5TB.  The current upper limit for
#  volume autogrow is 4TB (assumed here but coded in the Execution Layer
#  standards definition).  2.5 TB represents ~63% of max autogrow size.
#
# STRATEGY:
#  Based upon the above, the following volume selection strategy will
#  implemeneted:
#     1. We try to find an existing volume that matches all relevant
#        selection criteria.  If we can, we'll use that volume.
#     2. Failing #1 above, check the chargeback table to see if there
#        are any volumes found there that have not yet been discovered
#        by WFA.  If there are none, we will provision a new volume
#     3. If there is a volume that we know WILL be provisioned (based upon
#        an entry or entries in the chargeback table) but has not yet
#        been discovered by WFA, we will select that volume as a candidate
#        and use it if the following criteria are satisfied:
#        a. While we will not maintain initial volume size standards within
#           WFA or any code outside the Execution  Layer, we will here
#           assume a maximum volume size of 4TB for our purposes;
#        b. If the sum total of all outstanding requested shares shown in
#           the chargeback table associated with the volume that we select
#           from is <= 63% of 4 TB (see above for 63% rationale),
#           we will select the new volume within the chargeback table.
#     4. If there is a volume that we KNOW will be provisioned in the
#        chargeback table, but it fails the above criteria, we will
#        simply provision a new volume
#
#     The above strategy should result in minimal chance that we will
#     provision new volumes that are not entirely needed given
#     the expected rate of incoming requests vs. overall discovery time
#     of volumes.
#
# RISKS & CONSEQUENCES:
#  1. There is a very slight chance that we will exceed overcommit limits
#     using this strategy.  I believe this risk to be so minimal as to be
#     inconsquential
#  2. We may provision >1 volume when we really don't need it.  I see this
#     as negligable because eventually we can expect any "extra" volumes
#     to be consumed.
#-----------------------------------------------------------------------
function volume() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [array]$vservers,
      [parameter(Mandatory=$true)]
      [hashtable]$aggregate,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   #--------------------------------------------------------------------
   # We add CVO related volume logic first so that rest of the SSNAP
   # logic can be skipped which will save time
   #--------------------------------------------------------------------
 
   if ($request['service_level'].ToLower() -eq $CVO){
      $volume = cvo_vol_helper_prov_new       `
      -request $request                `
      -vservers   $vservers            `
      -aggregate  $aggregate           `
      -mysql_pw   $mysql_pw
 
   return $volume
   }
 
   #--------------------------------------------------------------------
   # 1st we try to find an existing volume that WFA knows about
   #--------------------------------------------------------------------
   $volume = vol_helper_find_existing  `
      -request    $request             `
      -vservers   $vservers            `
      -mysql_pw   $mysql_pw
 
   if ( $volume['success'] ){
      Get-WfaLogger -Info -Message $( "Suitable WFA volume found: " + $volume['ontap_volume']['name'] )
      return $volume
   }
 
   #--------------------------------------------------------------------
   # Failing that, see if there is one that we know is pending provisioning
   # but WFA hasn't yet discovered
   #--------------------------------------------------------------------
   Get-WfaLogger -Info -Message "No suitable WFA volume found so we'll look for an unprovisioned volume"
   $volume = vol_helper_find_unprovisioned   `
      -request    $request                   `
      -vservers   $vservers                  `
      -mysql_pw   $mysql_pw
  
   Get-WfaLogger -Info -Message "Exited from function vol_helper_find_unprovisioned()"
   if ( $volume['success'] ){
      Get-WfaLogger -Info -Message $("Found an unprovisioned volume: " + $volume['ontap_volume']['name'] )
      return $volume
   }
   elseif( -not $volume['success'] -and $volume['reason'] -ne "No pending provisions" ){
      #-------------------------------------------------------------------
      # We tried to find a volume pending provisioning in the chargeback
      # table but we ran into some kind of error
      #-------------------------------------------------------------------
      Get-WfaLogger -Info -Message $("Tried to find pending provision volume but failed: " + $volume['reason'] )
      return $volume
   }
 
   #--------------------------------------------------------------------
   # Failing that, provision a new one
   #--------------------------------------------------------------------
   $volume = vol_helper_prov_new       `
      -request $request                `
      -vservers   $vservers            `
      -aggregate  $aggregate           `
      -mysql_pw   $mysql_pw
 
   return $volume
 
}
 
#--------------------------------------------------------------------
# Volume selection functions for when we don't already have an
# existing volume
#--------------------------------------------------------------------
#--------------------------------------------------------------------
# FUNCTION: vol_helper_find_existing()
#  See if we can find an existing volume
#--------------------------------------------------------------------
function vol_helper_find_existing() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [array]$vservers,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   #--------------------------------------------------------------------
   # Try to find a volume that:
   # 1.  Has the same qtrees already on it
   # 2.  The overcommit for those qtrees is less than the max
   # 3.  The useage of the volume is less than the max
   #--------------------------------------------------------------------
   $qtree_name_regex = $request['service_name'].Substring(0,3) + '_' + $request['environment'] + '_[0-9]{' + $QTREE_NUM_DIGITS + '}$'
 
   $vserver_list = @()
   foreach ($vserver in $vservers){
      $vserver_list += `
         "(vserver.name = '" + $vserver['name'] + "'" + `
         " AND " + `
         "cluster.primary_address = '" + $vserver['hostname'] + "')"   
   }
   $key='data'
   if($request['service_name'] -eq $FABRIC){
      $key=$FABRIC.ToLower()
   }
   $vserver_query    = $vserver_list -join " OR "
 
   $vserver_vol_list = @()
   foreach ( $vserver in $vservers ){
      $vserver_vol_list += $vserver['name']
   }
 
   $vol_name_regexp  = '^(' + ($vserver_vol_list -join '|') + ')'  + `
                       '_'+$key+'_[0-9]{' +$VOL_NAME_IDX_DIGITS  + '}_' + `
                        $request['protocol'].ToLower()
  
   #-----------------------------------------------------------------
   # FIXME: RTU 14 Oct 2020
   # NETAPP-81
   # We will now support multiple qtrees so this must change
   # accordingly.  Also, this select does not take into account
   # the new qtree(s) so that needs to be fixed.
   #-----------------------------------------------------------------
 
   #--- NETAPPMS-55 - SSNAP not select DCN cluster ---#
   #--- NETAPPMS-56 - SSNAP to include Aggregate check ( use volume on aggr less than 85% ) for existing volume selection ---#
   # Date : 30-June-2023
   # We found issue with volume selection logic where whenever a volume was
   # bieng selected for new qtree creation, it just considered volume with least number of qtree
   # due to this it started picking up volumes with least number if qtree but on a full aggregate
   # A check has now been added to only select volume whic has aggregat utilization less that 85%
 
   $total_share_size = $request['storage_instance_count'] * $request['storage_requirement']
   $vol_select = "
      SELECT
         cluster.name AS 'cluster_name',
         cluster.primary_address AS 'cluster_pri_addr',
         vserver.name AS 'vserver_name',
         volume.name AS 'volume_name',
         aggregate.name AS 'aggr_name',
         (aggregate.used_size_mb/aggregate.size_mb) AS 'aggr_used_percent',
         qtree.name AS 'qtree_name',
         quota_rule.cluster,
         quota_rule.vserver_name,
         quota_rule.quota_volume,
         quota_rule.quota_target,
         SUM(quota_rule.disk_limit)  AS 'sum_disk_limit',
         ((SUM(quota_rule.disk_limit)/1024/1024)+$total_share_size)/(volume.max_autosize_mb/1024) AS 'overcommit'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver ON ( vserver.cluster_id = cluster.id )
      JOIN cm_storage.volume ON ( volume.vserver_id = vserver.id )
      JOIN cm_storage.qtree ON (qtree.volume_id = volume.id)
      JOIN cm_storage.aggregate ON (volume.aggregate_id = aggregate.id)
      JOIN cm_storage_quota.quota_rule   ON (
         ( quota_rule.cluster = cluster.name OR quota_rule.cluster = cluster.primary_address )
         AND quota_rule.vserver_name = vserver.name
         AND quota_rule.quota_volume = volume.name
         AND CONCAT('/vol/',volume.name,'/',qtree.name) = quota_rule.quota_target
      )
      WHERE 1
         AND ( $vserver_query )
         AND qtree.name != ''
         AND qtree.name REGEXP '$qtree_name_regex'
         AND volume.used_size_mb/volume.size_mb <= $VOL_USAGE_MAX
         AND volume.name REGEXP '$vol_name_regexp'
         AND (aggregate.used_size_mb/aggregate.size_mb) <= $AGGR_USED_THRESHOLD_PERCENT
      GROUP BY volume.name
      HAVING overcommit < $VOL_OVERCOMMIT_MAX
      ORDER BY aggregate.available_size_mb DESC
      ;
"
  
   Get-WfaLogger -Info -Message $("Querying volumes")
   Get-WfaLogger -Info -Message $vol_select
   $vols = invoke-MySqlQuery -query $vol_select -user root -password $mysql_pw
 
   if ( $vols[0] -ge 1 ){
      #----------------------------------------------------------------
      # We found an existing volume that WFA already knows about, so
      # we don't define WFA return data, just give back the volume object.
      # This ensures that we don't tempt fate by passing any
      # unneccessary data to the Execution Layer
      #----------------------------------------------------------------
      return @{
         'success'         = $True;
         'reason'          = "successfully found suitable volume";
         'return_values'   = @();
         'ontap_volume'    = @{
            'hostname'     = $vols[1].cluster_pri_addr;
            'vserver'      = $vols[1].vserver_name;
            'name'         = $vols[1].volume_name;
         }
      }
   }
   else{
      return @{
         'success'         = $False;
         'reason'          = "No existing volume found";
         'return_values'   = @();
         'ontap_volume'    = @{}
      }
   }
}
#--------------------------------------------------------------------
# FUNCTION: vol_helper_prov_new()
#  Return attributes to provision an entirely new volume
#--------------------------------------------------------------------
function vol_helper_prov_new() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [array]$vservers,
      [parameter(Mandatory=$true)]
      [hashtable]$aggregate,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
   #----------------------------------------------------------------------
   # We earlied delayed failure if we could not find a suitable aggr since
   # failure for a resource we may not need doesn't make sense.  But now,
   # we'll actually need that aggr, so before we do anything, check to see
   # that we actually got one and now it's time to bail if not.
   #----------------------------------------------------------------------
   if ( $aggregate.Count -eq 0 ){
      return @{
         'success'         = $False;
         'reason'          = "We need an aggr for a new volume but couldn't find one";
         'return_values'       = @();
         'ontap_volume'    = @{}
      }
   }
  
   $vserver_list = @()
   foreach ( $vserver in $vservers ){
     $vserver_list += $vserver['name']
   }
   #----------------------------------------------------------------------
   # We know we need a brand new volume and we have already picked the
   # cluster on which it will go due to the aggr selection.  This also
  # implies that of all possible vservers, there is only 1 that is on the
   # matching cluster.  So let's just pick that one here and use it
   # throughout.  So just find the vserver that sits on the same cluster as
   # the aggr that we already picked.  We do this by matching the cluster
   # hostnames.
   #----------------------------------------------------------------------
 
   #TODO volume count check per vserver
   $vserver_idx   = 0
   Get-WfaLogger -Info -Message "Entered function vol_helper_prov_new()"
   Get-WfaLogger -Info -Message $vservers.Count
   Get-WfaLogger -Info -Message $aggregate.Count
   Get-WfaLogger -Info -Message $aggregate['hostname']
   Do{
     
      $vserver_found = $vservers[$vserver_idx]['hostname'] -eq $aggregate['hostname']
      Get-WfaLogger -Info -Message $vservers[$vserver_idx]['hostname']
      Get-WfaLogger -Info -Message $vserver_found
      $vserver_idx += 1
 
   }While (-not $vserver_found -and ($vserver_idx -le $vservers.length))
 
   if ( $vserver_found ){
      $vserver_name = $vservers[$vserver_idx-1]['name']
      Get-WfaLogger -Info -Message $vserver_name
   }
   else{
      # This should never happen, but let's just make sure we catch it if it does
      return @{
         'success'         = $False;
         'reason'          = "Failed to match existing vserver to selected aggr";
         'return_values'       = @();
        'ontap_volume'    = @{}
      }
   }
   $key='data'
   if($request['service_name'] -eq $FABRIC){
      $key=$FABRIC.ToLower()
   }
 
   $vol_name_regexp  = '^(' + ($vserver_list -join '|') + ')'  + `
                       '_'+$key+'_[0-9]{' +$VOL_NAME_IDX_DIGITS  + '}_' + `
                        $request['protocol'].ToLower()
 
 
   Get-WfaLogger -Info -Message "Getting highest idx from any volume unprovisioned yet"
  
   $vol_select = "
      SELECT
         cluster.primary_address  AS 'cluster_name',
         vserver.name  AS 'vserver_name',
         volume.name   AS 'vol_name',
         chargeback.cluster_name AS 'cb_cluster_name',
         chargeback.vserver_name AS 'cb_svm_name',
         chargeback.volume_name  AS 'cb_vol_name'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver ON (vserver.cluster_id = cluster.id)
      JOIN cm_storage.volume  ON (volume.vserver_id = vserver.id)
      JOIN cm_storage.qtree    ON (qtree.volume_id = volume.id)
      RIGHT JOIN playground.chargeback ON (
         chargeback.cluster_name = cluster.primary_address AND
         chargeback.vserver_name = vserver.name AND
         chargeback.volume_name = volume.name
     )
      WHERE volume.name IS NULL
      AND chargeback.cluster_name = '" + $aggregate['hostname'] + "'
      AND chargeback.vserver_name = '$vserver_name'
      AND chargeback.volume_name REGEXP '$vol_name_regexp'
      GROUP BY cb_cluster_name, cb_svm_name, cb_vol_name
      ORDER by chargeback.volume_name DESC
   ;"
 
   Get-WfaLogger -Info -Message $vol_select  
   $vols = invoke-MySqlQuery -query $vol_select -user root -password $mysql_pw
   if ( $vols[0] -ge 1 ){
      Get-WfaLogger -Info -Message $("Looking for highest idx for any existing vols in chargeback and not in cm_storage" )
      Get-WfaLogger -Info -Message $("highest idx volume: " + $vols[1].cb_vol_name )
      Get-WfaLogger -Info -Message $("vserver: " + $vols[1].cb_svm_name)
      Get-WfaLogger -Info -Message $(($vols[1].cb_vol_name -replace $($vols[1].cb_svm_name + "_"+$key+"_"), ''))
      $old_idx                     = ($vols[1].cb_vol_name -replace $($vols[1].cb_svm_name + "_"+$key+"_"), '').split('_')[0]
      Get-WfaLogger -Info -Message $("old_idx=" + $old_idx )
      $new_idx       = "{0:d3}" -f ( [int]$old_idx + 1 )
      $vol_name      = $vols[1].cb_vol_name -replace $old_idx, $new_idx
   }
   else {
   $vol_select = "
      SELECT
         volume.name         AS 'vol_name',
         vserver.name        AS 'vserver_name',
         cluster.name        AS 'cluster_name',
         cluster.primary_address AS 'cluster_pri_addr'
      FROM cm_storage.cluster
      JOIN cm_storage.node      ON (node.cluster_id = cluster.id)
      JOIN cm_storage.aggregate ON (aggregate.node_id = node.id)
      JOIN cm_storage.vserver   ON (vserver.cluster_id  = cluster.id)
      JOIN cm_storage.volume    ON (volume.vserver_id   = vserver.id)
     JOIN cm_storage.qtree     ON (qtree.volume_id     = volume.id)
      WHERE 1
         AND (cluster.name = '" + $aggregate['cluster'] + "' OR cluster.primary_address = '" + $aggregate['cluster'] + "')
         AND ( vserver.name = '$vserver_name' )
         AND volume.name REGEXP '$vol_name_regexp'
      ORDER by volume.name DESC
      ;"
   
    Get-WfaLogger -Info -Message "Looking for highest idx for any existing vols in cm_storage"
    Get-WfaLogger -Info -Message $vol_select   
   #----------------------------------------------------------------------
   # We sorted in desc order so the highest index volume is 1st in the
   # list of a volume was found
   #----------------------------------------------------------------------
   Get-WfaLogger -Info -Message $("Looking for highest idx for any existing vols" )
   $vols = invoke-MySqlQuery -query $vol_select -user root -password $mysql_pw
   if ( $vols[0] -ge 1 ){
      Get-WfaLogger -Info -Message $("highest idx volume: " + $vols[1].vol_name )
      Get-WfaLogger -Info -Message $("vserver: " + $vols[1].vserver_name)
      Get-WfaLogger -Info -Message $(($vols[1].vol_name -replace $($vols[1].vserver_name + "_"+$key+"_"), ''))
      $old_idx                     = ($vols[1].vol_name -replace $($vols[1].vserver_name + "_"+$key+"_"), '').split('_')[0]
      Get-WfaLogger -Info -Message $("old_idx=" + $old_idx )
      $new_idx       = "{0:d3}" -f ( [int]$old_idx + 1 )
      $vol_name      = $vols[1].vol_name -replace $old_idx, $new_idx
   }
   else{
      $vol_name      = $vserver_name + '_'+$key+'_001_' + $request['protocol'].ToLower()
   }
   }
 
   # Adding a bugfix. Replace $protocol with $request['protocol'].ToLower()
   if ( $request['protocol'].ToLower() -eq 'nfs' ){
      $security_style = 'unix'
   }
   else{
      $security_style = 'ntfs'
   }
 
   Get-WfaLogger -Info -Message $vol_name
  $return_values = @()
  if($request['service_level'] -eq "nas shared"){
   if($request['service_name'].ToLower() -eq "ediscovery")
   {
         $return_values += `
         '__res_type=ontap_volume;'                      + `
         'hostname='       + $aggregate['hostname']    + ',' + `
         'vserver='        + $vserver_name       + ',' + `
         'name='           + $vol_name                   + ',' + `
         'junction_path='  + '/' + $vol_name             + ',' + `
         'volume_security_style=' + $security_style             + ',' + `
         'encrypt=True'                                         + ',' + `
         'snapshot_policy=none'     + ',' + `
         'aggregate_name='  + $aggregate['name']
   }
   elseif($request['location'].ToLower() -eq "ind"){
         $return_values += `
         '__res_type=ontap_volume;'                      + `
         'hostname='       + $aggregate['hostname']    + ',' + `
         'vserver='        + $vserver_name       + ',' + `
         'name='           + $vol_name                   + ',' + `
         'junction_path='  + '/' + $vol_name             + ',' + `
         'volume_security_style=' + $security_style             + ',' + `
         'snapshot_policy=' + $request['service_name'].ToUpper().Substring(0,3) + '_' + $request['environment'].ToUpper() + '_Default'           + ',' + `
         'aggregate_name='  + $aggregate['name']
         
         }
  
   else{  
         $return_values += `
         '__res_type=ontap_volume;'                      + `
         'hostname='       + $aggregate['hostname']    + ',' + `
         'vserver='        + $vserver_name       + ',' + `
         'name='           + $vol_name                   + ',' + `
         'junction_path='  + '/' + $vol_name             + ',' + `
         'volume_security_style=' + $security_style             + ',' + `
         'encrypt=True'                                         + ',' + `
         'snapshot_policy=' + $request['service_name'].ToUpper().Substring(0,3) + '_' + $request['environment'].ToUpper() + '_Default'           + ',' + `
         'aggregate_name='  + $aggregate['name'] }
         }
 
  #---- JIRA GSSC-353 : Enable encryption of new NY MC3 mcc -----
 
  elseif (($request['location'].ToLower() -eq "nyc")){
         $return_values += `
         '__res_type=ontap_volume;'                      + `
         'hostname='       + $aggregate['hostname']    + ',' + `
         'vserver='        + $vserver_name       + ',' + `
         'name='           + $vol_name                   + ',' + `
         'junction_path='  + '/' + $vol_name             + ',' + `
         'volume_security_style=' + $security_style             + ',' + `
         'encrypt=True'                                         + ',' + `
         'snapshot_policy=' + $request['service_name'].ToUpper().Substring(0,3) + '_' + $request['environment'].ToUpper() + '_Default'     + ',' + `
         'aggregate_name='  + $aggregate['name']
  }
   else{
    $return_values += `
         '__res_type=ontap_volume;'                      + `
         'hostname='       + $aggregate['hostname']    + ',' + `
         'vserver='        + $vserver_name       + ',' + `
         'name='           + $vol_name                   + ',' + `
         'junction_path='  + '/' + $vol_name             + ',' + `
         'volume_security_style=' + $security_style             + ',' + `
         'snapshot_policy=' + $request['service_name'].ToUpper().Substring(0,3) + '_' + $request['environment'].ToUpper() + '_Default'           + ',' + `
         'aggregate_name='  + $aggregate['name'] }       
      
    $return_values += `
         '__res_type=ontap_volume_autosize;'                      + `
         'hostname='       + $aggregate['hostname']    + ',' + `
         'vserver='        + $vserver_name       + ',' + `
         'volume='           + $vol_name                   + ',' + `
         'maximum_size='   + $VOL_SIZE_STD_GB + 'g'    
    
   return @{
      'success'         = $True;
      'reason'          = "successfully defined new volume";
      'return_values'       = $return_values;
      'ontap_volume'    = @{
         'hostname'     = $aggregate['hostname'];
         'vserver'      = $vserver_name;
         'name'         = $vol_name;
         'junction_path'   = '/' + $vol_name;
         'volume_security_style'  = $security_style;
         'aggregate_name'  = $aggregate['name']
      }
   }
}
#--------------------------------------------------------------------
# FUNCTION: vol_helper_find_unprovisioned()
#  Search the chargeback table to see if there are any volumes that
#  we know will be provisioned but haven't yet been discovered by
#  WFA.  If there are any and they meet the necessary criteria,
#  return the best one.  If none, return nothing.
#--------------------------------------------------------------------
 
#--- NETAPPMS-55 - SSNAP not select DCN cluster ---#
#--- NETAPPMS-56 - SSNAP to include Aggregate check ( use volume on aggr less than 85% ) for existing volume selection ---#
# Date : 30-June-2023
# As part of troubleshooting for defect NETAPPMS-55 it was found that chargeback table always
# listed at least one volume on which any qtree was deleted. To remediate this, qtree parameter on sql query has been removed
# and check is bieng made only on volume level. This helped to pick the correct un-provisioned volume.
 
function vol_helper_find_unprovisioned(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [array]$vservers,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   $vserver_list = @()
   foreach ( $vserver in $vservers ){
      $vserver_list += $vserver['name']
   }
   $key='data'
   if($request['service_name'] -eq $FABRIC){
      $key=$FABRIC.ToLower()
   }
   $vserver_regexp   = '^(' + ($vserver_list -join '|') + ')$'
  
   $vol_name_regexp  = '^(' + ($vserver_list -join '|') + ')'  + `
                       '_'+$key+'_[0-9]{' +$VOL_NAME_IDX_DIGITS  + '}_' + `
                        $request['protocol']
 
   $total_share_size = $request['storage_instance_count'] * $request['storage_requirement']
   #----------------------------------------------------
   # See if there is anything in the chargeback table
   # not in WFA.
   #----------------------------------------------------  
   $vol_select = "
      SELECT
         cluster.primary_address  AS 'cluster_name',
         vserver.name  AS 'vserver_name',
         volume.name   AS 'vol_name',
         chargeback.cluster_name AS 'cb_cluster_name',
         chargeback.vserver_name AS 'cb_svm_name',
         chargeback.volume_name  AS 'cb_vol_name',
         (SUM(storage_requirement_gb)+$total_share_size)/($VOL_SIZE_STD_GB) AS 'usage'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver ON (vserver.cluster_id = cluster.id)
      JOIN cm_storage.volume  ON (volume.vserver_id = vserver.id)
      RIGHT JOIN playground.chargeback ON (
         chargeback.cluster_name = cluster.primary_address AND
         chargeback.vserver_name = vserver.name AND
         chargeback.volume_name = volume.name
      )
      WHERE volume.name IS NULL
      AND chargeback.volume_name REGEXP '$vol_name_regexp'
      GROUP BY cb_cluster_name, cb_svm_name, cb_vol_name
      HAVING ((SUM(storage_requirement_gb)+$total_share_size)/($VOL_SIZE_STD_GB)) <= $VOL_NEW_PROV_USAGE_MAX_PCT
      ORDER by ((SUM(storage_requirement_gb)+$total_share_size)/($VOL_SIZE_STD_GB)) ASC
   ;"
 
   Get-WfaLogger -Info -Message $vol_select
   $vols = invoke-MySqlQuery -query $vol_select -user root -password $mysql_pw
 
   if ( $vols[0] -ge 1 ){
      #--------------------------------------------------------------------
      # We did find at least 1 suitable volume in the chargeback table,
      # so let's grab the info we need to populate the return data from WFA
      # and setup our return
      #--------------------------------------------------------------------
      $sql = "
         SELECT
            cluster.primary_address    AS 'mgmt_ip'
         FROM
            cm_storage.cluster
         WHERE
            cluster.name = '" + $vols[1].cb_cluster_name + "'
            OR
            cluster.primary_address = '" + $vols[1].cb_cluster_name +"'
      ;"
 
      Get-WfaLogger -Info -Message $sql
      $cluster = invoke-MySqlQuery -query $sql -user root -password $mysql_pw
      if ( $cluster[0] -ge 1 ){
         #----------------------------------------------------------------
         # We found an existing unprovisioned volume so we don't add to
         # the data gets returned from WFA because that would cause the
         # volume to be provisioned again (not really due to Ansible, but
         # I'm just not tempting fate)
         #----------------------------------------------------------------
         return @{
            'success'         = $True;
            'reason'          = "successfully found unprovisioned volume";
            'return_values'       = @();
            'ontap_volume'    = @{
               'hostname'     = $cluster[1]['mgmt_ip'];
               'vserver'      = $vols[1]['cb_svm_name'];
               'name'         = $vols[1]['cb_vol_name'];
            }
         }
      }
      else{
         #----------------------------------------------------------------
         # For some odd reason we found a cluster in the chargeback table
         # that doesn't seem to match in WFA's tables, we need to fail on
         # that.
         #----------------------------------------------------------------
         return @{
            'success'         = $False;
            'reason'          = "Found cluster in chargeback table not in WFA";
            'return_values'   = @();
            'ontap_volume'    = @{}
         }
      }
 
   }
   else{
   Get-WfaLogger -Info -Message "Entered else"
      return @{
         'success'         = $False;
         'reason'          = "No pending provisions";
         'return_values'   = @();
         'ontap_volume'    = @{}
      }
   }
}
 
#--------------------------------------------------------------------
# FUNCTION: cvo_vol_helper_prov_new()
#  Return attributes to provision an entirely new CVO volume
#--------------------------------------------------------------------
 
function cvo_vol_helper_prov_new() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [array]$vservers,
      [parameter(Mandatory=$true)]
      [hashtable]$aggregate,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
   #----------------------------------------------------------------------
   # We earlied delayed failure if we could not find a suitable aggr since
   # failure for a resource we may not need doesn't make sense.  But now,
   # we'll actually need that aggr, so before we do anything, check to see
   # that we actually got one and now it's time to bail if not.
   #----------------------------------------------------------------------
   if ( $aggregate.Count -eq 0 ){
      return @{
         'success'         = $False;
         'reason'          = "We need an aggr for a new volume but couldn't find one";
         'return_values'       = @();
         'ontap_volume'    = @{}
      }
   }
  
   $vserver_list = @()
   foreach ( $vserver in $vservers ){
     $vserver_list += $vserver['name']
   }
   #----------------------------------------------------------------------
   # We know we need a brand new volume and we have already picked the
   # cluster on which it will go due to the aggr selection.  This also
   # implies that of all possible vservers, there is only 1 that is on the
   # matching cluster.  So let's just pick that one here and use it
   # throughout.  So just find the vserver that sits on the same cluster as
   # the aggr that we already picked.  We do this by matching the cluster
   # hostnames.
   #----------------------------------------------------------------------
 
   #TODO volume count check per vserver
   $vserver_idx   = 0
   Get-WfaLogger -Info -Message "Entered function cvo_vol_helper_prov_new()"
   Get-WfaLogger -Info -Message $vservers.Count
   Get-WfaLogger -Info -Message $aggregate.Count
   Get-WfaLogger -Info -Message $aggregate['hostname']
   Do{
     
      $vserver_found = $vservers[$vserver_idx]['hostname'] -eq $aggregate['hostname']
      Get-WfaLogger -Info -Message $vservers[$vserver_idx]['hostname']
      Get-WfaLogger -Info -Message $vserver_found
      $vserver_idx += 1
 
   }While (-not $vserver_found -and ($vserver_idx -le $vservers.length))
 
   if ( $vserver_found ){
      $vserver_name = $vservers[$vserver_idx-1]['name']
      Get-WfaLogger -Info -Message $vserver_name
   }
   else{
      # This should never happen, but let's just make sure we catch it if it does
      return @{
         'success'         = $False;
         'reason'          = "Failed to match existing vserver to selected aggr";
         'return_values'   = @();
         'ontap_volume'    = @{}
      }
   }
 
   $key=$request['nar_id'].replace('-','_')
 
   $vol_name_regexp  = '^(' + ($vserver_list -join '|') + ')'  + `
                       '_'+$key+'_[0-9]{' +$VOL_NAME_IDX_DIGITS  + '}_' + `
                        $request['protocol'].ToLower()
 
   $total_cvo_usage = "
      SELECT
         cluster.primary_address  AS 'cluster_name',
         (SUM(cm_storage.volume.size_mb))/1024/1024 AS 'usage'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver ON (vserver.cluster_id = cluster.id)
      JOIN cm_storage.volume  ON (volume.vserver_id = vserver.id)
      WHERE volume.name REGEXP '$vol_name_regexp'
      AND vserver.name = '$vserver_name'
      GROUP BY cluster_name
      ORDER by 'usage' DESC
   ;"
   Get-WfaLogger -Info -Message $total_cvo_usage
   $total_cvo_usage_data = invoke-MySqlQuery -query $total_cvo_usage -user root -password $mysql_pw
 
   if ( $total_cvo_usage_data[0] -ge 1 ){
      Get-WfaLogger -Info -Message $("Vol usage: " + $total_cvo_usage_data[1].usage )
      if ( $total_cvo_usage_data[1].usage -ge $CVO_MAX_VOL_SIZE )
      {
         return @{
            'success'         = $False;
            'reason'          = "Total alocation capacity of CVO filled. Please create new CVO";
            'return_values'   = @();
            'ontap_volume'    = @{}
         }
      }
   }
 
  
   Get-WfaLogger -Info -Message "Getting highest idx from any volume unprovisioned yet"
  
   $vol_select = "
      SELECT
         cluster.primary_address  AS 'cluster_name',
         vserver.name  AS 'vserver_name',
         volume.name   AS 'vol_name',
         cvo_chargeback.cluster_name AS 'cb_cluster_name',
         cvo_chargeback.vserver_name AS 'cb_svm_name',
         cvo_chargeback.volume_name  AS 'cb_vol_name'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver ON (vserver.cluster_id = cluster.id)
      JOIN cm_storage.volume  ON (volume.vserver_id = vserver.id)
      RIGHT JOIN playground.cvo_chargeback ON (
         cvo_chargeback.cluster_name = cluster.primary_address AND
         cvo_chargeback.vserver_name = vserver.name AND
         cvo_chargeback.volume_name = volume.name
     )
      WHERE volume.name IS NULL
      AND cvo_chargeback.cluster_name = '" + $aggregate['hostname'] + "'
      AND cvo_chargeback.vserver_name = '$vserver_name'
      AND cvo_chargeback.volume_name REGEXP '$vol_name_regexp'
      GROUP BY cb_cluster_name, cb_svm_name, cb_vol_name
      ORDER by cvo_chargeback.volume_name DESC
   ;"
 
   Get-WfaLogger -Info -Message $vol_select  
   $vols = invoke-MySqlQuery -query $vol_select -user root -password $mysql_pw
   if ( $vols[0] -ge 1 ){
      Get-WfaLogger -Info -Message $("Looking for highest idx for any existing vols in chargeback and not in cm_storage" )
      Get-WfaLogger -Info -Message $("highest idx volume: " + $vols[1].cb_vol_name )
      Get-WfaLogger -Info -Message $("vserver: " + $vols[1].cb_svm_name)
      Get-WfaLogger -Info -Message $(($vols[1].cb_vol_name -replace $($vols[1].cb_svm_name + "_"+$key+"_"), ''))
      $old_idx                     = ($vols[1].cb_vol_name -replace $($vols[1].cb_svm_name + "_"+$key+"_"), '').split('_')[0]
      Get-WfaLogger -Info -Message $("old_idx=" + $old_idx )
      $new_idx       = "{0:d3}" -f ( [int]$old_idx + 1 )
      $vol_name      = $vols[1].cb_vol_name -replace "_$old_idx", "_$new_idx"
   }
   else {
   $vol_select = "
      SELECT
         volume.name         AS 'vol_name',
         vserver.name        AS 'vserver_name',
         cluster.name        AS 'cluster_name',
         cluster.primary_address AS 'cluster_pri_addr'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver   ON (vserver.cluster_id  = cluster.id)
      JOIN cm_storage.volume    ON (volume.vserver_id   = vserver.id)
      WHERE 1
         AND (cluster.name = '" + $aggregate['cluster'] + "' OR cluster.primary_address = '" + $aggregate['cluster'] + "')
         AND ( vserver.name = '$vserver_name' )
         AND volume.name REGEXP '$vol_name_regexp'
      ORDER by volume.name DESC
      ;"
   
    Get-WfaLogger -Info -Message "Looking for highest idx for any existing vols in cm_storage"
    Get-WfaLogger -Info -Message $vol_select   
   #----------------------------------------------------------------------
   # We sorted in desc order so the highest index volume is 1st in the
   # list of a volume was found
   #----------------------------------------------------------------------
   Get-WfaLogger -Info -Message $("Looking for highest idx for any existing vols" )
   $vols = invoke-MySqlQuery -query $vol_select -user root -password $mysql_pw
   if ( $vols[0] -ge 1 ){
      Get-WfaLogger -Info -Message $("highest idx volume: " + $vols[1].vol_name )
      Get-WfaLogger -Info -Message $("vserver: " + $vols[1].vserver_name)
      Get-WfaLogger -Info -Message $(($vols[1].vol_name -replace $($vols[1].vserver_name + "_"+$key+"_"), ''))
      $old_idx                     = ($vols[1].vol_name -replace $($vols[1].vserver_name + "_"+$key+"_"), '').split('_')[0]
      Get-WfaLogger -Info -Message $("old_idx=" + $old_idx )
      $new_idx       = "{0:d3}" -f ( [int]$old_idx + 1 )
      Get-WfaLogger -Info -Message $("new name = $($vols[1].vol_name -replace "_$old_idx_", "_$new_idx_")")
      $vol_name      = $vols[1].vol_name -replace "_$old_idx", "_$new_idx"
   }
   else{
      $vol_name      = $vserver_name + '_'+$key+'_001_' + $request['protocol'].ToLower()
   }
   }
 
   # Adding a bugfix. Replace $protocol with $request['protocol'].ToLower()
   if ( $request['protocol'].ToLower() -eq 'nfs' ){
      $security_style = 'unix'
   }
   else{
      $security_style = 'ntfs'
   }
 
   Get-WfaLogger -Info -Message $vol_name
   $return_values = @()
 
   $return_values += `
   '__res_type=cvo_ontap_volume;'                      + `
   'hostname='       + $aggregate['hostname']    + ',' + `
   'vserver='        + $vserver_name       + ',' + `
   'name='           + $vol_name                   + ',' + `
   'junction_path='  + '/' + $vol_name             + ',' + `
   'volume_security_style=' + $security_style             + ',' + `
   'size='   + [string]$request['storage_requirement'] + ',' + `
   'size_unit='  + $STORAGE_REQUIREMENT_UNITS + ',' + `
   'snapshot_policy=' + $request['service_name'].ToUpper().Substring(0,3) + '_' + $request['environment'].ToUpper() + '_Default'           + ',' + `
   'aggregate_name='  + $aggregate['name']    + ',' + `
   'tiering_control=best_effort'  + ',' + `
   'tiering_policy=auto'
 
   Get-WfaLogger -Info -Message $($return_values | out-string)
 
   return @{
      'success'         = $True;
      'reason'          = "successfully defined new volume";
      'return_values'   = $return_values;
      'ontap_volume'    = @{
         'hostname'     = $aggregate['hostname'];
         'vserver'      = $vserver_name;
         'name'         = $vol_name;
         'junction_path'   = '/' + $vol_name;
         'volume_security_style'  = $security_style;
         'aggregate_name'  = $aggregate['name']
      }
   }
}
 
# snapvault volume creation
 
function snapvault_volume(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true, HelpMessage="placement solution")]
      [hashtable]$placement_solution,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
   $snapvault_volume_data = @()
   $snapvault_dr_volume_data = @()
   $return_values = @()
   $snapvault_volume_required = $False
 
   Get-WfaLogger -Info -Message $( "ServieNow Request Inputs " + $request)
 
   $volume  = $placement_solution['resources']['ontap_volume']
   $primary_cluster_name = $placement_solution['resources']['ontap_volume']['hostname']
   $primary_vserver_name = $placement_solution['resources']['ontap_volume']['vserver']
   $peer_cluster_regex = "$($primary_cluster_name.Substring(0,6))sv"
   $peer_vserver_regex = "$($primary_vserver_name.Substring(0,6))sv"
 
   if ( $request['protocol'].ToLower() -eq 'nfs' ){
      $security_style = 'unix'
   }
   else{
      $security_style = 'ntfs'
   }
 
   Get-WfaLogger -Info -Message ($placement_solution['return_values'].Contains('__res_type=ontap_volume;'))
  
   foreach($data in $placement_solution['return_values']){
      if($data.Contains('__res_type=ontap_volume;')){
         $snapvault_volume_required = $true
      }
   }
   Get-WfaLogger -Info -Message $snapvault_volume_required
   if ($snapvault_volume_required){
      #if($request['service_level'].ToLower() -eq $NAS_PREMIUM -and `
         #$request['location'].ToLower() -eq 'nyc'){
 
            # search SV cluster
 
            $snapvault_cluster = "
            SELECT
               primary_cluster.primary_address AS primary_cluster_name,
               peer_cluster.primary_address AS peer_cluster_name
            FROM
               cm_storage.cluster_peer
            JOIN
               cm_storage.cluster AS primary_cluster ON cluster_peer.primary_cluster_id = primary_cluster.id
            JOIN
               cm_storage.cluster AS peer_cluster ON cluster_peer.peer_cluster_id = peer_cluster.id
            WHERE
               primary_cluster.primary_address = '$primary_cluster_name'
            AND
               peer_cluster.name LIKE '%$peer_cluster_regex%'
            ;"
 
            Get-WfaLogger -Info -Message $snapvault_cluster
            Get-WfaLogger -Info -Message $("Looking for snapvault cluster" )
            $sv_cluster = Invoke-MySqlQuery -query $snapvault_cluster -user root -password $mysql_pw
 
            if ( $sv_cluster[0] -ge 1 ){
               Get-WfaLogger -Info -Message $("Found SnapVault Cluster: " + $sv_cluster[1].peer_cluster_name )
               }
 
            # search SV DR cluster
 
            $snapvault_dr_cluster = "
            SELECT
               primary_cluster.primary_address AS primary_cluster_name,
               peer_cluster.primary_address AS peer_cluster_name
            FROM
               cm_storage.cluster_peer
            JOIN
               cm_storage.cluster AS primary_cluster ON cluster_peer.primary_cluster_id = primary_cluster.id
            JOIN
               cm_storage.cluster AS peer_cluster ON cluster_peer.peer_cluster_id = peer_cluster.id
            WHERE
               primary_cluster.name LIKE '%$peer_cluster_regex%'
            AND
               peer_cluster.name LIKE '%sv%'
            ;"
           
            Get-WfaLogger -Info -Message $snapvault_dr_cluster
            Get-WfaLogger -Info -Message $("Looking for snapvault cluster DR" )
            $sv_dr_cluster = Invoke-MySqlQuery -query $snapvault_dr_cluster -user root -password $mysql_pw
 
            if ( $sv_dr_cluster[0] -ge 1 ){
               Get-WfaLogger -Info -Message $("Found SnapVault DR Cluster: " + $sv_dr_cluster[1].peer_cluster_name )
               }
 
            # search SV aggr
 
            $aggr_select_sv = "
            SELECT
               cluster.name         AS 'cluster_name',
               cluster.primary_address AS 'hostname',
               node.name            AS 'node_name',
               aggregate.name       AS 'name'
            FROM cm_storage.cluster
            JOIN cm_storage.node ON (node.cluster_id = cluster.id)
            JOIN cm_storage.aggregate ON (aggregate.node_id = node.id)
            WHERE 1
               AND cluster.primary_address = '$($sv_cluster[1].peer_cluster_name)'
               AND aggregate.name NOT LIKE 'aggr0%'
               AND aggregate.name NOT LIKE '%root%'
               AND aggregate.name NOT LIKE '%dr%'
               AND aggregate.is_snaplock = 'false'
               AND (aggregate.used_size_mb/aggregate.size_mb) <= 0.9
            ORDER BY aggregate.available_size_mb DESC
            ;"
 
            Get-WfaLogger -Info -Message $aggr_select_sv
            Get-WfaLogger -Info -Message $("Looking for an aggr" )
            $aggrs_sv = Invoke-MySqlQuery -query $aggr_select_sv -user root -password $mysql_pw
 
            if ( $aggrs_sv[0] -ge 1 ){
               Get-WfaLogger -Info -Message $("Found aggr: " + $aggrs_sv[1].name )
               }
 
            # search SV DR aggr
 
            $aggr_select_sv_dr = "
            SELECT
               cluster.name         AS 'cluster_name',
               cluster.primary_address AS 'hostname',
               node.name            AS 'node_name',
               aggregate.name       AS 'name'
            FROM cm_storage.cluster
            JOIN cm_storage.node ON (node.cluster_id = cluster.id)
            JOIN cm_storage.aggregate ON (aggregate.node_id = node.id)
            WHERE 1
               AND cluster.primary_address = '$($sv_dr_cluster[1].peer_cluster_name)'
               AND aggregate.name NOT LIKE 'aggr0%'
               AND aggregate.name NOT LIKE '%root%'
               AND aggregate.name LIKE '%dr%'
               AND aggregate.is_snaplock = 'false'
               AND (aggregate.used_size_mb/aggregate.size_mb) <= 0.9
            ORDER BY aggregate.available_size_mb DESC
            ;"
 
            Get-WfaLogger -Info -Message $aggr_select_sv_dr
            Get-WfaLogger -Info -Message $("Looking for an aggr" )
            $aggrs_dr_sv = Invoke-MySqlQuery -query $aggr_select_sv_dr -user root -password $mysql_pw
 
            if ( $aggrs_dr_sv[0] -ge 1 ){
               Get-WfaLogger -Info -Message $("Found aggr: " + $aggrs_dr_sv[1].name )
               }
 
            # search SV vserver
 
            $snapvault_vserver = "
 
            SELECT
               primary_vserver.name AS primary_vserver_name,
               peer_vserver.name AS peer_vserver_name
            FROM
               cm_storage.vserver_peer
            JOIN
               cm_storage.vserver AS primary_vserver ON vserver_peer.vserver_id = primary_vserver.id
            JOIN
               cm_storage.vserver AS peer_vserver ON vserver_peer.peer_vserver_id = peer_vserver.id
            JOIN
               cm_storage.cluster ON primary_vserver.cluster_id = cluster.id
            WHERE
               cluster.primary_address = '$primary_cluster_name'
            AND
               primary_vserver.name = '$primary_vserver_name'
            AND
               peer_vserver.name LIKE '%$($peer_vserver_regex)%'
            ;"
 
            Get-WfaLogger -Info -Message $snapvault_vserver
            Get-WfaLogger -Info -Message $("Looking for snapvault svm" )
            $sv_vserver = Invoke-MySqlQuery -query $snapvault_vserver -user root -password $mysql_pw
 
            if ( $sv_vserver[0] -ge 1 ){
               Get-WfaLogger -Info -Message $("Found snapvault svm: " + $sv_vserver[1].peer_vserver_name )
               }
 
 
            # search SV dr vserver
 
            $snapvault_dr_vserver = "
 
            SELECT
               primary_vserver.name AS primary_vserver_name,
               peer_vserver.name AS peer_vserver_name
            FROM
               cm_storage.vserver_peer
            JOIN
               cm_storage.vserver AS primary_vserver ON vserver_peer.vserver_id = primary_vserver.id
            JOIN
               cm_storage.vserver AS peer_vserver ON vserver_peer.peer_vserver_id = peer_vserver.id
            JOIN
               cm_storage.cluster ON primary_vserver.cluster_id = cluster.id
            WHERE
               cluster.primary_address = '$($sv_cluster[1].peer_cluster_name)'
            AND
               primary_vserver.name LIKE '%$($sv_vserver[1].peer_vserver_name)%'
            AND
               peer_vserver.name LIKE '%dr%'
            ;"
 
            Get-WfaLogger -Info -Message $snapvault_dr_vserver
            Get-WfaLogger -Info -Message $("Looking for snapvault DR svm" )
            $sv_dr_vserver = Invoke-MySqlQuery -query $snapvault_dr_vserver -user root -password $mysql_pw
 
            if ( $sv_dr_vserver[0] -ge 1 ){
               Get-WfaLogger -Info -Message $("Found snapvault DR svm: " + $sv_dr_vserver[1].peer_vserver_name )
               }
 
            $snapvault_volume_data += @{
               'hostname'     = $sv_cluster[1].peer_cluster_name;
               'vserver'      = $sv_vserver[1].peer_vserver_name;
               'name'         = $volume['name'] + '_vault';
               'junction_path'   = '/' + $volume['name'] + '_vault';
               'volume_security_style'  = $security_style;
               'aggregate_name'  = $aggrs_sv[1].name;
               'type'            = 'DP';
            }
           
            Get-WfaLogger -Info -Message "Set snapvault volume return values"
            $return_values += `
               '__res_type=snapvault_ontap_volume;'                      + `
               'hostname='       + $sv_cluster[1].peer_cluster_name    + ',' + `
               'vserver='        + $sv_vserver[1].peer_vserver_name       + ',' + `
               'name='           + $volume['name'] + '_vault'                  + ',' + `
               'volume_security_style=' + $security_style             + ',' + `
               'encrypt=True'                                         + ',' + `
               'type=DP'                                         + ',' + `
               'snapshot_policy=none'                            + ',' + `
               'aggregate_name='  + $aggrs_sv[1].name
 
            $snapvault_dr_volume_data += @{
               'hostname'     = $sv_dr_cluster[1].peer_cluster_name;
               'vserver'      = $sv_dr_vserver[1].peer_vserver_name;
               'name'         = $volume['name'] + '_vault';
               'volume_security_style'  = $security_style;
               'aggregate_name'  = $aggrs_dr_sv[1].name;
               'type'            = 'DP';
            }
           
            Get-WfaLogger -Info -Message "Set snapvault DR volume return values"
            $return_values += `
               '__res_type=snapvault_ontap_volume;'                      + `
               'hostname='       + $sv_dr_cluster[1].peer_cluster_name    + ',' + `
               'vserver='        + $sv_dr_vserver[1].peer_vserver_name       + ',' + `
               'name='           + $volume['name'] + '_vault'                  + ',' + `
               'volume_security_style=' + $security_style             + ',' + `
               'encrypt=True'                                         + ',' + `
               'type=DP'                                         + ',' + `
               'snapshot_policy=none'                            + ',' + `
               'aggregate_name='  + $aggrs_dr_sv[1].name
            
            return @{
               'success'         = $True;
               'reason'          = "successfully built snapvault volume placement";
               'return_values'   = $return_values;
               'ontap_snapvault_volume'     = $snapvault_volume_data
               'ontap_snapvault_dr_volume'  = $snapvault_dr_volume_data
            }
         }
  
   
   else{
      return @{
         'success'      = $False;
         'reason'       = "Failed to find placement logic for snapvault volume"
         'ontap_snapvault_volume'   = @{}
         'ontap_snapvault_dr_volume' = @{}
         'return_values'   = $return_values;
         }
      }
  
}
 
#SnapVault Relationship creation
 
function snapvault(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true, HelpMessage="placement solution")]
      [hashtable]$placement_solution
   )
   $return_values = @()
 
   Get-WfaLogger -Info -Message "preparing inputs for snapvault relationship"
 
   $primary_volume      = $placement_solution['resources']['ontap_volume']
   $snapvault_volume    = $placement_solution['resources']['ontap_snapvault_volume'][0]
   $snapvault_dr_volume = $placement_solution['resources']['ontap_snapvault_dr_volume'][0]
  
   Get-WfaLogger -Info -Message "After preparing inputs for snapvault relationship"
 
   $return_values += `
         '__res_type=ontap_snapmirror;'                + `
         'hostname='       + $snapvault_volume['hostname']       + ',' + `
         'src_vserver='    + $primary_volume['vserver']          + ',' + `
         'dest_vserver='   + $snapvault_volume['vserver']        + ',' + `
         'src_volume='     + $primary_volume['name']             + ',' + `
         'dest_volume='    + $snapvault_volume['name']           + ',' + `
         'schedule='       + 'daily'                             + ',' + `
         'policy='         + 'GFS_PRD_VAULT'
 
   $return_values += `
         '__res_type=ontap_snapmirror;'                + `
         'hostname='       + $snapvault_dr_volume['hostname']    + ',' + `
         'src_vserver='    + $snapvault_volume['vserver']        + ',' + `
         'dest_vserver='   + $snapvault_dr_volume['vserver']     + ',' + `
         'src_volume='     + $snapvault_volume['name']           + ',' + `
         'dest_volume='    + $snapvault_dr_volume['name']        + ',' + `
         'schedule='       + 'snapmirror01'                      + ',' + `
         'policy='         + 'MirrorAllSnapshots'
 
        
   return @{
            'success'         = $true;
            'reason'          = "Create SnapVault Relationship";
            'return_values'   = $return_values;
         }
        
}
 
function qtree() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$volume,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   $qtree_service = $request['service_name'].ToLower()
   $qtree_service = $qtree_service.Substring(0,3)
   $qtree_regex = $qtree_service + '_' + $request['environment'].ToLower() + '_[0-9]{' + $QTREE_NUM_DIGITS + '}$'
   #----------------------------------------------------------------------
   # RTU 21 Sep 2020
   # The naming convention for qtrees was changed as part of this work.
   # Therefore, it's very unlikely that there will be names in existence
   # when this code starts being used such that they match the pattern that
   # we are looking for.  So we are going to use the chargeback table
   # exclusively to determine qtree names.
   #
   # Also, it's possible that some downstream error could mean that a
   # qtree name found in this table actually doesn't exist.  Given the
   # maximum number of qtrees we can have with 5 digits, I don't think
   # that's a problem so I'm just going to ignore that situation.  This
   # also means it's possible that actual qtree names will have gaps in
   # numeric index values.
   #----------------------------------------------------------------------
   $qtree_select = "
      SELECT
         qtree_name  AS 'qtree_name'
      FROM playground.chargeback
      WHERE 1        
         AND chargeback.qtree_name             REGEXP '$qtree_regex'
      ORDER BY qtree_name DESC
   ;
   "
 
   Get-WfaLogger -Info -Message "Looking for qtrees on the volume"
   Get-WfaLogger -Info -Message $qtree_select
   $qtrees = Invoke-MySqlQuery -query $qtree_select -user root -password $mysql_pw
   #-----------------------------------------------------------------
   # FIXME: RTU 14 Oct 2020
   # NETAPP-81
   # Change this to return a list of qtrees whose numbers run in
   # sequence starting with the highest index value determined
   #-----------------------------------------------------------------
   if ( $qtrees[0] -ge 1 ){
      Get-WfaLogger -Info -Message $("Will use qtree: " + $qtrees[1].qtree_name)
      $old_idx    = ($qtrees[1].qtree_name).split('_')[$QTREE_FLD_IDX]
      $new_idx    = [int]$old_idx + 1
   }
   else{
      Get-WfaLogger -Info -Message "None, this is the 1st"
      $new_idx    = 1
      $qtree_name    = $qtree_service + '_' + $request['environment'].ToLower() + '_' + $new_idx_str
      Get-WfaLogger -Info -Message $qtree_name
   }
 
   $qtrees        = @()
   $return_values = @()
   for( $idx=$new_idx; $idx -lt $new_idx+$request['storage_instance_count']; $idx +=1 ){
      $new_idx_str   = "{0:d$QTREE_NUM_DIGITS}" -f ( $idx )
      $qtree_name    = $qtree_service + '_' + $request['environment'].ToLower() + '_' + $new_idx_str
      Get-WfaLogger -Info -Message $("qtree_name=" + $qtree_name)
      $qtrees += @{
         'hostname'     = $volume['hostname'];
         'vserver'      = $volume['vserver'];
         'flexvol_name' = $volume['name'];
         'name'         = $qtree_name
      }
      Get-WfaLogger -Info -Message "Set qtree return values"
      if($request['service_name'].ToLower() -eq $FABRIC){
      $return_values +=                                    `
         '__res_type=ontap_qtree;'                 +       `
         'hostname='        + $volume['hostname']  + ',' + `
         'vserver='         + $volume['vserver']   + ',' + `
         'flexvol_name='    + $volume['name']      + ',' + `
         'unix_permissions=777'                    + ',' + `
         'name='            + $qtree_name }
     
      else {
      $return_values +=                                    `
         '__res_type=ontap_qtree;'                 +       `
         'hostname='        + $volume['hostname']  + ',' + `
         'vserver='         + $volume['vserver']   + ',' + `
         'flexvol_name='    + $volume['name']      + ',' + `
         'name='            + $qtree_name }
 
         Get-WfaLogger -Info -Message "qtree return values have been set"
   }
   #-----------------------------------------------------------------
   # FIXME: RTU 14 Oct 2020
   # NETAPP-81
   # This will need to change to a list of qtrees and any code that
   # assumes a single qtree will need to change as well.
   #-----------------------------------------------------------------
   Get-WfaLogger -Info -Message $("qtrees size: " + $qtrees.length)
   Get-WfaLogger -Info -Message $("return values size: " + $return_values.length)
   return @{
      'success'         = $True;
      'reason'          = "successfully built qtree name";
      'return_values'   = $return_values;
      'ontap_qtree'     = $qtrees
   }
}
 
function quota() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [array]$qtrees,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
   #-----------------------------------------------------------------
   # FIXME: RTU 14 Oct 2020
   # NETAPP-81
   # We will now support multiple qtrees so this must change
   # accordingly
   #-----------------------------------------------------------------
   Get-WfaLogger -Info -Message "Adding quotas to qtrees"
   $return_values = @()
   $quotas        = @()
   foreach ( $qtree in $qtrees ){
      Get-WfaLogger -Info -Message $( "Adding quotas to qtree: " + $qtree['name'])
      $quotas += @{
         'hostname'     = $qtree['hostname'];
         'vserver'      = $qtree['vserver'];
         'volume'       = $qtree['flexvol_name'];
         'quota_target' = '/vol/' + $qtree['flexvol_name'] + '/' + $qtree['name'];
         'disk_limit'   = [string]$request['storage_requirement'] + $STORAGE_REQUIREMENT_UNITS_QUOTAS
      }
     Get-WfaLogger -Info -Message $( "Adding return values for qtree: " + $qtree['name'])
      $return_values += `
         '__res_type=ontap_quota;'                                                     + `
         'hostname='          + $qtree['hostname']                              + ',' + `
         'vserver='           + $qtree['vserver']                               + ',' + `
         'volume='            + $qtree['flexvol_name']                                  + ',' + `
         'quota_target='      + '/vol/' + $qtree['flexvol_name'] + '/' + $qtree['name'] + ',' + `
         'disk_limit='        + [string]$request['storage_requirement'] + $STORAGE_REQUIREMENT_UNITS_QUOTAS
   }
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
 
   #-----------------------------------------------------------------
   # FIXME: RTU 14 Oct 2020
   # NETAPP-81
   # We will now support multiple qtrees so this must change
   # accordingly
   #-----------------------------------------------------------------
   # Return 3 items:
   # 1.  A list of export policies to provision
   # 2.  A list of rules to add to policies
   # 3.  A list of volumes/qtrees to update policy name
   #-----------------------------------------------------------------
 
   $return_values = @()
   $nfs_export_resource = @()
   foreach ( $qtree in $qtrees ){
   if($request['service_name'].ToLower() -ne $FABRIC){
      Get-WfaLogger -Info -Message $qtree['name']
      $qtree_flds = $qtree['name'].split('_')
      Get-WfaLogger -Info -Message $qtree_flds[$QTREE_FLD_IDX]
      $return_values += `
         '__res_type=ontap_export_policy;'               + `
         'hostname='       + $qtree['hostname']   + ',' + `
         'vserver='        + $qtree['vserver']      + ',' + `
         'name='           + $qtree['flexvol_name'] + '_' + $qtree_flds[$QTREE_FLD_IDX]
      if ( $request.ContainsKey('netgroup_ro') -and ($request['netgroup_ro'].length -ge 1 ) ){
         $return_values += `
         '__res_type=ontap_export_policy_rule;'          + `
         'hostname='       + $qtree['hostname']   + ',' + `
         'vserver='        + $qtree['vserver']      + ',' + `
         'name='           + $qtree['flexvol_name'] + '_' + $qtree_flds[$QTREE_FLD_IDX]       + ',' + `
         'client_match='   + '@' + $request['netgroup_ro'] + ',' + `
         'ro_rule='        + 'sys'                 + ',' + `
         'rw_rule='        + 'none'                 + ',' + `
         'super_user_security='  + 'none'          + ',' + `
         'anonymous_user_id='    + '65534'          + ',' + `
         'allow_suid='           + 'false'          + ',' + `
         'protocol='              + $request['protocol_version']
      }
#------- NETAPPMS-169  : SSNAP - Change to NFS Export permissions to satisfy audit ---- 
 
      $return_values += `
            '__res_type=ontap_export_policy_rule;'          + `
            'hostname='       + $qtree['hostname']   + ',' + `
            'vserver='        + $qtree['vserver']      + ',' + `
            'name='           + $qtree['flexvol_name'] + '_' + $qtree_flds[$QTREE_FLD_IDX]       + ',' + `
            'client_match='   + '@' + $request['netgroup_rw'] + ',' + `
            'ro_rule='        + 'sys'                 + ',' + `
            'rw_rule='        + 'sys'                 + ',' + `
            'super_user_security='  + 'none'          + ',' + `
            'anonymous_user_id='    + '65534'          + ',' + `
            'allow_suid='           + 'false'          + ',' + `
            'protocol='             + $request['protocol_version']
 
      # ---- JIRA GSSC-721 New export policy to add TSM snapdiff proxy netgroup -----     
 
      if(($request['environment'].ToLower() -eq $PROD) -and (-not ($request['service_name'].ToLower() -eq $EDISCOVERY)) ){
         if($request['service_level'].ToLower() -eq $NAS_SHARED -or `
            ($request['service_level'].ToLower() -eq $NAS_PREMIUM -and `
             $request['location'].ToLower() -eq 'ind')){
                $return_values += `
                '__res_type=ontap_export_policy_rule;'          + `
                'hostname='       + $qtree['hostname']   + ',' + `
                'vserver='        + $qtree['vserver']      + ',' + `
                'name='           + $qtree['flexvol_name'] + '_' + $qtree_flds[$QTREE_FLD_IDX]       + ',' + `
                'client_match='   + '@' + $SNAPDIFF_NETGROUP + ',' + `
                'ro_rule='        + 'sys'                 + ',' + `
                'rw_rule='        + 'sys'                 + ',' + `
                'super_user_security='  + 'sys'          + ',' + `
                'protocol='             + $NFS
         }             
      }
 
      $return_values += `
         '__res_type=qtree_export_policy;'         + `
         'hostname='       + $qtree['hostname']   + ',' + `
         'vserver='        + $qtree['vserver']      + ',' + `
         'flexvol_name='   + $qtree['flexvol_name']       + ',' + `
         'name='           + $qtree['name']       + ',' + `
         'export_policy='  + $qtree['flexvol_name'] + '_' + $qtree_flds[$QTREE_FLD_IDX]
      $nfs_export_resource += @{
         'hostname'       = $qtree['hostname'];
         'vserver'        = $qtree['vserver'];
         'flexvol_name'   = $qtree['flexvol_name'];
         'export_policy'  = $qtree['flexvol_name'] + '_' + $qtree_flds[$QTREE_FLD_IDX];
         'netgroup_rw'    = $request['netgroup_rw'];
            }
   }
   else{
      $return_values += `
         '__res_type=qtree_export_policy;'         + `
         'hostname='       + $qtree['hostname']   + ',' + `
         'vserver='        + $qtree['vserver']      + ',' + `
         'flexvol_name='   + $qtree['flexvol_name']       + ',' + `
         'name='           + $qtree['name']       + ',' + `
         'export_policy='  + $cluster_service_map[$service_level][$service_name]['qtree_export_policy'][$environment.ToLower()]
 
         $nfs_export_resource += @{
         'hostname'       = $qtree['hostname'];
         'vserver'        = $qtree['vserver'];
         'flexvol_name'   = $qtree['flexvol_name'];
         'export_policy'  = $cluster_service_map[$service_level][$service_name]['qtree_export_policy'][$environment.ToLower()];        
          }         
         }
   }
   $nfs_export = @{
      'success'      = $True;
      'reason'       = "Testing only";
      'return_values'    = $return_values
      'nfs_export'   = $nfs_export_resource
   }
  
   return $nfs_export
}
 
#-----------------------------------------------------------------
# Function cvo_nfs_export()
# We created a new function for defining export policy for CVO
# volume because we are not creating qtrees in CVO
#-----------------------------------------------------------------
 
function cvo_nfs_export(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$volume,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   #-----------------------------------------------------------------
   # FIXME: RTU 14 Oct 2020
   # NETAPP-81
   # We will now support multiple qtrees so this must change
   # accordingly
   #-----------------------------------------------------------------
   # Return 3 items:
   # 1.  A list of export policies to provision
   # 2.  A list of rules to add to policies
   # 3.  A list of volumes/qtrees to update policy name
   #-----------------------------------------------------------------
 
   $return_values = @()
   $nfs_export_resource = @()
 
      $return_values += `
         '__res_type=ontap_export_policy;'               + `
         'hostname='       + $volume['hostname']   + ',' + `
         'vserver='        + $volume['vserver']      + ',' + `
         'name='           + $volume['name']
        
#------- NETAPPMS-169  : SSNAP - Change to NFS Export permissions to satisfy audit ---- 
 
      if ( $request.ContainsKey('netgroup_ro') -and ($request['netgroup_ro'].length -ge 1 ) ){
         $return_values += `
         '__res_type=ontap_export_policy_rule;'          + `
         'hostname='       + $volume['hostname']   + ',' + `
         'vserver='        + $volume['vserver']      + ',' + `
         'name='           + $volume['name'] + ',' + `
         'client_match='   + '@' + $request['netgroup_ro'] + ',' + `
         'ro_rule='        + 'krb5p'                 + ',' + `
         'rw_rule='        + 'none'                 + ',' + `
         'super_user_security='  + 'none'          + ',' + `
         'anonymous_user_id='    + '65534'          + ',' + `
         'allow_suid='           + 'false'          + ',' + `
         'protocol='             + $request['protocol_version']
      }
 
      $return_values += `
            '__res_type=ontap_export_policy_rule;'          + `
            'hostname='       + $volume['hostname']   + ',' + `
            'vserver='        + $volume['vserver']      + ',' + `
            'name='           + $volume['name'] + ',' + `
            'client_match='   + '@' + $request['netgroup_rw'] + ',' + `
            'ro_rule='        + 'krb5p'                 + ',' + `
            'rw_rule='        + 'krb5p'                 + ',' + `
            'super_user_security='  + 'krb5p'          + ',' + `
            'anonymous_user_id='    + '65534'          + ',' + `
            'allow_suid='           + 'false'          + ',' + `
            'protocol='             + $request['protocol_version']
     
      $return_values += `
         '__res_type=volume_export_policy;'         + `
         'hostname='       + $volume['hostname']   + ',' + `
         'vserver='        + $volume['vserver']      + ',' + `
         'flexvol_name='   + $volume['name']       + ',' + `
         'name='           + $volume['name']       + ',' + `
         'export_policy='  + $volume['name']
     
      $nfs_export_resource += @{
         'hostname'       = $volume['hostname'];
         'vserver'        = $volume['vserver'];
         'flexvol_name'   = $volume['name'];
         'export_policy'  = $volume['name'];
         'netgroup_rw'    = $request['netgroup_rw'];
            }
 
   $nfs_export = @{
      'success'      = $True;
      'reason'       = "NFS Export";
      'return_values'    = $return_values
      'nfs_export'   = $nfs_export_resource
   }
  
   return $nfs_export
}
 
function cifs(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [array]$qtrees,
      [parameter(Mandatory=$true)]
      [hashtable]$volume,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
   #--------------------------------------------------------------
   # Build templates for the required AD groups
   # Per doc in Teams the pattern for AD Group names is:
   # DA-SHARE-----
   # UNIQUE ID is the index # from the index in the qtree name
   # Service, region, & env are mapped from the request using the
   # acl_codes_map
   #--------------------------------------------------------------
   $read_ad = 'DA-SHARE-'                                                     + `
      'N' + $acl_codes_map['services'][$request['service_level'].ToLower()]   + `
      $acl_codes_map['regions'][$request['location'].ToLower()]               + '-' + `
      $request['nar_id']                                                      + '-' + `
      '{QTREE_ID}'                                                           + '-' + `
      $acl_codes_map['environments'][$request['environment'].ToLower()]       + '-' + `
      'READ'
   $write_ad = 'DA-SHARE-'                                                    + `
      'N' + $acl_codes_map['services'][$request['service_level'].ToLower()]   + `
      $acl_codes_map['regions'][$request['location'].ToLower()]               + '-' + `
      $request['nar_id']                                                      + '-' + `
      '{QTREE_ID}'                                                           + '-' + `
      $acl_codes_map['environments'][$request['environment'].ToLower()]       + '-' + `
      'WRITE'
 
   #------ JIRA GSSC-232 (Add logic for FRA DEV hosted in LON cluster)
 
   $host_location = $($qtrees[0]['hostname']).Substring(0,3)
 
   $return_values = @()
   $cifs = @()
   foreach ( $qtree in $qtrees ){
      Get-WfaLogger -Info -Message $qtree['name']
      Get-WfaLogger -Info -Message $volume['name']
      $qtree_flds = $qtree['name'].split('_')
 
      #--------------------------------------------------------------
      # Creating the DFS Link
      #--------------------------------------------------------------
      ###----NETAPPMS-258 : SSNAP - Workaround for DFS path failure----####
      $dfslink_present = $false
      $dfslink=""
      if((($request['service_name'].ToLower() -eq $VFS) -or ($request['service_name'].ToLower() -eq $FSU)) -and (!$isRequestGFS)){
      $link=\\dbg.ads.db.com\+$request['dfs_root_path']
      if(($request.ContainsKey('dfs_path_1')) -and $request['dfs_path_1'] -ne ""){
         #------ JIRA GSSC-761 DFS paths having NA - To handle paths with NA
         if($request['dfs_path_1'] -ne "N/A"){
         $link+="\"+$request['dfs_path_1']
         $dfsutil = Invoke-Expression -Command "dfsutil link $link" -ErrorAction SilentlyContinue
         $target = $dfsutil | Select-String -Pattern 'Target="(.+?)"' | Select-Object -First 1 | %{ $_.Matches.Groups[1].Value}
            if($target){
                        $dfslink_present = $true
                        $dfslink = $link
                        Get-WfaLogger -Info -Message "Existing Share:"
                        Get-WfaLogger -Info -Message $($target|out-string)
            } 
      }
      }  
      if((($request.ContainsKey('dfs_path_2')) -and $request['dfs_path_2'] -ne "") -and !$dfslink_present){
         $link+="\"+$request['dfs_path_2']
         $dfsutil = Invoke-Expression -Command "dfsutil link $link" -ErrorAction SilentlyContinue
         $target = $dfsutil | Select-String -Pattern 'Target="(.+?)"' | Select-Object -First 1 | %{ $_.Matches.Groups[1].Value}
            if($target){
                        $dfslink_present = $true
                        $dfslink = $link
                        Get-WfaLogger -Info -Message "Existing Share:"
                        Get-WfaLogger -Info -Message $($target|out-string)
            } 
      }
      if(($request.ContainsKey('dfs_folder')) -and $request['dfs_folder'] -ne ""){
         $link+="\"+$request['dfs_folder']
      }
      if((($request.ContainsKey('dfs_new_folder')) -and $request['dfs_new_folder'] -ne "") -and !$dfslink_present){
         $link+="\"+$request['dfs_new_folder']
         $dfsutil = Invoke-Expression -Command "dfsutil link $link" -ErrorAction SilentlyContinue
         $target = $dfsutil | Select-String -Pattern 'Target="(.+?)"' | Select-Object -First 1 | %{ $_.Matches.Groups[1].Value}
            if($target){
                        $dfslink_present = $true
                        $dfslink = $link
                        Get-WfaLogger -Info -Message "Existing Share:"
                        Get-WfaLogger -Info -Message $($target|out-string)
            } 
      }
      #---- prepare dfs_path to be inserted into CB table ------#
      $dfs_path = $link
      $split=$dfs_path -split "\\"
      $path="\\"
      foreach ($part in $split)
      { if($part -ne ''){ $path += "\\"+$part }}
      $dfs_path = $path
 
      $request['dfs_path']=$dfs_path
 
      #---- JIRA GSSC-490 (Configure DFS path with prod and dr links fro non-geo regions) -------
 
      $return_values += `
         '__res_type=dfs;'                     + `
         'create='       + "link"       + ',' + `
         'link='       + '"' + $link + '"'       + ',' + `
         'cifs_share=' + '"' + '\\' +$qtree['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+'\'+ $qtree['name'] + '$' + '"'
      }
 
      if($acl_codes_map['non-geo-locations'].contains($request['location'])){
 
         $dr_svm = $qtree['vserver'] + '-dr'
        
         $return_values += `
         '__res_type=dfs;'                     + `
         'create='       + "target"       + ',' + `
         'link='       + '"' + $link + '"'       + ',' + `
         'cifs_share=' + '"' + '\\' + $dr_svm + $acl_codes_map['domains'][$host_location.ToLower()]+'\'+ $qtree['name'] + '$' + '"'
 
      }
     
      #--------------------------------------------------------------
      # Provision the new share
      #--------------------------------------------------------------
      $cifs += @{
         'hostname'     = $qtree['hostname'];
         'vserver'      = $qtree['vserver'];
         'share_name'   = $qtree['name'] + '$';
         'path'         = '/' + $volume['name'] + '/' + $qtree['name'];
         'link'         = $link;
         'read_acl'     = $read_ad -replace '{QTREE_ID}', $qtree_flds[$QTREE_FLD_IDX];
         'write_acl'    = $write_ad -replace '{QTREE_ID}', $qtree_flds[$QTREE_FLD_IDX]
      }
      $return_values += `
         '__res_type=ontap_cifs;'                     + `
         'hostname='       + $qtree['hostname']       + ',' + `
         'vserver='        + $qtree['vserver']        + ',' + `
         'share_name='     + $qtree['name'] + '$'     + ',' + `
         'path='           + '/' + $volume['name'] + '/' + $qtree['name']
        
            
      #--------------------------------------------------------------
      # Add new AD groups to be used by ACLs
      #--------------------------------------------------------------
      $approvers=""
      if(($request.ContainsKey('smb_acl_group_approver_1')) -and (-not $request['smb_acl_group_approver_1'] -eq "")){
         $approvers = ',dbagIMSApprovers1='+ $request['smb_acl_group_approver_1']
      }
      if(($request.ContainsKey('smb_acl_group_approver_2')) -and  (-not $request['smb_acl_group_approver_2'] -eq "")){
         $approvers += ',dbagIMSApprovers2='+ $request['smb_acl_group_approver_2']
      }
      if(($request.ContainsKey('smb_acl_group_contact')) -and  (-not $request['smb_acl_group_contact'] -eq "")){
         $approvers += ',dbagIMSApprovers3='+ $request['smb_acl_group_contact']
      }
 
      #---- JIRA GSSC-460 (Add regional OU names corrosponding to location in request) -------
 
      $sims_region = $request['location']
 
      if($sims_region -eq "sin")
      {
         $sims_region = "sng"
      }
 
      if($sims_region -eq "tko")
      {
         $sims_region = "jpn"
      }
 
      if($sims_region -eq "syd")
      {
         $sims_region = "aus"
      }
 
      #---- JIRA GSSC-364 (Add DFS link to SIMS AD Groups) -------
 
      $cifs_share = \\$($qtree['vserver'])$($acl_codes_map['domains'][$host_location.ToLower()])\$($qtree['name'])$
 
      if($link.length -ne 0)
      {
        $description = $link
      }
      else
      {
        $description = $cifs_share
      }
      #      15 June 2023
      #------NETAPPMS-4: Modify ACL attributes (dbagModifiedBy and dbagApplicationId) at NAS Automation ----#
      $return_values += `
         '__res_type=sims_ad_group;'                        + `
         'owner='                              + $request['smb_acl_group_approver_1']      + ',' + `
         'region='                             + $sims_region                              + ',' + `
         'description='                        + $description                              + ',' + `
         'dbagFileSystemFullPaths='            + $description                              + ',' + `
         'requestId='                          + $request['snow_request_id']               + ',' + `
         'dbagIMSAuthContact='                 + $request['smb_acl_group_contact']         + ',' + `
         'dbagIMSAuthContactDelegate='         + $request['smb_acl_group_delegate']        + ',' + `
         'dbagCostcenter='                     + $request['cost_centre']                   + ',' + `
         'dbagApplicationId='                  + $DBAG_NAR_ID                              + ',' + `
         'dbagModifiedBy='                     + $DBAG_NAR_ID                              + ',' + `
         'sAMAccountName='       + ($read_ad -replace '{QTREE_ID}', $qtree_flds[$QTREE_FLD_IDX]) + $approvers
      $return_values += `
         '__res_type=sims_ad_group;'                       + `
         'owner='                              + $request['smb_acl_group_approver_1']      + ',' + `
         'region='                             + $sims_region                              + ',' + `
         'description='                        + $description                              + ',' + `
         'dbagFileSystemFullPaths='            + $description                              + ',' + `
         'requestId='                          + $request['snow_request_id']               + ',' + `
         'dbagIMSAuthContact='                 + $request['smb_acl_group_contact']         + ',' + `
         'dbagIMSAuthContactDelegate='         + $request['smb_acl_group_delegate']        + ',' + `
         'dbagCostcenter='                     + $request['cost_centre']                   + ',' + `
         'dbagApplicationId='                  + $DBAG_NAR_ID                              + ',' + `
         'dbagModifiedBy='                     + $DBAG_NAR_ID                              + ',' + `
         'sAMAccountName='       + ($write_ad -replace '{QTREE_ID}', $qtree_flds[$QTREE_FLD_IDX]) + $approvers
      #-------------------------------------------------------------------
      # Provision the new share ACLs NT Authority\Authenticated Users
      #-------------------------------------------------------------------
      $return_values += `
         '__res_type=ontap_cifs_acl;'                 + `
         'hostname='       + $qtree['hostname']       + ',' + `
         'vserver='        + $qtree['vserver']        + ',' + `
         'share_name='     + $qtree['name'] + '$'     + ',' + `
         'user_or_group='  + 'Authenticated Users' + ',' + `
         'permission='     + 'full_control'
      #--------------------------------------------------------------
      # Remove the default 'everyone' ACL
      #--------------------------------------------------------------
      $return_values += `
         '__res_type=ontap_cifs_acl;'                 + `
         'hostname='       + $qtree['hostname']       + ',' + `
         'vserver='        + $qtree['vserver']        + ',' + `
         'share_name='     + $qtree['name'] + '$'     + ',' + `
         'user_or_group='  + 'Everyone' + ',' + `
         'permission='     + 'full_control'  + ',' + `
         'state='          + 'absent'
 
      #--------------------------------------------------------------
      # Provision the NTFS permissions for READ and WRITE ACL
      #--------------------------------------------------------------
      $return_values += `
         '__res_type=win_acl;'                 + `
         'path='           + '\\' + $qtree['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+'\'+ $volume['name'] + '$' + '\' + $qtree['name']    + ',' + `
         'user='           + 'DBG\' + ($read_ad -replace '{QTREE_ID}', $qtree_flds[$QTREE_FLD_IDX]) + ',' + `
         'rights='         + 'ReadAndExecute'                   + ',' + `
         'state='          + 'present'
 
      $return_values += `
         '__res_type=win_acl;'                 + `
         'path='           + '\\' + $qtree['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+'\'+ $volume['name'] + '$' + '\' + $qtree['name']    + ',' + `
         'user='           + 'DBG\' + ($write_ad -replace '{QTREE_ID}', $qtree_flds[$QTREE_FLD_IDX]) + ',' + `
         'rights='         + 'Modify'                     + ',' + `
         'state='          + 'present'
     
   }
 
   if($dfslink_present){
      return @{
         'success'         = $False;
         'reason'          = $dfslink + " is already a Share. Modify DFS Path accordingly and re-submit the request.";
         'return_values'   = $return_values
         'ontap_cifs'      = $cifs
      }
   }
   else{
      return @{
         'success'         = $True;
         'reason'          = "Provision CIFS share";
         'return_values'   = $return_values
         'ontap_cifs'      = $cifs
      }
   }
  
}
 
function cvo_cifs(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$volume,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
   #--------------------------------------------------------------
   # Build templates for the required AD groups
   # Per doc in Teams the pattern for AD Group names is:
   # DA-SHARE-----
   # UNIQUE ID is the index # from the index in the volume name
   # Service, region, & env are mapped from the request using the
   # acl_codes_map
   #--------------------------------------------------------------
   $read_ad = 'DA-SHARE-'                                                     + `
      'N' + $acl_codes_map['services'][$request['service_level'].ToLower()]   + `
      $acl_codes_map['regions'][$request['location'].ToLower()]               + '-' + `
      $request['nar_id']                                                      + '-' + `
      '{CVO_VOLUME_ID}'                                                           + '-' + `
      $acl_codes_map['environments'][$request['environment'].ToLower()]       + '-' + `
      'READ'
   $write_ad = 'DA-SHARE-'                                                    + `
      'N' + $acl_codes_map['services'][$request['service_level'].ToLower()]   + `
      $acl_codes_map['regions'][$request['location'].ToLower()]               + '-' + `
      $request['nar_id']                                                      + '-' + `
      '{CVO_VOLUME_ID}'                                                           + '-' + `
      $acl_codes_map['environments'][$request['environment'].ToLower()]       + '-' + `
      'WRITE'
 
   #------ JIRA GSSC-232 (Add logic for FRA DEV hosted in LON cluster)
 
   $host_location = $($volume['hostname']).Substring(0,3)
 
   $return_values = @()
   $cifs = @()
 
      Get-WfaLogger -Info -Message $volume['name']
      $volume_flds = $volume['name'].split('_')
 
      #--------------------------------------------------------------
      # Creating the DFS Link - Dont need DFS for CVO but kept
      # the code piece in just in case we need to add in future we use "-ne "
      #--------------------------------------------------------------
 
      if( ($request['service_level'].ToLower() -ne $CVO) ){
      $link=\\dbg.ads.db.com\+$request['dfs_root_path']
      if(($request.ContainsKey('dfs_path_1')) -and $request['dfs_path_1'] -ne ""){
         $link+="\"+$request['dfs_path_1']
      }
      if(($request.ContainsKey('dfs_path_2')) -and $request['dfs_path_2'] -ne ""){
         $link+="\"+$request['dfs_path_2']
      }
      if(($request.ContainsKey('dfs_folder')) -and $request['dfs_folder'] -ne ""){
         $link+="\"+$request['dfs_folder']
      }
      if(($request.ContainsKey('dfs_new_folder')) -and $request['dfs_new_folder'] -ne ""){
         $link+="\"+$request['dfs_new_folder']
      }
 
      #---- JIRA GSSC-490 (Configure DFS path with prod and dr links fro non-geo regions) -------
 
      # $return_values += `
      #    '__res_type=dfs;'                     + `
      #    'create='       + "link"       + ',' + `
      #    'link='       + '"' + $link + '"'       + ',' + `
      #    'cifs_share=' + '"' + '\\' +$volume['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+'\'+ $volume['name'] + '$' + '"'
      }
 
      Get-WfaLogger -Info -Message $($write_ad -replace '{CVO_VOLUME_ID}', $volume_flds[$VOLUME_FLD_IDX])
      Get-WfaLogger -Info -Message $($read_ad -replace '{CVO_VOLUME_ID}', $volume_flds[$VOLUME_FLD_IDX])
      #Get-WfaLogger -Info -Message $link
     
      #--------------------------------------------------------------
      # Provision the new share
      #--------------------------------------------------------------
      $cifs += @{
         'hostname'     = $volume['hostname'];
         'vserver'      = $volume['vserver'];
         'share_name'   = $volume['name'] + '$';
         'path'         = '/' + $volume['name'];
         'share'        = \\$($volume['vserver'])$($acl_codes_map['cvo_domains'][$request['landing_zone']][$request['environment']][$host_location.ToLower()])\$($volume['name'])$;
         'read_acl'     = $read_ad -replace '{CVO_VOLUME_ID}', $volume_flds[$VOLUME_FLD_IDX];
         'write_acl'    = $write_ad -replace '{CVO_VOLUME_ID}', $volume_flds[$VOLUME_FLD_IDX]
      }
      $return_values += `
         '__res_type=ontap_cifs;'                     + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'share_name='     + $volume['name'] + '$'     + ',' + `
         'path='           + '/' + $volume['name']
        
      Get-WfaLogger -Info -Message $($return_values|out-string)     
      #--------------------------------------------------------------
      # Add new AD groups to be used by ACLs
      #--------------------------------------------------------------
      $approvers=""
      if(($request.ContainsKey('smb_acl_group_approver_1')) -and (-not $request['smb_acl_group_approver_1'] -eq "")){
         $approvers = ',dbagIMSApprovers1='+ $request['smb_acl_group_approver_1']
      }
      if(($request.ContainsKey('smb_acl_group_approver_2')) -and  (-not $request['smb_acl_group_approver_2'] -eq "")){
         $approvers += ',dbagIMSApprovers2='+ $request['smb_acl_group_approver_2']
      }
      if(($request.ContainsKey('smb_acl_group_contact')) -and  (-not $request['smb_acl_group_contact'] -eq "")){
         $approvers += ',dbagIMSApprovers3='+ $request['smb_acl_group_contact']
      }
 
      #---- JIRA GSSC-460 (Add regional OU names corrosponding to location in request) -------
 
      $sims_region = $request['location']
 
      #---- JIRA GSSC-364 (Add DFS link to SIMS AD Groups) -------
 
      $cifs_share = \\$($volume['vserver'])$($acl_codes_map['cvo_domains'][$request['landing_zone']][$request['environment']][$host_location.ToLower()])\$($volume['name'])$
 
      if($link.length -ne 0)
      {
        $description = $link
      }
      else
      {
        $description = $cifs_share
      }
      #      15 June 2023
      #------NETAPPMS-4: Modify ACL attributes (dbagModifiedBy and dbagApplicationId) at NAS Automation ----#
      $return_values += `
         '__res_type=sims_ad_group;'                        + `
         'owner='                              + $request['smb_acl_group_approver_1']      + ',' + `
         'region='                             + $sims_region                              + ',' + `
         'description='                        + $description                              + ',' + `
         'dbagFileSystemFullPaths='            + $description                              + ',' + `
         'requestId='                          + $request['snow_request_id']               + ',' + `
         'dbagIMSAuthContact='                 + $request['smb_acl_group_contact']         + ',' + `
         'dbagIMSAuthContactDelegate='         + $request['smb_acl_group_delegate']        + ',' + `
         'dbagCostcenter='                     + $request['cost_centre']                   + ',' + `
         'dbagApplicationId='                  + $DBAG_NAR_ID                              + ',' + `
         'dbagModifiedBy='                     + $DBAG_NAR_ID                              + ',' + `
         'sAMAccountName='       + ($read_ad -replace '{CVO_VOLUME_ID}', $volume_flds[$VOLUME_FLD_IDX]) + $approvers
      $return_values += `
         '__res_type=sims_ad_group;'                       + `
         'owner='                              + $request['smb_acl_group_approver_1']      + ',' + `
         'region='                             + $sims_region                              + ',' + `
         'description='                        + $description                              + ',' + `
         'dbagFileSystemFullPaths='            + $description                              + ',' + `
         'requestId='                          + $request['snow_request_id']               + ',' + `
         'dbagIMSAuthContact='                 + $request['smb_acl_group_contact']         + ',' + `
         'dbagIMSAuthContactDelegate='         + $request['smb_acl_group_delegate']        + ',' + `
         'dbagCostcenter='                     + $request['cost_centre']                   + ',' + `
         'dbagApplicationId='                  + $DBAG_NAR_ID                              + ',' + `
         'dbagModifiedBy='                     + $DBAG_NAR_ID                              + ',' + `
         'sAMAccountName='       + ($write_ad -replace '{CVO_VOLUME_ID}', $volume_flds[$VOLUME_FLD_IDX]) + $approvers
      #-------------------------------------------------------------------
      # Provision the new share ACLs NT Authority\Authenticated Users
      #-------------------------------------------------------------------
      $return_values += `
         '__res_type=ontap_cifs_acl;'                 + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'share_name='     + $volume['name'] + '$'     + ',' + `
         'user_or_group='  + 'Authenticated Users' + ',' + `
         'permission='     + 'change'
      #--------------------------------------------------------------
      # Remove the default 'everyone' ACL
      #--------------------------------------------------------------
      $return_values += `
         '__res_type=ontap_cifs_acl;'                 + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'share_name='     + $volume['name'] + '$'     + ',' + `
         'user_or_group='  + 'Everyone' + ',' + `
         'permission='     + 'full_control'  + ',' + `
         'state='          + 'absent'
 
      #--------------------------------------------------------------
      # Provision the NTFS permissions for READ and WRITE ACL
      #--------------------------------------------------------------
      $return_values += `
         '__res_type=win_acl;'                 + `
         'path='           + '\\' + $volume['vserver']+$acl_codes_map['cvo_domains'][$request['landing_zone']][$request['environment']][$host_location.ToLower()]+'\'+ $volume['name'] + '$'  + ',' + `
         'user='           + 'DBG\' + ($read_ad -replace '{CVO_VOLUME_ID}', $volume_flds[$VOLUME_FLD_IDX]) + ',' + `
         'rights='         + 'ReadAndExecute'                   + ',' + `
         'state='          + 'present'
 
      $return_values += `
         '__res_type=win_acl;'                 + `
         'path='           + '\\' + $volume['vserver']+$acl_codes_map['cvo_domains'][$request['landing_zone']][$request['environment']][$host_location.ToLower()]+'\'+ $volume['name'] + '$'   + ',' + `
         'user='           + 'DBG\' + ($write_ad -replace '{CVO_VOLUME_ID}', $volume_flds[$VOLUME_FLD_IDX]) + ',' + `
         'rights='         + 'Modify'                     + ',' + `
         'state='          + 'present'
     
 
   return @{
      'success'         = $True;
      'reason'          = "Provision CIFS share";
      'return_values'   = $return_values
      'ontap_cifs'      = $cifs
   }
  
}
#---------------------------------------------------------------
# Function: servicenow()
# This functions creates the input for Servicenow. SO that ansible can make a call to servicenow.
# In this function we read the values from  $placement_solution and create statments for worknotes and comments.
# We are creating the backup required and comments depending upon different service level and service name.
# we need to add default 'logging' inputs to return_values So that logging can happen on the ansible side.
#---------------------------------------------------------------
function servicenow(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true, HelpMessage="placement solution")]
      [hashtable]$placement_solution
   )
   $return_values = @()
   $backup_required = $False
 
   Get-WfaLogger -Info -Message $( "ServieNow Request Inputs " + $request)
 
   $volume  = $placement_solution['resources']['ontap_volume']
   $qtree   = $placement_solution['resources']['ontap_qtree']
 
   #------ JIRA GSSC-232 (Add logic for FRA DEV hosted in LON cluster)
 
   $host_location = $($qtree[0]['hostname']).Substring(0,3)
 
   Get-WfaLogger -Info -Message (($request['environment'].ToLower() -eq $PROD) -and (-not ($request['service_name'].ToLower() -eq $EDISCOVERY)) )
   Get-WfaLogger -Info -Message ($placement_solution['return_values'].Contains('__res_type=ontap_volume;'))
  
   # ---- JIRA NETAPPMS-123 FIX for Duplicate Backup tasks for HKG/NAS SHARED-----
   #------- NETAPPMS-140  : Include FRA MC3 and SV and Re-group MC3 logic ----                             
   foreach($data in $placement_solution['return_values']){
      if( ($data.Contains('__res_type=ontap_volume;')) -and `
            (  (($request['service_level'] -eq $NAS_PREMIUM) -and `
               (!$SNAPVAULT_SITE.Contains($request['location'].ToLower())))  -or  `
               ($request['service_level'] -eq $NAS_SHARED)
            )
         ){
         $backup_required = $true
      }
   }
   Get-WfaLogger -Info -Message $("printing backup requirement: " + $backup_required)
   # ---- JIRA GSSC-681, GSSC-665 Remove MC2 clusters from TSM snapdiff 4 RITM process -----
   # ---- NETAPPMS-139   : Add Snapdiff backup task for IND Fabric ---- #
   if(($request['environment'].ToLower() -eq $PROD) -and (-not ($request['service_name'].ToLower() -eq $EDISCOVERY)) ){     
      if ($backup_required){  
         if($request['service_level'].ToLower() -eq $NAS_PREMIUM -and `
            ($request['location'].ToLower() -ne 'nyc' -and `
            $request['location'].ToLower() -ne 'ind')){
            $backup_type = "NDMP"
         }    
         elseif($request['service_level'].ToLower() -eq $NAS_SHARED -or `
               ($request['service_level'].ToLower() -eq $NAS_PREMIUM -and `
               $request['location'].ToLower() -eq 'ind') ){
               $backup_type = "SnapDiff"
               # JIRA - NETAPPMS-320 Volume backup check and prevent notification until backup for new volume is configured
               $do_not_notify_user = $true
               $do_not_notify_user_comments = "The storage has been provisioned and backup configuration requested. Please wait for RITM to be closed fully to ensure your storage is successfully configured for backup and data protection. Mount details are present in the RITM worknotes. Please note: Although your storage has been allocated your data is unprotected until the request for backup is complete and there would be a risk of data loss."
         }
         else{
            $backup_type = ""
         }
         $backup_required = "BACKUP REQUIRED: TASK1 - Please Create a $backup_type backup for Following Storage - "
         Get-WfaLogger -Info -Message $("Backup Required Loggig is required")
         Get-WfaLogger -Info -Message $( "Adding backup details for " + $volume['name'])
         $backup_required += @(
            'volume: '       + $volume['name']    + ' and ' + `
            'vserver: '      + $volume['vserver']     
         );
 
         # ---- JIRA GSSC-681, GSSC-665 Remove MC2 clusters from TSM snapdiff 4 RITM process -----
         #------- NETAPPMS-139  : Include IND Fabric for Snapdiff ----
         if ($request['service_level'].ToLower() -eq $NAS_SHARED -or `
            ($request['service_level'].ToLower() -eq $NAS_PREMIUM -and `
            $request['location'].ToLower() -eq 'ind')){
               $backup_required += ". Also provide PROXY details in activity logs for Platform team TASK 2"
 
               if($request['protocol'].ToLower() -like "nfs"){
 
                        $backup_required += ". Once registered please raise a CR for the HP_GLOBAL_CTB_UNIX_BESTSHORE to configure proxy. "
                       
                        # ---- JIRA GSSC-703, GSSC-706 Add NIS Domain and Mount Path details to Backup TASK1 -----
                        $backup_required += @(
                           'NIS_Domain: '   + $request['nis_domain']    + ' and ' +`
                           'Mount_Path: '   + $qtree[0]['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+":/"+$qtree[0]['flexvol_name']  
                        );
 
               }
               # ---- JIRA GSSC-778 Update Backup task1 with Retention period  -----
               if($request['service_name'].ToLower() -eq $FSU){
                  $backup_required += $RETENTION_FSU }
               elseif($request['service_name'].ToLower() -eq $VFS){
                  $backup_required += $RETENTION_VFS }         
               elseif($request['service_name'].ToLower() -eq $GFS){
                  $backup_required += $RETENTION_GFS }
               elseif($request['service_name'].ToLower() -eq $FABRIC){
                  $backup_required += $RETENTION_FABRIC }  
            }
        
      $return_values +=                                              `
         '__res_type=servicenow;'                                    +       `
         'work_notes='        + $backup_required  + ','              + `
         'correlation_id='    + $request['correlation_id']   + ','   + `
         'action='            + 'comment'      + ','                 + `
         'sys_id='            + $request['sys_id']
      }
   }
 
   $comment = $SERVICENOW_COMMENT
 
   if($request['service_name'].ToLower() -eq $GFS){
      if($request['protocol'].ToLower() -eq $NFS){     
         $comment+= $qtree[0]['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+":/"+$qtree[0]['flexvol_name']+"/"+$qtree[0]['name']
         $comment+= ". Netgroup is $($request['netgroup_rw'] | Out-String)"
         $comment+= ". Add host to this netgroup for share access"
      }
      elseif($request['protocol'].ToLower() -eq $SMB){
         $cifs  = $placement_solution['resources']['ontap_cifs']
         $comment+= '\\'+$cifs[0]['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+'\'+$cifs[0]['share_name']
         $comment+= ". Read-Only ACL is $($cifs[0]['read_acl'] | Out-String). Read-Write ACL is $($cifs[0]['write_acl'] | Out-String)"
         $comment+= ". Add yourself to these ACLs for share access"
      }
   }
 
   elseif ($request['service_name'].ToLower() -eq $FABRIC){
         $comment+= $qtree[0]['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+":/"+$qtree[0]['flexvol_name']+"/"+$qtree[0]['name']+"  -  " `
         +$qtree[-1]['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+":/"+$qtree[-1]['flexvol_name']+"/"+$qtree[-1]['name']     
   }
 
   elseif ($request['service_name'].ToLower() -eq $FSU){
      $cifs  = $placement_solution['resources']['ontap_cifs']
      $comment+= $cifs[0]['link']
      $comment+= ". Read-Only ACL is $($cifs[0]['read_acl'] | Out-String). Read-Write ACL is $($cifs[0]['write_acl'] | Out-String)"
      $comment+= ". Add yourself to these ACLs for share access"
   }
 
   elseif ($request['service_name'].ToLower() -eq $VFS ){
      if($request['protocol'].ToLower() -eq $NFS){      
         $comment+= $qtree[0]['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+":/"+$qtree[0]['flexvol_name']+"/"+$qtree[0]['name']
         $comment+= ". Netgroup is $($request['netgroup_rw'] | Out-String)"
         $comment+= ". Add host to this netgroup for share access"
      }
      #------NETAPPMS-6: MC2 to MC3 migration for GFS DEV re-location to NAS Shared ----#
      elseif(($request['protocol'].ToLower() -eq $SMB) -and $isRequestGFS){   
         $cifs  = $placement_solution['resources']['ontap_cifs']
         $comment+= '\\'+$cifs[0]['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+'\'+$cifs[0]['share_name']
         $comment+= ". Read-Only ACL is $($cifs[0]['read_acl'] | Out-String). Read-Write ACL is $($cifs[0]['write_acl'] | Out-String)"
         $comment+= ". Add yourself to these ACLs for share access"
      }
      elseif($request['protocol'].ToLower() -eq $SMB){
         $cifs  = $placement_solution['resources']['ontap_cifs']
         $comment+= $cifs[0]['link']
         $comment+= ". Read-Only ACL is $($cifs[0]['read_acl'] | Out-String). Read-Write ACL is $($cifs[0]['write_acl'] | Out-String)"
         $comment+= ". Add yourself to these ACLs for share access"
      }    
   }
 
   elseif ($request['service_name'].ToLower() -eq $Ediscovery){
      $cifs  = $placement_solution['resources']['ontap_cifs']
         $comment+= "\\"+$cifs[0]['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+"\"+$cifs[0]['share_name']
         $comment+= ". Read-Only ACL is $($cifs[0]['read_acl'] | Out-String). Read-Write ACL is $($cifs[0]['write_acl'] | Out-String)"
         $comment+= ". Add yourself to these ACLs for share access"
   }
 
   # JIRA - NETAPPMS-320 Volume backup check and prevent notification until backup for new volume is configured
   if ($do_not_notify_user){
      $comment+= ". ** Please note ** : Kindly wait for RITM to be closed fully to ensure your storage is successfully configured for backup and data protection. Although your storage has been allocated your data is unprotected until the request for backup is complete and there would be a risk of data loss."
   }
 
   # JIRA - NETAPPMS-320 Volume backup check and prevent notification until backup for new volume is configured
   if ($do_not_notify_user){
 
      $return_values +=                                              `
         '__res_type=servicenow;'                                    +       `
         'work_notes='        + $comment  + ','              + `
         'correlation_id='    + $request['correlation_id']   + ','   + `
         'action='            + 'comment'      + ','                 + `
         'sys_id='            + $request['sys_id']
 
      $return_values +=                                              `
         '__res_type=servicenow;'                                    +       `
         'comment='           + $do_not_notify_user_comments  + ','              + `
         'correlation_id='    + $request['correlation_id']   + ','   + `
         'action='            + 'completed'      + ','                 + `
         'sys_id='            + $request['sys_id']
   }
   else {
      $return_values +=                                              `
            '__res_type=servicenow;'                                    +       `
            'comment='           + $comment  + ','              + `
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
   $backup_required = $False
 
   Get-WfaLogger -Info -Message "Inside cvo_servicenow"
   Get-WfaLogger -Info -Message $( "ServieNow Request Inputs " + $request)
 
   $volume  = $placement_solution['resources']['ontap_volume']
 
   Get-WfaLogger -Info -Message $($volume | out-string)
 
   #------ JIRA GSSC-232 (Add logic for FRA DEV hosted in LON cluster)
 
   $host_location = $($volume['hostname']).Substring(0,3)
  
   foreach($data in $placement_solution['return_values']){
      if(($request['environment'].ToLower() -eq $PROD) -and $data.Contains('__res_type=cvo_ontap_volume;')){
         $backup_required = $true
      }
   }   
      if ($backup_required){        
         $backup_required = "CBS BACKUP REQUIRED"
         Get-WfaLogger -Info -Message $("CBS Backup required")
         Get-WfaLogger -Info -Message $( "Adding backup details for " + $volume['name'])
         $backup_required += @(
            'volume: '       + $volume['name']    + ' and ' + `
            'vserver: '      + $volume['vserver']     
         ); 
         
      $return_values +=                                              `
         '__res_type=servicenow;'                                    +       `
         'work_notes='        + $backup_required  + ','              + `
         'correlation_id='    + $request['correlation_id']   + ','   + `
         'action='            + 'comment'      + ','                 + `
         'sys_id='            + $request['sys_id']
      }
 
   $comment = $SERVICENOW_COMMENT
 
      if($request['protocol'].ToLower() -eq $NFS){      
         $comment+= $volume['vserver']+$acl_codes_map['cvo_domains'][$request['landing_zone']][$request['environment']][$host_location.ToLower()]+":/"+$volume['name']
         $comment+= ". Netgroup is $($request['netgroup_rw'] | Out-String)"
         $comment+= ". Add host to this netgroup for share access"
      }
      elseif($request['protocol'].ToLower() -eq $SMB){
         $cifs  = $placement_solution['resources']['ontap_cifs']
         $comment+= $cifs[0]['share']
         $comment+= ". Read-Only ACL is $($cifs[0]['read_acl'] | Out-String). Read-Write ACL is $($cifs[0]['write_acl'] | Out-String)"
         $comment+= ". Add yourself to these ACLs for share access"
      }    
 
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
 
#---------------------------------------------------------------
# Function: cifs_volume_root()
# This functions creates CIFS share for smb volumes for administrative purposes.
# We apply ntfs and share permission to volume share which gets inherited to qtree
#---------------------------------------------------------------
 
function cifs_volume_root(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$volume
   )
   $return_values = @()
   $return_values += `
         '__res_type=ontap_cifs;'                     + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'share_name='     + $volume['name'] + '$'     + ',' + `
         'path='           + '/' + $volume['name']
 
   #--------------------------------------------------------------
   # Provision the BUILTIN ACLs
   #--------------------------------------------------------------
   $return_values += `
         '__res_type=ontap_cifs_acl;'                 + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'share_name='     + $volume['name'] + '$'     + ',' + `
         'user_or_group='  + 'Administrators'  + ',' + `
         'permission='     + 'full_control'
   $return_values += `
         '__res_type=ontap_cifs_acl;'                 + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'share_name='     + $volume['name'] + '$'     + ',' + `
         'user_or_group='  + 'Backup Operators'  + ',' + `
         'permission='     + 'full_control'
   #--------------------------------------------------------------
   # Remove the default 'everyone' ACL
   #--------------------------------------------------------------
   $return_values += `
         '__res_type=ontap_cifs_acl;'                 + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'share_name='     + $volume['name'] + '$'     + ',' + `
         'user_or_group='  + 'Everyone'                + ',' + `
         'permission='     + 'full_control'            + ',' + `
         'state='          + 'absent'
   #--------------------------------------------------------------
   # Provision the NTFS permissions for builtin ACL
   #--------------------------------------------------------------
 
   #------ JIRA GSSC-232 (Add logic for FRA DEV hosted in LON cluster)
 
   $host_location = $($volume['hostname']).Substring(0,3)
 
   $return_values += `
         '__res_type=win_acl;'                 + `
         'path='           + '\\' + $volume['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+'\'+ $volume['name'] + '$'       + ',' + `
         'user='           + 'builtin\administrators'        + ',' + `
         'rights='         + 'FullControl'                   + ',' + `
         'state='          + 'present'
  
   $return_values += `
         '__res_type=win_acl;'                 + `
         'path='           + '\\' + $volume['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+'\'+ $volume['name'] + '$'       + ',' + `
         'user='           + 'builtin\backup operators'        + ',' + `
         'rights='         + 'FullControl'                     + ',' + `
         'state='          + 'present'
  
   #--------------------------------------------------------------
   # Remove "everyone" NTFS permissions using ICACLS
   #--------------------------------------------------------------
   $return_values += `
         '__res_type=win_icacls;'                 + `
         'path='           + '\\' + $volume['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]+'\'+ $volume['name'] + '$'       + ',' + `
         'user='           + 'Everyone'
 
   $cifs_volume_root = @{
            'success'         = $True;
            'reason'          = "CIFS share creation failed for volume";
            'return_values'   = $return_values
   } 
   
   Get-WfaLogger -Info -Message "CIFS share created for volume root"
   
   return $cifs_volume_root
 
}
 
#---------------------------------------------------------------
# Function: cifs_volume_root()
# This functions creates CIFS share for smb volumes for administrative purposes.
# We apply ntfs and share permission to volume share which gets inherited to qtree
#---------------------------------------------------------------
 
function cvo_cifs_volume_root(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$volume
   )
   $return_values = @()
   $return_values += `
         '__res_type=ontap_cifs;'                     + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'share_name='     + $volume['name'] + '$'     + ',' + `
         'path='           + '/' + $volume['name']
 
   #--------------------------------------------------------------
   # Provision the BUILTIN ACLs
   #--------------------------------------------------------------
   $return_values += `
         '__res_type=ontap_cifs_acl;'                 + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'share_name='     + $volume['name'] + '$'     + ',' + `
         'user_or_group='  + 'Administrators'  + ',' + `
         'permission='     + 'full_control'
   $return_values += `
         '__res_type=ontap_cifs_acl;'                 + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'share_name='     + $volume['name'] + '$'     + ',' + `
         'user_or_group='  + 'Backup Operators'  + ',' + `
         'permission='     + 'full_control'
   #--------------------------------------------------------------
   # Remove the default 'everyone' ACL
   #--------------------------------------------------------------
   $return_values += `
         '__res_type=ontap_cifs_acl;'                 + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'share_name='     + $volume['name'] + '$'     + ',' + `
         'user_or_group='  + 'Everyone'                + ',' + `
         'permission='     + 'full_control'            + ',' + `
         'state='          + 'absent'
   #--------------------------------------------------------------
   # Provision the NTFS permissions for builtin ACL
   #--------------------------------------------------------------
 
   #------ JIRA GSSC-232 (Add logic for FRA DEV hosted in LON cluster)
 
   $host_location = $($volume['hostname']).Substring(0,3)
 
   $return_values += `
         '__res_type=win_acl;'                 + `
         'path='           + '\\' + $volume['vserver']+$acl_codes_map['cvo_domains'][$request['landing_zone']][$request['environment']][$host_location.ToLower()]+'\'+ $volume['name'] + '$'       + ',' + `
         'user='           + 'builtin\administrators'        + ',' + `
         'rights='         + 'FullControl'                   + ',' + `
         'state='          + 'present'
  
   $return_values += `
         '__res_type=win_acl;'                 + `
         'path='           + '\\' + $volume['vserver']+$acl_codes_map['cvo_domains'][$request['landing_zone']][$request['environment']][$host_location.ToLower()]+'\'+ $volume['name'] + '$'       + ',' + `
         'user='           + 'builtin\backup operators'        + ',' + `
         'rights='         + 'FullControl'                     + ',' + `
         'state='          + 'present'
  
   #--------------------------------------------------------------
   # Remove "everyone" NTFS permissions using ICACLS
   #--------------------------------------------------------------
   $return_values += `
         '__res_type=win_icacls;'                 + `
         'path='           + '\\' + $volume['vserver']+$acl_codes_map['cvo_domains'][$request['landing_zone']][$request['environment']][$host_location.ToLower()]+'\'+ $volume['name'] + '$'       + ',' + `
         'user='           + 'Everyone'
 
   $cvo_cifs_volume_root = @{
            'success'         = $True;
            'reason'          = "CIFS share creation failed for volume";
            'return_values'   = $return_values
   } 
   
   Get-WfaLogger -Info -Message "CIFS share created for volume root"
   
   return $cvo_cifs_volume_root
 
}
 
#------- JIRA GSSC-368 : RITM for SnapDiff proxy server configuration -------#
#------- JIRA GSSC-599 : Additional RITMs for Backup team and NetApp team ------#
 
function servicenow_snapdiff_ritm(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true, HelpMessage="placement solution")]
      [hashtable]$placement_solution
   )
 
   $return_values = @()
   $backup_required = $False
 
   $proxy_ritm_short_description = "TASK 2 - Configure proxy server for snapdiff backup"
   $proxy_ritm_description       = "TASK 2 - Configure proxy server for snapdiff backup for following storage volume - "
  
   $schedule_ritm_short_description = "TASK 3 - Configure backup schedule for NetApp volume"
   $schedule_ritm_description       = "TASK 3 - Configure backup schedule for following NetApp storage volume - "
  
   $validation_ritm_short_description = "TASK 4 - Validate snapdiff backup successful run"
   $validation_ritm_description       = "TASK 4 - Validate snapdiff backup successful scheduled run for following storage volume - "
  
   $base_url               = https://dbunityworker.service-now.com/api/now/table/sc_task
   $proxy                  = http://serverproxy.intranet.db.com:8080
   $content_type           = "application/json"
   $Authorization          = "Basic bmFzX2F1dG9tYXRpb25faW50ZXJmYWNlOk5mMkoxeE1N"
 
   $volume  = $placement_solution['resources']['ontap_volume']
   $qtree   = $placement_solution['resources']['ontap_qtree']
   $host_location = $($qtree[0]['hostname']).Substring(0,3)
   $vserver = $qtree[0]['vserver']+$acl_codes_map['domains'][$host_location.ToLower()]
 
  
   foreach($data in $placement_solution['return_values']){
      if($data.Contains('__res_type=ontap_volume;')){
         $backup_required = $true
      }
   }
 
   if((($request['environment'].ToLower() -eq $PROD) -and `
      (-not ($request['service_name'].ToLower() -eq $EDISCOVERY))) -and `
      (($request['service_level'].ToLower() -eq $NAS_SHARED) -or `
      ($request['service_level'].ToLower() -eq $NAS_PREMIUM -and `
      $request['location'].ToLower() -eq 'ind'))){
 
      if ($backup_required){
 
         #---- RITM for platform team to configure snapdiff proxy ----#     
 
         Get-WfaLogger -Info -Message $("Backup Required - creating snapdiff ritm")
         Get-WfaLogger -Info -Message $("Adding backup details for " + $volume_details)
         $volume_details += @(
            'volume: '       + $volume['name']    + ' and ' + `
            'vserver: '      + $vserver
         );
 
         $proxy_ritm_description += $volume_details 
 
         if($request['protocol'].ToLower() -like "nfs"){
 
                  $assignment_group = "hp_global_unix"
                 
                  }
 
         elseif ($request['protocol'].ToLower() -like "smb"){
 
                  $assignment_group = "global_hcl_wintel"
              
                  }
              
            $return_values +=                                              `
               '__res_type=snow_ritm;'                                    +       `
               'short_description='        + $proxy_ritm_short_description  + ','              + `
               'description='              + $proxy_ritm_description  + ','              + `
               'base_url='                 + $base_url   + ','   + `
               'authorization='            + $Authorization + ','              + `
               'request_item='             + $request['snow_request_id']      + ','                 + `
               'protocol='                 + $request['protocol']      + ','                 + `
               'proxy='                    + $proxy      + ','                 + `
               'action='                   + 'snapdiff_proxy'      + ','                 + `
               'assignment_group='         + $assignment_group
 
         #---- RITM for backup team to add volume to backup schedule ----#
 
            $schedule_ritm_description += $volume_details
 
         # ---- JIRA GSSC-778 Update Backup task3 with Retention period  -----
         if($request['service_name'].ToLower() -eq $FSU){
            $schedule_ritm_description += $RETENTION_FSU }
         elseif($request['service_name'].ToLower() -eq $VFS){
            $schedule_ritm_description += $RETENTION_VFS }          
         elseif($request['service_name'].ToLower() -eq $GFS){
            $schedule_ritm_description += $RETENTION_GFS}  
         elseif($request['service_name'].ToLower() -eq $FABRIC){
            $schedule_ritm_description += $RETENTION_FABRIC}
 
            $return_values +=                                              `
               '__res_type=snow_ritm;'                                    +       `
               'short_description='        + $schedule_ritm_short_description  + ','              + `
               'description='              + $schedule_ritm_description  + ','              + `
               'base_url='                 + $base_url   + ','   + `
               'authorization='            + $Authorization + ','              + `
               'request_item='             + $request['snow_request_id']      + ','                 + `
               'proxy='                    + $proxy      + ','                 + `
               'action='                   + 'snapdiff_schedule'      + ','                 + `
               'assignment_group='         + 'HP_GLOBAL_BACKUP'
 
         #---- RITM for NetApp team to validate backup schedule and successful backup run ----#
 
            $validation_ritm_description += $volume_details
 
            $return_values +=                                              `
               '__res_type=snow_ritm;'                                    +       `
               'short_description='        + $validation_ritm_short_description  + ','              + `
               'description='              + $validation_ritm_description  + ','              + `
               'base_url='                 + $base_url   + ','   + `
               'authorization='            + $Authorization + ','              + `
               'request_item='             + $request['snow_request_id']      + ','                 + `
               'proxy='                    + $proxy      + ','                 + `
               'action='                   + 'snapdiff_validation'      + ','                 + `
               'assignment_group='         + 'DB_GLOBAL_NETAPP'
            }
 
   }
 
 
   $snow_ritm = @{
      'success'         = $True;
      'reason'          = "Creating snapdiff RITM in ServiceNow";
      'return_values'   = $return_values
   }  
   return $snow_ritm
}
 
#------- JIRA GSSC-365 : Enable volume efficiency for new volumes -------#
 
function volume_efficiency(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$volume
   )
   $return_values = @()
   $return_values += `
         '__res_type=ontap_volume_efficiency;'                     + `
         'hostname='       + $volume['hostname']       + ',' + `
         'vserver='        + $volume['vserver']        + ',' + `
         'path='           + '/vol/' + $volume['name']
 
   $ontap_volume_efficiency = @{
            'success'         = $True;
            'reason'          = "Enable volume efficiency";
            'return_values'   = $return_values
   } 
   
   Get-WfaLogger -Info -Message "Enable volume efficiency for volume"
   
   return $ontap_volume_efficiency
 
}
 
#------- NETAPPMS-223 : SSNAP - Automate CVO CBS for new volumes -------#
 
 
function get_working_env_id(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$volume
   )
   $id_token = @{}
   $bluexp = @{}
   Get-WfaLogger -Info -Message "get_working_env_id()"
   $host1 = "bluexp"
   Get-WfaLogger -Info -Message "Before Creds"
   $cred = Get-WfaCredentials -Host $host1
   Get-WfaLogger -Info -Message $($cred.UserName)
   Get-WfaLogger -Info -Message "After creds"
   $bluexp['client_id'] = $cred.UserName
  
    
   $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password)
   $bluexp['refresh_token'] = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
   [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
 
   $url = https://netapp-cloud-account.auth0.com/oauth/token
   $headers = @{
        "Content-Type"      ="application/json";
        "Accept"            ="application/json";  
   }
#$general_headers = $general_headers | ConvertTo-Json
   $payload = @{
            "grant_type"     = "refresh_token";
            "refresh_token"  = $bluexp['refresh_token'];
            "client_id"      = $bluexp['client_id'];
   }
 
try{
$response = Invoke-WebRequest -uri $url -Method POST `
                 -body $($payload|ConvertTo-Json) `
                 -headers $headers `
                 -proxy $PROXY
 
if ($response.StatusCode -eq 200){
$token = "Bearer "+($response.Content|ConvertFrom-Json).access_token}
$id_token['access_token'] = $token
}
catch {
      Get-Wfalogger -Info -Message $($_ | out-string)
   }
Get-WfaLogger -Info -Message $token
 
$url1 = https://cloudmanager.cloud.netapp.com/account/account-OYHUtF5r/providers/cloudmanager_cbs/api/v1/backup/working-environment
 
$headers1 = @{
        "Content-Type"      ="application/json";
        "Accept"            ="application/json";  
        "x-agent-id"        = $CONNECTOR_ID;
        "Authorization"     = $token;
}
 
$cvo = ($volume['hostname']).split(".")[0]
 
try{
$response1 = Invoke-WebRequest -uri $url1 -Method GET `
                 -headers $headers1 `
                 -proxy $PROXY
 
   if($response1.StatusCode -eq 200){
      $result = ($response1.Content|ConvertFrom-Json).'working-environment' | Where-Object { $_.name -eq $cvo}
      $id_token['env_id'] = $result.id
   }
}
catch {
      Get-Wfalogger -Info -Message $($_ | out-string)
}
 
Get-Wfalogger -Info -Message "End of get_working_env_id()"
return $id_token
 
}  
 
function cvo_cbs_backup(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$volume
   )
 
   Get-WfaLogger -Info -Message "Inside cvo_cbs_backup"
   $cvo = ($volume['hostname']).split(".")[0]
   ###----- Get Working Environment ID and Token ------#
   Get-WfaLogger -Info -Message "Calling get_working_env_id()"
   $id_token = get_working_env_id -request $request -volume $volume
   $url = https://cloudmanager.cloud.netapp.com/account/account-OYHUtF5r/providers/cloudmanager_cbs/api/v1/backup/working-environment/+$id_token['env_id']+"/volume/"
   Get-WfaLogger -Info -Message $($url|out-string)
 
   $return_values = @()
   $return_values += `
         '__res_type=cvo_ontap_backup;'                            + `
         'hostname='            + $volume['hostname']              + ',' + `
         'url='                 + $url                             + ',' + `
         'access_token='        + $id_token['access_token']        + ',' + `
         'x_agent_id='          + $CONNECTOR_ID                    + ',' + `
         'vol_name='            + $volume['name']                  + ',' + `
         'https_proxy='         + $PROXY                           + ',' + `
         'backup_policy_name='  + $CVO_BACKUP_POLICY
 
 
   $cvo_volume_backup = @{
            'success'         = $True;
            'reason'          = "Enable CVO volume Backup";
            'return_values'   = $return_values
   } 
   
   Get-WfaLogger -Info -Message "Enable CVO volume Backup"
   
   return $cvo_volume_backup
 
}
 
########################################################################
# VARIABLES & CONSTANTS
########################################################################
$cluster_service_map = @{
   'NAS Premium' = @{
      'platform_code'  = 'mc';
      'gfs' = @{       
         'prefix'  = '';
         'service'   = 'nas_premium_gfs';
         'std_name'  = 'nas_premium'
      }; 
      'Fabric' = @{
         'prefix'  = '';
         'service'   = 'nas_premium_fabric';
         'std_name'  = 'nas_premium'
         'qtree_export_policy'  = @{
            'prd'  =  'ose_platform_prd';
            'uat'  =  'ose_platform_uat';
            'int'  =  'ose_platform_int';
            'dev'  =  'ose_platform_int'
         };
      }; 
   };
  'NAS Shared'    = @{
      'platform_code'  = 'cl';
      'FSU' = @{
         'prefix'  = 'f';
         'service'   = 'nas_shared_fsu';
         'std_name'  = 'nas_shared'
      };
      'VFS' = @{
         'prefix'  = 'v';
         'service'   = 'nas_shared_vfs';
         'std_name'  = 'nas_shared'
      };
      'eDiscovery' = @{
         'prefix'  = 'e';
         'service'   = 'nas_shared_ediscovery';
         'std_name'  = 'nas_shared'
      };  
   };
   'CVO'    = @{
      'platform_code' = @{
         'rehost' = 'rh';
         'native' = 'nt'
      };
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
 
$acl_codes_map = @{
   'services'  = @{
      'NAS Premium'   = 'P';
      'NAS Shared'    = 'S';
      'CVO'           = 'C'
  };
   'regions'   = @{
      'LON'    = 'EM';
      'FRA'    = 'EM';
      'SIN'    = 'AP';
      'NYC'    = 'US';
      'IND'    = 'AP';
      'TKO'    = 'AP';
      'HKG'    = 'AP';
      'AUS'    = 'AP';
      'SYD'    = 'AP';
 
   };
   'domains'   = @{
      'LON'    = '.uk.db.com';
      'FRA'    = '.de.db.com';
      'SIN'    = '.sg.db.com';
      'NYC'    = '.us.db.com';
      'NJM'    = '.us.db.com';
      'IND'    = '.in.db.com';
      'PNQ'    = '.in.db.com';
      'MUM'    = '.in.db.com';
      'TOK'    = '.jp.db.com';
      'HKG'    = '.hk.db.com';
      'SYD'    = '.au.db.com';
      'AUS'    = '.au.db.com';
 
   };
   'environments' = @{
      'prd'          = 'P';
      'uat'          = 'U';
      'dev'          = 'D';
   };
 
   'non-geo-locations' = @(
   'hkg','aus');
 
   'cvo_domains' =      @{
      'Native' =     @{
         'dev' =  @{
            'LON' =  '.uk.cvo.dev.gcp.db.com';
            'FRA' =  '.de.cvo.dev.gcp.db.com';
            'NYC' =  '.us.cvo.dev.gcp.db.com';
            'SIN' =  '.sg.cvo.dev.gcp.db.com';
         };
         'uat' =  @{
            'LON' =  '.uk.cvo.uat.gcp.db.com';
            'FRA' =  '.de.cvo.uat.gcp.db.com';
            'NYC' =  '.us.cvo.uat.gcp.db.com';
            'SIN' =  '.sg.cvo.uat.gcp.db.com';
         };
         'prd' =  @{
            'LON' =  '.uk.cvo.prd.gcp.db.com';
            'FRA' =  '.de.cvo.prd.gcp.db.com';
            'NYC' =  '.us.cvo.prd.gcp.db.com';
            'SIN' =  '.sg.cvo.prd.gcp.db.com';
         };
      };
      'Rehost' =     @{
         'dev' =  @{
            'LON' =  '.uk.db.com';
            'FRA' =  '.de.db.com';
            'NYC' =  '.us.db.com';
            'SIN' =  '.sg.db.com';
         };
         'uat' =  @{
            'LON' =  '.uk.db.com';
            'FRA' =  '.de.db.com';
            'NYC' =  '.us.db.com';
            'SIN' =  '.sg.db.com';
         };
         'prd' =  @{
            'LON' =  '.uk.db.com';
            'FRA' =  '.de.db.com';
            'NYC' =  '.us.db.com';
            'SIN' =  '.sg.db.com';
         };
      }
   }
}
 
 
 
$VOL_USAGE_MAX       = 0.8
$VOL_SIZE_STD_GB     = 10*1024   # 10 TB
$VOL_OVERCOMMIT_MAX  = 1.2
$AGGR_USED_THRESHOLD_PERCENT  = 0.85
$VOL_NEW_PROV_USAGE_MAX_PCT = .63
$VOL_NAME_IDX_DIGITS = 3
$STORAGE_REQUIREMENT_UNITS = 'g'
$STORAGE_REQUIREMENT_UNITS_QUOTAS = 'GB'
$CVO_MAX_VOL_SIZE = 300
 
 
$QTREE_NUM_DIGITS    = 5
$QTREE_FLD_SERVICE   = 0
$QTREE_FLD_ENV       = 1
$QTREE_FLD_IDX       = 2
$VOLUME_FLD_IDX      = 3
 
$SERVICENOW_COMMENT = "Your "+$service_name+" has been allocated. Your mount details are - "
$GFS                = 'gfs'
$FABRIC             = 'fabric'
$FSU                = 'fsu'
$VFS                = 'vfs'
$EDISCOVERY         = 'ediscovery'
$PROD               = 'prd'
$UAT                = 'uat'
$DEV                = 'dev'
$INT                = 'int'
$NFS                = 'nfs'
$SMB                = 'smb'
$NAS_PREMIUM        = 'NAS Premium'
$NAS_SHARED         = 'NAS Shared'
$CVO                = 'CVO'
$CIFS_DOMIAN        = 'dbg.ads.db.com'
$SNAPDIFF_NETGROUP  = 's-in-prod-snapdiff-nfs'
$RETENTION_FSU      = '. Backup Retention Period for FSU : LTR. '
$RETENTION_VFS      = '. Backup Retention Period for VFS : LTR. '
$RETENTION_GFS      = '. Backup Retention Period for GFS : LTR. '
$RETENTION_FABRIC   = '. Backup Retention Period for FABRIC : LTR. '
$isRequestGFS       = $false
$DBAG_NAR_ID        = '65953-2'
$SNAPVAULT_SITE     = @("nyc","fra","sin","lon")
$MC3_SITE           = @("nyc","fra","ind","sin","lon")
$none               = 'none' #for the new columns as part of CI
$CVO_BACKUP_POLICY  = 'CBS_32_Daily'
$PROXY              = 'http://serverproxy.intranet.db.com:8080'
$CONNECTOR_ID       = 'Pt7WLcnolAjnqgkxCvjdv97YrnjEICGEclients'
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
elseif($protocol.ToLower() -eq "nfs"){
   $protocol_version = "nfs"
   $protocol_type = "nfs"
}
elseif($protocol.ToLower() -eq "smb"){
   $protocol_version = "smb"
   $protocol_type = "smb"
}
#------NETAPPMS-6: MC2 to MC3 migration for GFS DEV re-location to NAS Shared ----#
if(($service_name.ToLower() -eq $GFS) -and ($environment.ToLower() -eq $DEV)){
   $service_level = $NAS_SHARED
   $service_name = $VFS.ToUpper()
   $isRequestGFS = $true
}
###---NETAPPMS-257: SSNAP - Workaround fix for FSU (PRD) Protocol field value---###
if($service_name.ToLower() -eq $FSU){
    $protocol_version = $SMB
    $protocol_type = $SMB
}
 
$request = @{
   'app_short_name'                = $app_short_name.ToLower();
   'contact'                       = $contact;
   'cost_centre'                   = $cost_centre.split(" ")[0];
   'email_address'                 = $email_address;
   'environment'                   = $environment.ToLower();
   'location'                      = ($location.split('-')[0]).ToLower();
   'site'                          = $location.split('-')[1];
   'nar_id'                        = $nar_id;
   'netgroup_ro'                   = $netgroup_ro;
   'netgroup_rw'                   = $netgroup_rw;
   'nis_domain'                    = $nis_domain.ToLower();
   'protocol'                      = $protocol_type;
   'protocol_version'              = $protocol_version;
   'service_level'                 = $service_level.ToLower();
   'service_name'                  = $service_name.ToLower();
   'snow_request_id'               = $snow_request_id;
   'storage_instance_count'        = $storage_instance_count;
   'storage_requirement'           = $storage_requirement;
   'correlation_id'                = $correlation_id;
   'smb_acl_group_contact'         = $smb_acl_group_contact;
   'smb_acl_group_delegate'        = $smb_acl_group_delegate;
   'smb_acl_group_approver_1'      = $smb_acl_group_approver_1;
   'smb_acl_group_approver_2'      = $smb_acl_group_approver_2;
   'dfs_root_path'                 = $dfs_root_path;
   'dfs_path_1'                    = $dfs_path_1;
   'dfs_path_2'                    = $dfs_path_2;
   'dfs_new_folder'                = $dfs_new_folder;
   'dfs_folder'                    = $dfs_folder;
   'sys_id'                        = $sys_id;
   'landing_zone'                  = $landing_zone;
   'platform'                      = $platform;
   'ekm'                           = $ekm
}
#---------------------------------------------------------------
# The placement solution maintains both the return values and
# what amounts to an object definition.  The return values are
# taken unchanged and passed as WFA workflow return values.
# The objects are maintained because some are used in order to
# fully define other objects.
#---------------------------------------------------------------
#---------------------------------------------------------------
# NETAPP-70
# Get our current state from the db.lock table.  If we have timed
# out, we bail at this point.
# Set success to FALSE and reason as TIMEDOUT waiting for lock
#---------------------------------------------------------------
 
# NETAPPMS - 346 Check RITM in chargeback and stop execution to avoid multiple runs
$sql = "SELECT ritm from playground.chargeback where ritm = '$($request['snow_request_id'])';"
$result = Invoke-MySqlQuery -Query $sql -user 'root' -password $mysql_pass
if ( $result[0] -gt 0 ){
   $fail_msg = 'RITM already executed once and present in chargeback table'
   Get-WfaLogger -Info -Message $($fail_msg)
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
 
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
# The VOlume Standard side is different for Dev and prd environment.
# So added this to change the $VOL_SIZE_STD_GB to 4GB in case of prd
#---------------------------------------------------------------
if($request['environment'].ToLower() -eq "prd"){
   $VOL_SIZE_STD_GB = 4*1024
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
 
#---------------------------------------------------------------
# Added to check if we support specific service under the service level
# fail to supoort that service, It should fail gracefully.
#---------------------------------------------------------------
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
 
#---------------------------------------------------------------
# Get the vserver that matches the NIS Domain
#---------------------------------------------------------------
Get-WfaLogger -Info -Message "##################### VSERVERS #####################"
$vservers = vserver `
         -request $request `
         -mysql_pw $mysql_pass
if ( -not $vservers['success'] ){
   $fail_msg = $vservers['reason'] + ": nis_domain=" + $request['nis_domain']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
$placement_solution['resources']['ontap_vserver'] = $vservers['ontap_vserver']
 
#---------------------------------------------------------------
# Get an aggregate in case we need a new volume.  We could do
# this after we determine whether or not we need a new volume,
# but this is not that expensive to do it here and just makes
# things a bit easier IMHO.
#---------------------------------------------------------------
Get-WfaLogger -Info -Message "##################### AGGR #####################"
Get-WfaLogger -Info -Message "Find an aggr"
$aggr = aggregate                               `
      -vservers      $vservers['ontap_vserver']  `
      -vol_size      $VOL_SIZE_STD_GB              `
      -mysql_pw      $mysql_pass
if ( -not $aggr['success'] ){
   #----------------------------------------------------------------------
   # I'm not going to exit here because, we may not end up actually
   # needing an aggr and I don't want to fail the request for lack of a
   # a resource that we don't really need in this case.  So we'll just
   # log the inability to find an aggr here in WFA and move on for now.
   #----------------------------------------------------------------------
   $fail_msg = $aggr['reason']
   Get-WfaLogger -Info -Message $fail_msg
   Get-WfaLogger -Info -Message "Continuing until we know if actually needed the aggr we couldn't find."
}
 
Get-WfaLogger -Info -Message "##################### VOLUME #####################"
$volume = volume `
      -vservers $vservers['ontap_vserver'] `
      -aggregate $aggr['ontap_aggr'] `
      -request $request `
      -mysql_pw $mysql_pass
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
 
if ( ($request['protocol'].ToLower() -eq 'smb') -and ($placement_solution['return_values'].Count -ne 0) ){
   foreach($data in $placement_solution['return_values']){  
      if($data.Contains('__res_type=ontap_volume;')){
         Get-WfaLogger -Info -Message "##################### CIFS SHARE - SMB volume root #####################"
         $cifs_volume_root = cifs_volume_root `
         -request  $request                  `
         -volume   $volume['ontap_volume']    ` 
         $placement_solution['return_values'] += $cifs_volume_root['return_values']  
      }
 
      #------ JIRA NETAPPMS-219 (Add logic for CVO - Native DNS update)
      if($data.Contains('__res_type=cvo_ontap_volume;')){
         Get-WfaLogger -Info -Message "##################### CVO CIFS SHARE - SMB volume root #####################"
         $cvo_cifs_volume_root = cvo_cifs_volume_root `
         -request  $request                  `
         -volume   $volume['ontap_volume']    `
         $placement_solution['return_values'] += $cvo_cifs_volume_root['return_values']  
      }
   }
  
}
 
#------- JIRA GSSC-365 : Enable volume efficiency for new volumes -------#
 
if ( ($placement_solution['return_values'].Count -ne 0) ){
   foreach($data in $placement_solution['return_values']){  
      if($data.Contains('__res_type=ontap_volume;') -or $data.Contains('__res_type=cvo_ontap_volume;')){
         Get-WfaLogger -Info -Message "##################### Volume Efficiency #####################"
         $ontap_volume_efficiency = volume_efficiency `
         -request  $request                  `
         -volume   $volume['ontap_volume']    `            }
   }
   $placement_solution['return_values'] += $ontap_volume_efficiency['return_values']  
}
 
if($request['service_level'] -ne $CVO){
Get-WfaLogger -Info -Message "##################### QTREE NAME #####################"
 
$qtrees = qtree  `
   -request    $request  `
   -volume     $volume['ontap_volume']       `
   -mysql_pw   $mysql_pass
if ( -not $qtrees['success'] ){
   $fail_msg = $qtrees['reason']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
   exit
}
Get-WfaLogger -Info -Message "Before adding qtree resources"
$placement_solution['resources']['ontap_qtree'] = $qtrees['ontap_qtree']
Get-WfaLogger -Info -Message "Before adding qtree return values"
$placement_solution['return_values'] += $qtrees['return_values']
Get-WfaLogger -Info -Message "Qtrees all finished"
Get-WfaLogger -Info -Message "##################### QUOTA RULE #####################"
$quota = quota  `
   -request    $request                      `
   -qtrees     $qtrees['ontap_qtree']       `
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
 
if ( $request['protocol'].ToLower() -eq 'nfs' ){
   if( $request['service_level'] -eq $CVO ){
      Get-WfaLogger -Info -Message "##################### CVO NFS EXPORT #####################"
      $nfs_export = cvo_nfs_export `
      -request  $request                  `
      -volume   $volume['ontap_volume']     `
      -mysql_pw      $mysql_pass
   }
   else{
      Get-WfaLogger -Info -Message "##################### NFS EXPORT #####################"
      $nfs_export = nfs_export `
         -request  $request                  `
         -qtrees   $qtrees['ontap_qtree']     `
         -mysql_pw      $mysql_pass
   }
   if ( -not $nfs_export['success'] ){
      $fail_msg = $nfs_export['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
 
   $placement_solution['return_values'] += $nfs_export['return_values']
}
elseif ( $request['protocol'].ToLower() -eq 'smb' ){
   if( $request['service_level'] -eq $CVO ){
   Get-WfaLogger -Info -Message "##################### CVO CIFS SHARE #####################"
      $cifs = cvo_cifs `
      -request  $request                  `
      -volume   $volume['ontap_volume']    `
      -mysql_pw      $mysql_pass
   }
   else{
   Get-WfaLogger -Info -Message "##################### CIFS SHARE #####################"
      $cifs = cifs `
         -request  $request                  `
         -qtrees   $qtrees['ontap_qtree']     `
         -volume   $volume['ontap_volume']    `
         -mysql_pw      $mysql_pass
   }
   if ( -not $cifs['success'] ){
      $fail_msg = $cifs['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
   $placement_solution['return_values'] += $cifs['return_values']
   $placement_solution['resources']['ontap_cifs'] = $cifs['ontap_cifs']
 
}
 
#---------------------------------------------------------------
# Calling snapvault function
#---------------------------------------------------------------
$SnapVault_required = $false
if(($request['environment'].ToLower() -eq $PROD) -and
   (($request['service_level'].ToLower() -eq $NAS_PREMIUM) -and ($SNAPVAULT_SITE.Contains($request['location'].ToLower())))){
   foreach($data in $placement_solution['return_values']){
   if($data.Contains('__res_type=ontap_volume;')){
      $SnapVault_required = $true
      } 
   }
}
 
if($SnapVault_required -eq $true){
Get-WfaLogger -Info -Message "##################### SnapVault details if required #####################"
 
$snapvault_vol = snapvault_volume  `
   -request $request  `
   -placement_solution   $placement_solution   `
   -mysql_pw      $mysql_pass
if ( -not $snapvault_vol['success'] ){
   $fail_msg = $snapvault_vol['reason']
   Get-WfaLogger -Info -Message $fail_msg
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
   set_wfa_return_values $placement_solution
}
Get-WfaLogger -Info -Message "Adding SnapVault details"
$placement_solution['resources']['ontap_snapvault_volume'] = $snapvault_vol['ontap_snapvault_volume']
$placement_solution['resources']['ontap_snapvault_dr_volume'] = $snapvault_vol['ontap_snapvault_dr_volume']
Get-WfaLogger -Info -Message "Before adding snapvault volume return values"
$placement_solution['return_values'] += $snapvault_vol['return_values']
Get-WfaLogger -Info -Message "Snapvault volume all finished"
}
 
#---------------------------------------------------------------
# Calling snapvault function
#---------------------------------------------------------------
if($SnapVault_required -eq $true)
{
   Get-WfaLogger -Info -Message "##################### SNAPVAULT RELATIONSHIP #####################"
   $snapvault = snapvault `
      -request $request     `
      -placement_solution $placement_solution
 
   if ( -not $snapvault['success'] ){
      $fail_msg = $volume['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
 
Get-WfaLogger -Info -Message "Adding Return Values for snapvault relationship"
$placement_solution['return_values'] += $snapvault['return_values']
Get-WfaLogger -Info -Message "snapvault relationship all finished"
}
 
#---------------------------------------------------------------
# Calling servicenow function
#---------------------------------------------------------------
Get-WfaLogger -Info -Message "##################### SET SERVICE NOW #####################"
   if( $request['service_level'] -eq $CVO ){
      $snow = cvo_servicenow `
      -request $request      `
      -placement_solution   $placement_solution 
   }
   else{
      $snow = servicenow `
      -request $request      `
      -placement_solution   $placement_solution 
   }  
   if ( -not $snow['success'] ){
      $fail_msg = $snow['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
 
   $placement_solution['return_values'] += $snow['return_values']
 
 
#---------------------------------------------------------------
# Calling SNAPDIFF servicenow function
#---------------------------------------------------------------
 
#------- JIRA GSSC-368 : RITM for SnapDiff proxy server configuration -------#
#------- JIRA GSSC-667 : Include MC3 NYC for SnapDiff -------#
#------- NETAPPMS-139  : Include IND Fabric for Snapdiff
if($request['service_level'].ToLower() -eq $NAS_SHARED -or `
   ($request['service_level'].ToLower() -eq $NAS_PREMIUM -and `
   $request['location'].ToLower() -eq 'ind')){
Get-WfaLogger -Info -Message "##################### SERVICENOW CREATE SNAPDIFF RITM #####################"
 
  $snow_ritm = servicenow_snapdiff_ritm `
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
 
   $placement_solution['return_values'] += $snow_ritm['return_values']
}
 
#------- NETAPPMS-223 : SSNAP - Automate CVO CBS for new volumes -------#
 
if(($request['environment'].ToLower() -eq $PROD) -and $request['service_level'] -eq $CVO){
Get-WfaLogger -Info -Message "##################### CVO CBS Backup #####################"
 
  $cvo_volume_backup = cvo_cbs_backup `
               -request $request      `
               -volume  $volume['ontap_volume']   
   if ( -not $cvo_volume_backup['success'] ){
      $fail_msg = $cvo_volume_backup['reason']
      Get-WfaLogger -Info -Message $fail_msg
      $placement_solution['success']   = 'FALSE'
      $placement_solution['reason']    = $fail_msg
      set_wfa_return_values $placement_solution
      exit
   }
 
   $placement_solution['return_values'] += $cvo_volume_backup['return_values']
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
if( $request['service_level'] -eq $CVO ){
   update_cvo_chargeback_table `
      -volume $volume['ontap_volume']    `
      -request $request `
      -db_user 'root' `
      -db_pw $mysql_pass `
      -placement_solution $placement_solution
}
else{
   update_chargeback_table `
      -qtrees $qtrees['ontap_qtree'] `
      -request $request `
      -db_user 'root' `
      -db_pw $mysql_pass `
      -placement_solution $placement_solution
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
