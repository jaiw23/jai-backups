

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
   [string]$servers
 
)
 
 
function validation() {
   param(
      [parameter(Mandatory=$true)]
      [array]$servers,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
 
   )
 
   Get-wfalogger -info -message "DNS check`n"
 
   $validation = dns  `
      -servers    $servers
   if (-not $validation['success'] ){
      echo $( "Host invalid in DNS: " + $validation['invalid'] )
      $validation
      send_email -validation $validation
      throw $validation['reason']
   }
 
 
   Get-wfalogger -info -message "Checking location"
   $validation = location   `
      -servers    $servers
  
   if (-not $validation['success'] ){
      $validation
      send_email -validation $validation
      throw $validation['reason']
   }
 
   Get-wfalogger -info -message "Checking CMDB"
   $validation = dbib   `
      -servers    $servers  `
      -mysql_pw $mysql_pw
  
   if (-not $validation['success'] ){
      $validation
      send_email -validation $validation
      throw $validation['reason']
   }
 
   #--------------------------------------------------------------------
   # Failing that, return validation
   #--------------------------------------------------------------------
 
   return $validation
 
}
 
 
function dns() {
   param(
      [parameter(Mandatory=$true)]
      [array]$servers
   )
  
   $valid_hosts = @()
   $invalid_hosts = @()
   $success = $False
 
   foreach ($server in $servers){
      $dns = ""
      try{
      $dns = [System.Net.Dns]::GetHostAddresses($server)
      }
      catch{}
      if($dns.Length -gt 0){
        $valid_hosts += $server
        }
      else{$invalid_hosts += $server}
   }
 
   if($invalid_hosts.length -gt 0){$success = $false} else {$success = $true}
 
   if ( $invalid_hosts.length -gt 0 ){
 
      return @{
         'success'         = $False;
         'reason'          = "DNS check failed for followung hosts :<span style='color:red'> $($invalid_hosts -join ',' | Out-String)</span><br><br>No DNS record found for specified hosts";
         'invalid'    = $invalid_hosts;
         'valid'      = $valid_hosts
      }
   }
   else{
      return @{
         'success'         = $True;
         'reason'          = "DNS check passed";
         'invalid'    = $invalid_hosts;
         'valid'      = $valid_hosts
      }
   }
}
 
