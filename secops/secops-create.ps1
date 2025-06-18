
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
 
   [parameter(Mandatory=$False, HelpMessage="protocol (NFS|CIFS)")]
   [string]$protocol,
 
   [parameter(Mandatory=$True)]
   [string]$service_level,
 
   [parameter(Mandatory=$True)]
   [string]$service_name,
 
   [parameter(Mandatory=$False)]
   [int]$storage_requirement,
 
   [parameter(Mandatory=$False)]
   [string]$servers
 
)
 
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
 
<#cls
$app_short_name='secops'
$contact='jai'
$cost_centre='123'
$email_address='jai.waghela@netapp.com'
$environment='prd'
$location='lon'
$nar_id='456'
$protocol='nfs'
$service_level='NAS Premium'
$service_name='secops'
$storage_instance_count='4'
$storage_requirement='25'
$servers='srv1,srv2,srv3'
$ritm = 'RITM0000001'
#>
 
 
function svm_selection_logic() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request
   )
 
   Get-WfaLogger -Info -Message "Entered svm_selection_logic with request =="
   $regular_regex = $request['location'].ToLower() + '[a-zA-Z]{3}'
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
 
        $cluster_name_regex = $regular_regex +`
                              'nas' + $cluster_service_map[$service_level]['platform_code']  + `
                              $request['environment'][0] + '[0-9]+'
      
        $svm_name_regex = $regular_regex +`
                         $cluster_service_map[$service_level]['platform_code']  + `
                         $request['environment'][0]+'[0-9]+'                 + `
                         'svm' +`
                         '[0-9]+' 
      
      if($request['environment'] -eq $DEV)
      {
      $cluster_env = $UAT
        if($request['location'].ToLower() -eq "fra")
            {
                $regular_regex = '(lon|fra)' + '[a-zA-Z]{3}'               
            }
 
        if($request['location'].ToLower() -eq "nyc")
            {
                $svm_name_regex = $regular_regex +`
                         $cluster_service_map[$service_level]['platform_code']  + `
                         '[a-zA-Z]{1}' + $request['environment'][0]+'[0-9]+'                 + `
                         'svm' +`
                         '[0-9]+'               
            }
 
        if(($request['location'].ToLower() -eq "sin") -and ($request['service_name'].ToLower() -eq $SECOPS))
            {
                $cluster_env = $PROD
                $svm_name_regex = $regular_regex +`
                         $cluster_service_map[$service_level]['platform_code']  + `
                         'u' +'[0-9]+'                 + `
                         'svm' +`
                         '[0-9]+'               
            }
 
        $cluster_name_regex = $regular_regex +`
                              'nas' + $cluster_service_map[$service_level]['platform_code']  + `
                              $cluster_env[0] + '[0-9]+'
       }
 
       if(($request['environment'] -eq $UAT) -and (($request['location'].ToLower() -eq "fra") -or ($request['location'].ToLower() -eq "sin") ))
      {
        $cluster_env = $PROD
        $cluster_name_regex = $regular_regex +`
                              'nas' + $cluster_service_map[$service_level]['platform_code']  + `
                              $cluster_env[0] + '[0-9]+'
                              }
 
       if(($request['location'].ToLower() -eq "nyc") -and ($request['environment'] -ne $DEV)){
         $cluster_env = $PROD
         $regular_regex = $request['location'].ToLower() + '[a-zA-Z0-9]{3}'
         $cluster_name_regex = $regular_regex +`
                              $cluster_service_map[$service_level]['platform_code'] + `
                              $cluster_env[0] + '[0-9]+'
                             
         $svm_name_regex = $regular_regex +`
                        $cluster_service_map[$service_level]['platform_code']  + `
                        $request['environment'][0] +'[0-9]+'                   + `
                        'svm' + '[0-9]+'
                        }
                                              
   if ($request['service_name'].ToLower() -eq $SECOPS){
 
             $sql+=  " AND cluster.name REGEXP '" + $cluster_name_regex + "'" +`
                     " AND vserver.name REGEXP '" + $svm_name_regex + "'" +`
                     " AND vserver.type = 'data' "             
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
 
<#    $sql = $sql = "
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
                         "AND vserver.name REGEXP 'loninengclsp02'" +`
                         " AND vserver.type = 'data' " +`
                         "GROUP BY vserver.id ORDER BY vserver_volume_count ASC;"
 
    #---------- End of test query------------------------------------#>
 
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
      [string]$db_pw
   )
   Get-WfaLogger -Info -Message "Entered update_chargeback_table()"
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
            '" + $request['netgroup_ro']                                   + "',
            '" + $request['netgroup_rw']                                   + "',
            '" + $request['email_address']                                 + "',           
            '" + $qtree['hostname']                                        + "',
            NULL,
            '" + $request['environment']                                   + "',
            '" + $request['correlation_id']                               + "'
         )
         ;
      "
      Get-WfaLogger -Info -Message $new_row
      Invoke-MySqlQuery -query $new_row -user $db_user -password $db_pw
   }
}
 
function update_budget_table(){
   param(
      [parameter(Mandatory=$true)]
      [array]$qtrees,
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
   Get-WfaLogger -Info -Message "old budget : $($result[1].budget)"
   Get-WfaLogger -Info -Message "no. of hosts : $($qtrees.length)"
   Get-WfaLogger -Info -Message "Total storage requested : $($qtrees.length * $request['storage_requirement'])"
   Get-WfaLogger -Info -Message "budget allocated : $($result[1].budget - ($qtrees.length * $request['storage_requirement']))"
   $budget_allocated = $result[1].budget - ($qtrees.length * $request['storage_requirement'])
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
         AND (aggregate.used_size_mb/aggregate.size_mb) <= 0.9
      ORDER BY aggregate.available_size_mb DESC
      ;"
   Get-WfaLogger -Info -Message $aggr_select_sql
   Get-WfaLogger -Info -Message $("Looking for an aggr" )
   $aggrs = Invoke-MySqlQuery -query $aggr_select_sql -user root -password $mysql_pw
 
   if ( $aggrs[0] -ge 1 ){
      Get-WfaLogger -Info -Message $("Found aggr: " + $aggrs[1].name )
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
   $sql = svm_selection_logic -request $request        
   Get-WfaLogger -Info -Message "Ready to query"
   $vservers = Invoke-MySqlQuery -Query $sql -user 'root' -password $mysql_pass
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
   $key='secops'
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
 
  
 
   $total_share_size = $request['storage_instance_count'] * $request['storage_requirement']
   $vol_select = "
      SELECT
         cluster.name AS 'cluster_name',
         cluster.primary_address AS 'cluster_pri_addr',
         vserver.name AS 'vserver_name',
         volume.name AS 'volume_name',
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
      JOIN cm_storage_quota.quota_rule   ON (
         ( quota_rule.cluster = cluster.name OR quota_rule.cluster = cluster.primary_address )
         AND quota_rule.vserver_name = vserver.name
         AND quota_rule.quota_volume = volume.name
         AND CONCAT('/vol/',volume.name,'/',qtree.name) = quota_rule.quota_target
      )
      WHERE 1
         AND ( $vserver_query )
         AND qtree.name != ''
         AND volume.used_size_mb/volume.size_mb <= $VOL_USAGE_MAX
         AND volume.name REGEXP '$vol_name_regexp'
      GROUP BY volume.name
      HAVING overcommit < $VOL_OVERCOMMIT_MAX
      ORDER BY volume.used_size_mb ASC
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
         'new'             = $False;
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
         'ontap_volume'    = @()
      }
   }
  
   $vserver_list = @()
   $volume = @()
   $volume_autosize = @()
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
   $key='secops'
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
         qtree.name    AS 'qtree_name',
         chargeback.cluster_name AS 'cb_cluster_name',
         chargeback.vserver_name AS 'cb_svm_name',
         chargeback.volume_name  AS 'cb_vol_name',
         chargeback.qtree_name   AS 'db_qtree_name'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver ON (vserver.cluster_id = cluster.id)
      JOIN cm_storage.volume  ON (volume.vserver_id = vserver.id)
      JOIN cm_storage.qtree    ON (qtree.volume_id = volume.id)
      RIGHT JOIN playground.chargeback ON (
         chargeback.cluster_name = cluster.primary_address AND
         chargeback.vserver_name = vserver.name AND
         chargeback.volume_name = volume.name AND
         chargeback.qtree_name = qtree.name
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
 
   if ( $protocol -eq 'nfs' ){
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
  elseif (($request['service_level'] -eq "nas premium") -and ($request['location'].ToLower() -eq "nyc"))
  {
    $volume += @{
         'hostname'     = $aggregate['hostname'];
         'vserver'      = $vserver_name;
         'name'         = $vol_name;
         'junction_path'   = '/' + $vol_name;
         'volume_security_style'  = $security_style;
         'snapshot_policy' = 'GFS_' + $request['environment'].ToUpper() + '_Default';
         'aggregate_name'  = $aggregate['name'];
         'encrypt'         ='True'
        
          }
 
    $volume_autosize += @{
         'hostname'       = $aggregate['hostname'];
         'vserver'        = $vserver_name;
         'volume'         = $vol_name;
         'maximum_size'   = [string]$VOL_SIZE_STD_GB + $STORAGE_REQUIREMENT_UNITS;
         }
  }
   else{   
 
   $volume += @{
         'hostname'     = $aggregate['hostname'];
         'vserver'      = $vserver_name;
         'name'         = $vol_name;
         'junction_path'   = '/' + $vol_name;
         'volume_security_style'  = $security_style;
         'snapshot_policy' = 'GFS_' + $request['environment'].ToUpper() + '_Default';
         'aggregate_name'  = $aggregate['name']
        
          }
 
    $volume_autosize += @{
         'hostname'       = $aggregate['hostname'];
         'vserver'        = $vserver_name;
         'volume'         = $vol_name;
         'maximum_size'   = [string]$VOL_SIZE_STD_GB + $STORAGE_REQUIREMENT_UNITS;
         } 
         
      } 
    
   return @{
      'success'         = $True;
      'new'             = $True;
      'reason'          = "successfully defined new volume";
      'return_values'       = $return_values;
      'ontap_volume'    = $volume;
      'ontap_volume_autosize'    = $volume_autosize;
   }
}
#--------------------------------------------------------------------
# FUNCTION: vol_helper_find_unprovisioned()
#  Search the chargeback table to see if there are any volumes that
#  we know will be provisioned but haven't yet been discovered by
#  WFA.  If there are any and they meet the necessary criteria,
#  return the best one.  If none, return nothing.
#--------------------------------------------------------------------
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
   $key='secops'
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
         qtree.name    AS 'qtree_name',
         chargeback.cluster_name AS 'cb_cluster_name',
         chargeback.vserver_name AS 'cb_svm_name',
         chargeback.volume_name  AS 'cb_vol_name',
         chargeback.qtree_name   AS 'db_qtree_name',
         (SUM(storage_requirement_gb)+$total_share_size)/($VOL_SIZE_STD_GB) AS 'usage'
      FROM cm_storage.cluster
      JOIN cm_storage.vserver ON (vserver.cluster_id = cluster.id)
      JOIN cm_storage.volume  ON (volume.vserver_id = vserver.id)
      JOIN cm_storage.qtree    ON (qtree.volume_id = volume.id)
      RIGHT JOIN playground.chargeback ON (
         chargeback.cluster_name = cluster.primary_address AND
         chargeback.vserver_name = vserver.name AND
         chargeback.volume_name = volume.name AND
         chargeback.qtree_name = qtree.name
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
            'new'             = $False;
            'reason'          = "successfully found unprovisioned volume";
            'return_values'       = @();
            'ontap_volume'    = @(@{
               'hostname'     = $cluster[1]['mgmt_ip'];
               'vserver'      = $vols[1]['cb_svm_name'];
               'name'         = $vols[1]['cb_vol_name'];
            })
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
 
function qtree() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [array]$volume,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
 
   $qtrees        = @()
   $return_values = @()
 
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
   foreach($qtree_name in $request['hosts']){
 
      $qtree_select = "
         SELECT
         qtree_name  AS 'qtree_name'
         FROM playground.chargeback
         WHERE 1        
         AND chargeback.qtree_name = ' " + $qtree_name + " '
         ORDER BY qtree_name DESC
      ;
      "
      Get-WfaLogger -Info -Message "Looking for qtrees on the volume"
      Get-WfaLogger -Info -Message $qtree_select
      $qtrees_entry = Invoke-MySqlQuery -query $qtree_select -user root -password $mysql_pw
   #-----------------------------------------------------------------
   # FIXME: RTU 14 Oct 2020
   # NETAPP-81
   # Change this to return a list of qtrees whose numbers run in
   # sequence starting with the highest index value determined
   #-----------------------------------------------------------------
   if ( $qtrees_entry[0] -ge 1 ){
      Get-WfaLogger -Info -Message $("qtree: " + $qtree_name + "already exist, skipping it")
      continue;
   }
 
   Get-WfaLogger -Info -Message $("qtree_name=" + $qtree_name)
      $qtrees += @{
         'hostname'     = $volume[0]['hostname'];
         'vserver'      = $volume[0]['vserver'];
         'flexvol_name' = $volume[0]['name'];
         'unix_permissions' = '777';
         'name'         = $qtree_name
      }
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
         'policy'       = 'default';
         'quota_target' = '/vol/' + $qtree['flexvol_name'] + '/' + $qtree['name'];
         'disk_limit'   = [string]$request['storage_requirement'] + $STORAGE_REQUIREMENT_UNITS
      }
      Get-WfaLogger -Info -Message $( "Adding return values for qtree: " + $qtree['name'])
      $return_values += `
         '__res_type=ontap_quota;'                                                     + `
         'hostname='          + $qtree['hostname']                              + ',' + `
         'vserver='           + $qtree['vserver']                               + ',' + `
         'volume='            + $qtree['flexvol_name']                                  + ',' + `
         'quota_target='      + '/vol/' + $qtree['flexvol_name'] + '/' + $qtree['name'] + ',' + `
         'disk_limit='        + [string]$request['storage_requirement'] + $STORAGE_REQUIREMENT_UNITS
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
   $return_values = @()
   $ontap_export_policy = @()
   $ontap_export_policy_rule = @()
   $qtree_export_policy = @()
   foreach ( $qtree in $qtrees ){
      Get-WfaLogger -Info -Message $qtree['name']
      $ontap_export_policy += @{
         'hostname'     = $qtree['hostname'];
         'vserver'      = $qtree['vserver'];
         'name'         = $qtree['name'];
      }
      $ontap_export_policy_rule += @{
         'hostname'     = $qtree['hostname'];
         'vserver'      = $qtree['vserver'];
         'name'         = $qtree['name'];
         'client_match' = $qtree['name'];
         'ro_rule'      = 'sys';
         'rw_rule'      = 'sys';
         'super_user_security'  = 'sys';
         'protocol'     = 'nfs3'
      }
      $qtree_export_policy += @{
         'hostname'      = $qtree['hostname'];
         'vserver'       = $qtree['vserver'];
         'flexvol_name'  = $qtree['flexvol_name'];
         'name'          = $qtree['name'];
         'export_policy' = $qtree['name'];
      }
 
   }
   $nfs_export = @{
      'success'      = $True;
      'reason'       = "Testing only";
      'return_values'    = $return_values;
      'ontap_export_policy'   = $ontap_export_policy;
      'ontap_export_policy_rule' = $ontap_export_policy_rule;
      'qtree_export_policy' = $qtree_export_policy
   }
   return $nfs_export
}
 
function mount_paths(){
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [array]$qtrees
   )
   $return_values = @()
   $comment = $SERVICENOW_COMMENT + "<br><br>"
   foreach ( $qtree in $qtrees ){ 
      $mount_paths += $qtree['vserver']+$acl_codes_map['domains'][$qtree['vserver'].ToUpper().Substring(0,3)]+":/"+$qtree['flexvol_name']+"/"+$qtree['name']+"<br>"
   }
   $paths = @{
      'success'      = $True;
      'reason'       = 'Mount path created';
      'return_values'    = $return_values;
      'mount_paths'   = $comment + $mount_paths;
      }  
   return $paths
}
 
function snow_auth() {
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
   $snow_general_headers = @{
        "Content-Type"      ="application/json";
        "Accept"            ="application/json";  
        "Authorization"     ="Bearer ";
       }
       
   $snow_auth_headers = @{
        "Content-Type"  ="application/x-www-form-urlencoded";
       }
  
   try {
      $payload = "client_id="+ $snow_cfg['client_id'] +"&client_secret="+ $snow_cfg['client_secret']
      $payload = $payload + "&grant_type=password&username="+ $snow_cfg['user'] +"&password="+ $snow_cfg['pw']
      $url = $snow_cfg['base_url'] + '/oauth_token.do'
      $response = Invoke-WebRequest -uri $url -Method POST `
                 -body $payload `
                 -headers $snow_auth_headers `
                 -Proxy $snow_cfg['proxy']
      if ($response.StatusCode -eq 200){
         $snow_general_headers['Authorization'] = $snow_general_headers['Authorization'] + $($response.content | convertfrom-json).access_token
         return $snow_general_headers
      }
   }
   catch {
      Get-Wfalogger -Info -Message $($_ | out-string)
   }
}
 
