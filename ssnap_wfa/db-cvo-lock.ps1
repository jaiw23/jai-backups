
 
param (
  [parameter(Mandatory=$False)]
  [string]$snow_request_id,
 
  [parameter(Mandatory=$False)]
  [int]$timeout_secs,
 
  [parameter(Mandatory=$False)]
  [int]$lock_expire_secs,
 
  [parameter(Mandatory=$False)]
  [int]$lock_polling_interval_secs=1
)
################################################################
# FUNCTIONS
################################################################
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
 
#---------------------------------------------------------------
# This custom WFA command implements a basic locking mechanism
# in order to ensure that only 1 instance of the workflow is
# active at any given time.  It works as follows:
# 1.  The db.lock table in WFA's MySQL database is used
#     essentially as a semophore mechanism.
# 2.  The 'lock_state' of a given workflow instance (determined
#     by WFA Job ID & Service NOW Request Number) determines
#     whether that instance can proceed.  There can be only 1
#     instance whose lock_state == active at any given time
# 3.  First thing a workflow instance does in this command is
#     add itself to the queue waiting for permission to proceed
#     by inserting a row into the db.lock table
# 4.  Next it checks to see if there are any instances
#     whose lock_state == active.
# 5.  If there is already an active workflow instance the current
#     instance will continue to poll the table until:
#     a.  The active instance has reached the lock expiration
#         time
#         OR
#     b.  The instance has timed out trying to acquire the active
#         lock
#         OR
#     c.  The current instance is the longest waiting instance
#         and the active instance has released the lock
#
#     As implied above by 5a, the active lock has an expiration
#     time in order to avoid problems when the workflow fails
#     or for some other reason can't release the lock.
#---------------------------------------------------------------
 
################################################################
# MAIN
################################################################
#---------------------------------------------------------------
# It may be desirable at some point to lock based upon specific
# operations in order to avoid delays for one thing casued by
# something else that will not interfere.  However, for now, I
# think the number of times this will run and the length of run
# time will result in very short and few delays so we will just
# lock everything so only a single workflow instance can execute
# at any given time.
#---------------------------------------------------------------
 
#---------------------------------------------------------------
# Add us to the waiting line
#---------------------------------------------------------------
 
$mysql_pass       = Get-WFAUserPassword -pw2get "MySQL"
 
$start_time = Get-Date -f 'yyyy-MM-dd hh:mm:ss'
$wfa_job_id = Get-WfaRestParameter -Name jobId
$sql = "
    INSERT INTO playground.lock VALUES
    (
      NULL,
      '$snow_request_id',
      '$wfa_job_id',
      'waiting',
      '$start_time',
      '$start_time'
    );
"
 
Get-WfaLogger -Info -Message "Getting our place in line in the lock table"
try{
  $result = Invoke-MySqlQuery -Query $sql -user 'root' -password $mysql_pass
}
catch{
  #---------------------------------------------------------------
  # We check that we were able to obtain the lock in the actual command
  # so here we just bail and that command will pick up the missing lock
  # then exit accordingly
  #---------------------------------------------------------------
  Get-WfaLogger -Info -Message $( "Failed to add ourselves to the lock queue")
  Get-WfaLogger -Info -Message $( $_.Exception.Message )
  exit
}
 
#---------------------------------------------------------------
# Determine our place in the lock queue and whether or not there
# is an active workflow instance holding the lock.
#---------------------------------------------------------------
$sql = "
  SELECT
    snow_request_id   AS 'snow_request_id',
    wfa_job_id        AS 'wfa_job_id',
    lock_state        AS 'lock_state',
    start_time        AS 'start_time',
    last_activity     AS 'last_activity'
  FROM playground.lock
  WHERE 1
    AND lock_state REGEXP 'waiting|active|acquired'
  ORDER BY start_time ASC;
"
 
Get-WfaLogger -Info -Message "Trying to figure out where we are in line"
try{
  $result = Invoke-MySqlQuery -Query $sql -user 'root' -password $mysql_pass
}
catch{
  Get-WfaLogger -Info -Message $( $_.Exception.Message )
  $fail_msg = 'Unable determine our place in line in the lock table'
  Add-WfaWorkflowParameter -Name 'success'  -Value 'FALSE'    -AddAsReturnParameter $True
  Add-WfaWorkflowParameter -Name 'reason'   -Value  $fail_msg -AddAsReturnParameter $True
  Throw $fail_msg
}
 
Get-WfaLogger -Info -Message "Found our place in line"
if ( $result[0] -ge 1 ){
  Get-WfaLogger -Info -Message $( "Queue length is: " + $result[0] )
}
 