function location() {
   param(
      [parameter(Mandatory=$true)]
      [array]$servers
   )
  
   $valid_hosts = @()
   $invalid_hosts = @()
   $success = $False
 
   foreach ($server in $servers){
      $temp = $server.Split('.')
      if($location_map["$location"] -contains $temp[-3]){
        $valid_hosts += $server
        }
      else{$invalid_hosts += $server}
   }
 
   if($invalid_hosts.length -gt 0){$success = $false} else {$success = $true}
 
   if ( $invalid_hosts.length -gt 0 ){
 
      return @{
         'success'    = $False;
         'reason'    = "Location check failed for following hosts :<span style='color:red'> $($invalid_hosts -join ',' | Out-String)</span><br><br>Specified hosts cannot be provisioned in '$($request['location'])'";
         'invalid'    = $invalid_hosts;
         'valid'      = $valid_hosts
      }
   }
   else{
      return @{
         'success'    = $True;
         'reason'     = "Location, DNS check passed";
         'invalid'    = $invalid_hosts;
         'valid'      = $valid_hosts
      }
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
 
function dbib() {
   param(
      [parameter(Mandatory=$true)]
      [array]$servers,
      [parameter(Mandatory=$true)]
      [string]$mysql_pw
   )
  
   $valid_hosts = @()
   $invalid_hosts = @()
   $success = $False
 
   foreach ($server in $servers){
 
   $dbib_servers = ""
 
     $server_dbib_sql = "
      SELECT *
      FROM secops.secops_all
      WHERE
         ci_name = '$server'
         AND lifecycle <> 'Removed'
         AND (classification LIKE '%$($request['environment'])%'
         OR classification LIKE '%dr%')
      ;"
     #get-wfalogger -info -message $server_dbib_sql
     $dbib_servers = Invoke-MySqlQuery -query $server_dbib_sql -user root -password $mysql_pw
 
     if ( $dbib_servers[0] -ge 1 ){
      $valid_hosts += $server
      }
     else{$invalid_hosts += $server}
    }
 
   if($invalid_hosts.length -gt 0){$success = $false} else {$success = $true}
 
   if ( $invalid_hosts.length -gt 0 ){
 
      return @{
         'success'         = $False;
         'reason'          = "CMDB check failed for following hosts :<span style='color:red'> $($invalid_hosts -join ',' | Out-String)</span><br><br>Check if hosts are classified as '$($request['environment'])' and lifecyscle status is one of the following'new/build/active'";
         'invalid'    = $invalid_hosts;
         'valid'      = $valid_hosts
      }
   }
   else{
      return @{
         'success'         = $True;
         'reason'          = "Location, DNS, CMDB check passed";
         'invalid'    = $invalid_hosts;
         'valid'      = $valid_hosts
      }
   }
}
 
function send_email(){
 
param(
      [parameter(Mandatory=$true)]
      [hashtable]$validation
   )
 
$email_obj = "D:\email_objects"
 
 
$email_body = '<html xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns:m=http://schemas.microsoft.com/office/2004/12/omml xmlns=http://www.w3.org/TR/REC-html40><head>
<meta http-equiv="Content-Type" content="text/html; charset=us-ascii">
<meta name="Generator" content="Microsoft Word 15 (filtered medium)">
<!--[if !mso]><style>v\:* {behavior:url(#default#VML);}
o\:* {behavior:url(#default#VML);}
w\:* {behavior:url(#default#VML);}
.shape {behavior:url(#default#VML);}
</style><![endif]--><style><!--
/* Font Definitions */
@font-face
                {font-family:"Cambria Math";
                panose-1:2 4 5 3 5 4 6 3 2 4;}
@font-face
                {font-family:Calibri;
                panose-1:2 15 5 2 2 2 4 3 2 4;}
/* Style Definitions */
p.MsoNormal, li.MsoNormal, div.MsoNormal
                {margin:0cm;
                margin-bottom:.0001pt;
                font-size:11.0pt;
                font-family:"Calibri",sans-serif;
                mso-fareast-language:EN-US;}
a:link, span.MsoHyperlink
                {mso-style-priority:99;
                color:#0563C1;
                text-decoration:underline;}
a:visited, span.MsoHyperlinkFollowed
                {mso-style-priority:99;
                color:#954F72;
                text-decoration:underline;}
p.MsoListParagraph, li.MsoListParagraph, div.MsoListParagraph
                {mso-style-priority:34;
                margin-top:0cm;
                margin-right:0cm;
                margin-bottom:0cm;
                margin-left:36.0pt;
                margin-bottom:.0001pt;
                font-size:11.0pt;
                font-family:"Calibri",sans-serif;
                mso-fareast-language:EN-US;}
span.EmailStyle18
                {mso-style-type:personal-compose;
                font-family:"Calibri",sans-serif;
                color:windowtext;}
span.EmailStyle20
                {mso-style-type:personal;
                font-family:"Calibri",sans-serif;
                color:windowtext;}
.MsoChpDefault
                {mso-style-type:export-only;
                font-size:10.0pt;
                font-family:"Calibri",sans-serif;
                mso-fareast-language:EN-US;}
@page WordSection1
                {size:612.0pt 792.0pt;
                margin:72.0pt 72.0pt 72.0pt 72.0pt;}
div.WordSection1
                {page:WordSection1;}
--></style><!--[if gte mso 9]><xml>
<o:shapedefaults v:ext="edit" spidmax="1026" />
</xml><![endif]--><!--[if gte mso 9]><xml>
<o:shapelayout v:ext="edit">
<o:idmap v:ext="edit" data="1" />
</o:shapelayout></xml><![endif]-->
</head>
<body lang="EN-GB" link="#0563C1" vlink="#954F72">
<table class="MsoTableGrid" border="0" cellspacing="0" cellpadding="0" style="border-collapse:collapse;border:none">
<tbody>
<tr style="height:40.85pt">
<td width="708" colspan="2" style="width:575.3pt;padding:0cm 0cm 0cm 0cm;height:40.85pt">
<p class="MsoNormal"><span style="mso-fareast-language:EN-GB"><img width="314" height="58" id="Picture_x0020_4" src=cid:banner.png><o:p></o:p></span></p>
</td>
</tr>
<tr style="height:55.75pt">
<td width="524" style="width:432.35pt;background:#9CC2E5;padding:0cm 0cm 0cm 0cm;height:55.75pt">
<p class="MsoNormal" align="center" style="text-align:center"><span style="font-size:20.0pt;color:white;mso-fareast-language:EN-GB">NetApp Managed Services Notification<o:p></o:p></span></p>
</td>
<td width="184" valign="top" style="width:142.95pt;background:white;padding:0cm 0cm 0cm 0cm;height:55.75pt">
<p class="MsoNormal"><span style="mso-fareast-language:EN-GB"><img width="140" height="76" id="Picture_x0020_8" src=cid:pic.jpg><o:p></o:p></span></p>
</td>
</tr>
<tr>
<td width="524" valign="top" style="width:432.35pt;padding:0cm 0cm 0cm 0cm">
<p class="MsoNormal"><span style="mso-fareast-language:EN-GB"><o:p>&nbsp;</o:p></span></p>
</td>
<td style="border:none;padding:0cm 0cm 0cm 0cm" width="191">
<p class="MsoNormal">&nbsp;</p>
</td>
</tr>
<tr style="height:45.0pt">
<td width="524" valign="top" style="width:432.35pt;padding:0cm 0cm 0cm 0cm;height:45.0pt">
<p class="MsoNormal"><span style="font-size:16.0pt">Secops host validation failed<o:p></o:p></span></p>
<p class="MsoNormal"><span style="font-size:16.0pt"><o:p>&nbsp;</o:p></span></p>
<p class="MsoNormal"><span style="font-size:14.0pt">'+ $validation['reason'] +'<o:p></o:p></span></p>
<p class="MsoNormal"><span style="font-size:16.0pt"><o:p>&nbsp;</o:p></span></p>
<p class="MsoNormal"><span style="font-size:16.0pt"><o:p>&nbsp;</o:p></span></p>
<p class="MsoNormal"><span style="font-size:16.0pt"><o:p>&nbsp;</o:p></span></p>
<p class="MsoNormal"><span style="mso-fareast-language:EN-GB">For any questions or concerns regarding this communication please contact NetApp Managed Services<o:p></o:p></span></p>
</td>
<td style="border:none;padding:0cm 0cm 0cm 0cm" width="191">
<p class="MsoNormal">&nbsp;</p>
</td>
</tr>
</tbody>
</table>
<p class="MsoNormal"><span style="mso-fareast-language:EN-GB"><o:p>&nbsp;</o:p></span></p>
<p class="MsoNormal"><span style="mso-fareast-language:EN-GB">Group email: </span>
<a href=mailto:db.global.netapp@list.db.com><span style="mso-fareast-language:EN-GB">db.global.netapp@list.db.com</span></a><span style="color:#4472C4;mso-fareast-language:EN-GB"><o:p></o:p></span></p>
<p class="MsoNormal"><span style="mso-fareast-language:EN-GB">MyDB page: </span><a href=https://mydb.intranet.db.com/groups/netapp-managed-services><span style="mso-fareast-language:EN-GB">https://mydb.intranet.db.com/groups/netapp-managed-services</span></a><span style="mso-fareast-language:EN-GB"><o:p></o:p></span></p>
<p class="MsoNormal"><span style="mso-fareast-language:EN-GB"><o:p>&nbsp;</o:p></span></p>
<p class="MsoNormal"><span style="mso-fareast-language:EN-GB"><img border="0" width="176" height="32" id="Picture_x0020_1" src=cid:netapp.png alt="netapp 2 - Copy"><o:p></o:p></span></p>
<p class="MsoNormal"><o:p>&nbsp;</o:p></p>
</div>
</font></div>
</body>
</html>
'
 
    try{
                    $smtpServer = "smtphub.uk.mail.db.com" 
                    $msg = new-object Net.Mail.MailMessage 
                    $smtp = new-object Net.Mail.SmtpClient($smtpServer) 
                  
                    $msg.From = db.global.netapp@list.db.com
                    $msg.To.Add(jai.waghela@db.com)
                    $msg.subject = "$wfa_job_id : SECOPS Validation - $($request['correlation_id'])" 
                  
                    $msg.IsBodyHtml = $True 
                  
                    $msg.Body = $email_body
                 
                    $attachment = New-Object System.Net.Mail.Attachment –ArgumentList "$email_obj\banner.png"
                    $attachment.ContentDisposition.Inline = $True 
                    $attachment.ContentDisposition.DispositionType = "Inline" 
                    $attachment.ContentType.MediaType = "image/png" 
                    $attachment.ContentId = 'banner.png' 
                    $msg.Attachments.Add($attachment) 
                  
                    $attachment = New-Object System.Net.Mail.Attachment –ArgumentList "$email_obj\pic.jpg"
                    $attachment.ContentDisposition.Inline = $True 
                    $attachment.ContentDisposition.DispositionType = "Inline" 
                    $attachment.ContentType.MediaType = "image/jpg" 
                    $attachment.ContentId = 'pic.png' 
                    $msg.Attachments.Add($attachment) 
                  
                    $attachment = New-Object System.Net.Mail.Attachment –ArgumentList "$email_obj\netapp.png"
                    $attachment.ContentDisposition.Inline = $True 
                    $attachment.ContentDisposition.DispositionType = "Inline" 
                    $attachment.ContentType.MediaType = "image/png" 
                    $attachment.ContentId = 'netapp.jpg' 
                    $msg.Attachments.Add($attachment) 
                  
                    $smtp.Send($msg)
                    $attachment.Dispose();
                    $msg.Dispose();
 
    }
    catch{
        Get-Wfalogger -Info -Message $($_ | out-string)
    }
 
 
 
}
  
 
#--------- Variables --------------
 
$location_map = @{
'lon' = @('uk','ie');
'fra' = @('it','pl','ru','sa','za','es','se','ch','tr','ua','ae','de');
'sin' = @('au','cn','hk','in','id','jp','my','ph','sg','kr','lk','tw','vn','th');
'nyc' = @('br','us','mx','ca')
}
 
$mysql_pass = Get-WFAUserPassword -pw2get "MySQL"
 
$wfa_job_id = Get-WfaRestParameter -Name jobId
 
$hosts = @()
$hosts = $servers.Split(',') | where {$_ -ne ""}
$hosts = $hosts | select -unique
 
#$loc = "lon"
 
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
}
 
 
$validation = validation -servers $hosts -mysql_pw $mysql_pass
Get-wfalogger -info -message $($validation | Out-String)