function snow_comment_old() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$snow_cfg,
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$snow_general_headers,
      [parameter(Mandatory=$true)]
      [string]$comment
   )
   #-----------------------------------------------------------------
   # FIXME: RTU 25 Oct 2021
   # NETAPP-81
   # We will now support snow updates from WFA
   # This function will get auth info and perform updates to snow
   #-----------------------------------------------------------------
    try {
      $uri = $snow_cfg['base_url'] + '/api/global/v1/srm_task_api/task/update_actions'
      $data = @{
         'action' = "comment";
         'correlation_id' = $request['correlation_id'];
         'sys_id'= $request['sys_id'];
         'work_notes'= $comment;
         }
      $response = Invoke-WebRequest -uri $uri -Method POST `
         -body $( ConvertTo-Json $data -Depth 10 ) `
         -headers $snow_general_headers `
         -Proxy $snow_cfg['proxy']
      if ($response.StatusCode -ne 200){
         Get-Wfalogger -Info -Message  $("Error commenting SNOW ticket $($_.Exception | out-String)")
      }
      Get-Wfalogger -Info -Message $($response | Out-String)
   }
   catch { Get-Wfalogger -Info -Message $($_ | Out-String)}
}
 
 
function snow_tag_correlation_id() {
    param(
      [parameter(Mandatory=$true)]
      [hashtable]$snow_cfg,
      [parameter(Mandatory=$true)]
      [hashtable]$request,
      [parameter(Mandatory=$true)]
      [hashtable]$snow_general_headers
      )
 
      Get-WfaLogger -Info -Message "Tagging Correlation ID to $request['correlation_id']"
 
      try{
         $uri = $snow_cfg['base_url'] + '/api/global/v1/srm_task_api/task/update_actions'
 
         $data = @{
            'action'= "correlation";
            'correlation_id'= $request['correlation_id'];
            'sys_id'= $request['sys_id'];
            }
         $response = Invoke-WebRequest -uri $uri -Method POST `
            -body $( ConvertTo-Json $data -Depth 10 ) `
            -headers $snow_general_headers `
            -Proxy $snow_cfg['proxy']
 
         Get-WfaLogger -Info -Message "Tagged Correlation ID"
 
         if ($response.status_code -ne 200){
            Get-WfaLogger -Info -Message "Error tagging correlation id : $Error[0]"}
         }
 
      catch{
        
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
         'wfa_auth'     = $basicAuthValue;
         'wfa_job_id'   = $wfa_job_id;
         'content_type' = 'application/json';
         'accept'       = 'application/json';
      }
 
   return @{
      'success'         = $True;
      'reason'          = "successfully set wfa resume parameter";
      'dbrun_wfa_resume'     = $dbrun_resume
   }
}
 