#---------------------------------------------------------------
# We now have a list of queue members, are 1st in line?  If we
# are that means there is no instance holding the active lock
#---------------------------------------------------------------
$first_in_line = $false
if ($result[1].snow_request_id -eq $snow_request_id -and $result[1].wfa_job_id -eq $wfa_job_id ){
  Get-WfaLogger -Info -Message "We are first in line"
  $first_in_line = $true
}
 
# Make sure there are at least 2 entries on the off chance
# that something went horribly wrong.
 
#---------------------------------------------------------------
# If we are not 1st in line, check for the following:
# 1.  Are we 2nd in line
#---------------------------------------------------------------
Get-WfaLogger -Info -Message "We are not 1st in line, are we 2nd in line or has 1st in line expired?"
$timeout_at = (Get-Date).AddSeconds($timeout_secs)
$timed_out = $False
while (-not ($first_in_line -or $timed_out) ){
  if ($result[2].snow_request_id -eq $snow_request_id -and $result[2].wfa_job_id -eq $wfa_job_id ){
    $lock_expire_time = [DateTime]::ParseExact($result[1].last_activity, 'MM/dd/yyyy hh:mm:ss', $null).AddSeconds($lock_expire_secs)
    if ( (Get-Date) -gt $lock_expire_time ){
      Get-WfaLogger -Info -Message "Looks like 1st in line ran out of time"
      Get-WfaLogger -Info -Message "Will expire his lock and take the active lock"
      $lock_date = Get-Date -f 'yyyy-MM-dd hh:mm:ss'
      $sql = "
        LOCK TABLES playground.lock WRITE;
        UPDATE playground.lock SET lock_state = 'expired', last_activity = '$lock_date'
        WHERE 1
          AND snow_request_id = '" + $result[1].snow_request_id + "'
          AND wfa_job_id = '" + $result[1].wfa_job_id + "';
        UNLOCK TABLES;
      "
      $result = Invoke-MySqlQuery -Query $sql -user 'root' -password $mysql_pass
      $first_in_line = $True
      Get-WfaLogger -Info -Message "We are now 1st in line"
    }
  }
  else{
  #---------------------------------------------------------------
  # Last time we checked out place in line was >= 3rd.  Let's
  # check to see if other instances finished up and we are now 1st
  #---------------------------------------------------------------
    Get-WfaLogger -Info -Message "We are not 2nd, did 1st finish?"
    $sql = "
      SELECT
        snow_request_id   AS 'snow_request_id',
        wfa_job_id        AS 'wfa_job_id',
        lock_state        AS 'lock_state',
        start_time        AS 'start_time',
        last_activity     AS 'last_activity'
      FROM playground.lock
      WHERE 1
        AND lock_state REGEXP 'waiting|active|acquired'
      ORDER BY start_time ASC;
    "
    $result = Invoke-MySqlQuery -Query $sql -user 'root' -password $mysql_pass
    if ($result[1].snow_request_id -eq $snow_request_id -and $result[1].wfa_job_id -eq $wfa_job_id ){
      $first_in_line = $true
    }
  }
  $timed_out = (Get-Date) -gt $timeout_at
  sleep $lock_polling_interval_secs
}
#---------------------------------------------------------------
# If we are 1st in line, grab the lock, otherwise we are done
# for now so give it up for now.
#---------------------------------------------------------------
$lock_date = Get-Date -f 'yyyy-MM-dd hh:mm:ss'
if ( $first_in_line ){
  $sql = "
    LOCK TABLES playground.lock WRITE;
    UPDATE playground.lock SET lock_state = 'active', last_activity = '$lock_date'
    WHERE 1
      AND snow_request_id = '$snow_request_id'
      AND wfa_job_id = '$wfa_job_id';
    UNLOCK TABLES;
  "
  Get-WfaLogger -Info -Message "Acquiring the lock"
  Get-WfaLogger -Info -Message $( $sql )
}
else{
  $sql = "
    LOCK TABLES playground.lock WRITE;
    UPDATE playground.lock SET lock_state = 'timedout', last_activity = '$lock_date'
    WHERE 1
      AND snow_request_id = '$snow_request_id'
      AND wfa_job_id = '$wfa_job_id';
    UNLOCK TABLES;
  "
  Get-WfaLogger -Info -Message "Timed out waiting to acquire the lock"
  Get-WfaLogger -Info -Message $( $sql )
}
$result = Invoke-MySqlQuery -Query $sql -user 'root' -password $mysql_pass