function dbrun_secops_email() {
 
   Get-WfaLogger -Info -Message "Inside dbRun Secops Email"
   $return_values = @()
   $dbrun_secops_email        = @()
 
   $from = 'db.global.netapp@list.db.com'
   $to = 'jai.waghela@db.com'
   $sub = 'SECOPS - DBRun Notification'
 
      $dbrun_secops_email += @{
         'from'      = $from;
         'to'   = $to;
         'wfa_jobid'       = $wfa_job_id;
      }
 
   return @{
      'success'         = $True;
      'reason'          = "successfully set dbrun emailparameters";
      'email'           = $dbrun_secops_email
   }
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
 
$cluster_service_map = @{
   'NAS Premium' = @{
      'platform_code'  = 'mc';
      'gfs' = @{       
         'prefix'  = '';
         'service'   = 'nas_premium_gfs';
         'std_name'  = 'nas_premium'
      };
      'secops' = @{       
         'prefix'  = '';
         'service'   = 'nas_premium_secops';
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
 
 
 
$VOL_USAGE_MAX       = 0.8
$VOL_SIZE_STD_GB     = 10*1024   # 10 TB
$VOL_OVERCOMMIT_MAX  = 1.2
$VOL_NEW_PROV_USAGE_MAX_PCT = .63
$VOL_NAME_IDX_DIGITS = 3
$STORAGE_REQUIREMENT_UNITS = 'g'
 
 
$QTREE_NUM_DIGITS    = 5
$QTREE_FLD_SERVICE   = 0
$QTREE_FLD_ENV       = 1
$QTREE_FLD_IDX       = 2
 
$SERVICENOW_COMMENT = "Your "+$service_name+" has been allocated. Your mount details are -"
$GFS                = 'gfs'
$FABRIC             = 'fabric'
$SECOPS             = 'secops'
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
$CIFS_DOMIAN        = 'dbg.ads.db.com'
 
 
########################################################################
# MAIN
########################################################################
Get-WfaLogger -Info -Message "##################### PRELIMINARIES #####################"
Get-WfaLogger -Info -Message "Get DB Passwords"
$playground_pass  = Get-WFAUserPassword -pw2get "WFAUSER"
$mysql_pass       = Get-WFAUserPassword -pw2get "MySQL"
 
$hosts = @()
$hosts = $servers.Split(',') | where {$_ -ne ""} | %{$_.Split('.')[0]}
$hosts = $hosts | select -unique
 
$request = @{
   'app_short_name'                = $app_short_name.ToLower();
   'contact'                       = $contact;
   'cost_centre'                   = $cost_centre.split(" ")[0];
   'email_address'                 = $email_address;
   'environment'                   = $environment.ToLower();
   'location'                      = $location.ToLower();
   'nar_id'                        = $nar_id;
   'protocol'                      = $protocol.ToLower();
   'service_level'                 = $service_level.ToLower();
   'service_name'                  = $service_name.ToLower();
   'storage_instance_count'        = $hosts.count;
   'storage_requirement'           = $storage_requirement;
   'hosts'                         = $hosts;
   'ritm'                          = $ritm;
   'correlation_id'                = $change_itask;
   'sys_id'                        = $sys_id;
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
$wfa_job_id = Get-WfaRestParameter -Name jobId
snow_comment -snow_cfg $snow_cfg -comment "Execution started (New Provisioning) - WFA job id : $wfa_job_id"
 
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
Get-WfaLogger -Info -Message $sql
Get-WfaLogger -Info -Message $($result | Out-String)
if ( $result[0] -ne 1 ){
   $fail_msg = 'Unable to get RITM details from budget table'
   Get-WfaLogger -Info -Message $($fail_msg)
   snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
   Throw $($fail_msg)
   exit
}
elseif ( $hosts.Count -gt $result[1].count ){
   $fail_msg = "Hosts are greter than supported under selected budget code. Provide $result[1].count or less hosts under $ritm"
   Get-WfaLogger -Info -Message $($fail_msg)
   snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
   Throw $($fail_msg)
   exit
}
elseif ( ($hosts.Count*$request['storage_requirement']) -gt $result[1].budget ){
   $fail_msg = "Requested storage $($hosts.Count*$request['storage_requirement']) Gb. Available budget for $ritm $($result[1].budget) GB"
   Get-WfaLogger -Info -Message $($fail_msg)
   snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
   Throw $($fail_msg)
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
 
$raw_service_request = @{
  'service'     = 'nas_premium_secops';
  'operation'   = 'create';
  'std_name'    = 'nas_premium';
  'req_details' = @{}
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
   snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
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
   snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
   $placement_solution['success']   = 'FALSE'
   $placement_solution['reason']    = $fail_msg
set_wfa_return_values $placement_solution
   exit
}
 
$placement_solution['service']  = $service_data[$service_name]['service']
$placement_solution['std_name']  = $service_data[$service_name]['std_name']
 
Get-WfaLogger -Info -Message $($snow_cfg | out-string)
Get-WfaLogger -Info -Message $($request | out-string)
 
 
Get-WfaLogger -Info -Message "##################### VSERVERS #####################"
$vservers = vserver `
         -request $request `
         -mysql_pw $mysql_pass
if ( -not $vservers['success'] ){
   $fail_msg = $vservers['reason']
   Get-WfaLogger -Info -Message $fail_msg
   snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
   Throw $fail_msg
}
#Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
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
   snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
   Throw $fail_msg
}
if( $volume['new'] ){
$raw_service_request['req_details']['ontap_volume'] = $volume['ontap_volume']
$raw_service_request['req_details']['ontap_volume_autosize'] = $volume['ontap_volume_autosize']
#Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
}
 
 
Get-WfaLogger -Info -Message "##################### QTREE NAME #####################"
$qtrees = qtree  `
   -request    $request  `
   -volume     $volume['ontap_volume']       `
   -mysql_pw   $mysql_pass
if ( -not $qtrees['success'] ){
   $fail_msg = $qtrees['reason']
   Get-WfaLogger -Info -Message $fail_msg
   snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
   Throw $fail_msg
}
$raw_service_request['req_details']['ontap_qtree'] = $qtrees['ontap_qtree']
#Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
 
Get-WfaLogger -Info -Message "##################### QUOTA RULE #####################"
$quota = quota  `
   -request    $request                      `
   -qtrees     $qtrees['ontap_qtree']       `
   -mysql_pw   $mysql_pass
if ( -not $quota['success'] ){
   $fail_msg = $quota['reason']
   Get-WfaLogger -Info -Message $fail_msg
   snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
   Throw $fail_msg
}
$raw_service_request['req_details']['ontap_quota'] = $quota['ontap_quota']
#Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
 
Get-WfaLogger -Info -Message "##################### NFS EXPORT #####################"
$nfs_export = nfs_export `
      -request  $request                  `
      -qtrees   $qtrees['ontap_qtree']     `
      -mysql_pw      $mysql_pass
if ( -not $nfs_export['success'] ){
      $fail_msg = $nfs_export['reason']
      Get-WfaLogger -Info -Message $fail_msg
      snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
      Throw $fail_msg
   }
$raw_service_request['req_details']['ontap_export_policy']      = $nfs_export['ontap_export_policy']
$raw_service_request['req_details']['ontap_export_policy_rule'] = $nfs_export['ontap_export_policy_rule']
$raw_service_request['req_details']['qtree_export_policy']      = $nfs_export['qtree_export_policy']
#Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10) 
 
Get-WfaLogger -Info -Message "##################### dbRun WFA RESUME #####################"
$dbrun_wfa_resume = dbrun_wfa_resume
if ( -not $dbrun_wfa_resume['success'] ){
      $fail_msg = 'Failed sending wfa resume payload'
      Get-WfaLogger -Info -Message $fail_msg
      snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
      Throw $fail_msg
   }
$raw_service_request['req_details']['dbrun_wfa_resume']      = $dbrun_wfa_resume['dbrun_wfa_resume']
#Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10) 
 
Get-WfaLogger -Info -Message "##################### dbRun EMAIl PARAM #####################"
$dbrun_secops_email = dbrun_secops_email
if ( -not $dbrun_secops_email['success'] ){
      $fail_msg = 'Failed setting dbrun email param'
      Get-WfaLogger -Info -Message $fail_msg
      snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
      Throw $fail_msg
   }
$raw_service_request['req_details']['email']      = $dbrun_secops_email['email']
 
Get-WfaLogger -Info -Message "##################### dbRun SNOW PARAM #####################"
$dbrun_snow_param = servicenow_dbrun -snow_cfg $snow_cfg
if ( -not $dbrun_snow_param['success'] ){
      $fail_msg = 'Failed sending snow dbrun param'
      Get-WfaLogger -Info -Message $fail_msg
      snow_comment -snow_cfg $snow_cfg -comment $($fail_msg)
      Throw $fail_msg
   }
$raw_service_request['req_details']['servicenow']    = $dbrun_snow_param['servicenow']
 
#---------------------------------------------------------------
Get-WfaLogger -Info -Message "##################### CHARGEBACK TABLE #####################"
update_chargeback_table `
   -qtrees $qtrees['ontap_qtree'] `
   -request $request `
   -db_user 'root' `
   -db_pw $mysql_pass
 
Get-WfaLogger -Info -Message "##################### BUDGET TABLE #####################"
update_budget_table `
   -qtrees $qtrees['ontap_qtree'] `
   -request $request `
   -db_user 'root' `
   -db_pw $mysql_pass
 
 
Get-WfaLogger -Info -Message "##################### MOUNT PATHS #####################"
$path = mount_paths `
      -request $request `
      -qtrees $qtrees['ontap_qtree'] `
           
if ( -not $path['success'] ){
   $fail_msg = "Failed createing mount paths"
   Get-WfaLogger -Info -Message $fail_msg
   Throw $fail_msg
}
 
Get-WfaLogger -Info -Message $( $path['mount_paths'])
 
<#$fromaddress = db.global.netapp@list.db.com
$toaddress = jai.waghela@db.com
$body = $($path['mount_paths'])
$Subject = "Secops Allocation Details - $(Get-Date)"
$SMTPServer = "smtphub.uk.mail.db.com"
#Send-MailMessage -From $fromaddress -to $toaddress  -Subject $Subject `
#-Body $body -BodyAsHtml -SmtpServer $SMTPServer #>
 
Get-WfaLogger -Info -Message "##################### RAW SERVICE REQUEST #####################"
Get-WfaLogger -Info -Message $( $raw_service_request | ConvertTo-Json -Depth 10)
 
Get-WfaLogger -Info -Message "##################### SNOW COMMENT #####################"
 
snow_comment -snow_cfg $snow_cfg -comment "Sending payload to dbrun : $(convertto-json $raw_service_request -depth 10 -Compress)"
#snow_comment -snow_cfg $snow_cfg -comment $($path['mount_paths'] -replace "<br>","\n")
 
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
