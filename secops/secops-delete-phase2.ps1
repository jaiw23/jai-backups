
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
 
function invoke_wfa_delete_phase_2() {
   param(
      [parameter(Mandatory=$true)]
      [hashtable]$wfa_payload
   )
 
   $cred1 = Get-WfaCredentials -Host $localhost
   $user = $cred1.UserName
   $pass = [System.Net.NetworkCredential]::new("", $cred1.Password).Password
 
   $pair = "$($user):$($pass)"
 
   $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
 
   $basicAuthValue = "Basic $encodedCreds"
 
   $wfa_headers = @{
        "Content-Type"      = "application/json";
        "Accept"            = "application/json";  
        "Authorization"     = $basicAuthValue;
       }
 
    try {
      #$uri = https://$env:COMPUTERNAME.us.db.com/rest/secops_provisioning/jobs/
      $uri = https://localhost/rest/secops_provisioning/jobs/
 
      $response = Invoke-WebRequest -uri $uri -Method POST `
         -body $( ConvertTo-Json $wfa_payload -Depth 10 ) `
         -headers $wfa_headers
 
         Get-Wfalogger -Info -Message $($response | Out-String)
 
      if ($response.StatusCode -ne 201){
         Get-Wfalogger -Info -Message  $("Error scheduling delete phase 2 $($_.Exception | out-String)")
         Throw $("Error scheduling delete phase 2 $($_.Exception | out-String)")
      }
      Get-Wfalogger -Info -Message $($response | Out-String)
      return $response
   }
   catch { Get-Wfalogger -Info -Message $($_ | Out-String)
           Throw $("Error scheduling delete phase 2 $($_.Exception | out-String)")  
   }
}
 
function send_email(){
 
param(
      [parameter(Mandatory=$true)]
      [string]$message
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
<p class="MsoNormal"><span style="font-size:16.0pt">Secops notification for scheduling delete phase 2 - ' + $($change_itask) +'<o:p></o:p></span></p>
<p class="MsoNormal"><span style="font-size:16.0pt"><o:p>&nbsp;</o:p></span></p>
<p class="MsoNormal"><span style="font-size:14.0pt">'+ $message +'<o:p></o:p></span></p>
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
                    $msg.To.Add("$email_address")
        $msg.Cc.Add(jai.waghela@db.com)
                    $msg.subject = "$wfa_job_id : SECOPS Notification - $($change_itask)" 
                  
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
 
 
$request = @{
   'request_type'          = 'delete';
   'app_name'              = $app_short_name.ToLower();
   'email'                 = $email_address;
   'env'                   = $environment.ToLower();
   'loc'                   = $location.ToLower();
   'service_level'         = $service_level.ToLower();
   'service_name'          = $service_name.ToLower();
   'ritm'                  = $ritm;
   'change'                = $change_itask;
   'phase'                 = 2;
   'qtrees'                = $qtrees;
}
 
#---------------------------------------------------------------
# Create array of qtrees from input provided in GUI
#---------------------------------------------------------------
 
$wfa_job_id = Get-WfaRestParameter -Name jobId
 
#---- Add 30 days delay to phase 2
 
$date = (Get-Date).AddDays(30)
#$date = (Get-Date).AddMinutes(6)
$executionTime = (Get-Date $date).ToString('MM/dd/yyyy hh:mm tt')
 
#---
 
#--- Creaate key:value pair as input for WFA rest api
 
$user_input_values = @()
foreach ($h in $request.GetEnumerator()) {
    $user_input_values+=@{"key" = $h.Name;"value" = $h.Value}
}
 
$wfa_payload = @{
        "executionDateAndTime"= $executionTime;
        "comments"= "string";
        "userInputValues"= $user_input_values
        }
 
#Get-Wfalogger -Info -Message $(ConvertTo-Json $wfa_payload -Depth 10)
 
$wfa_response = invoke_wfa_delete_phase_2 -wfa_payload $wfa_payload
Get-Wfalogger -Info -Message $($wfa_response.content | ConvertFrom-Json)
$wfa_phase2_jobid = $(($wfa_response.content | ConvertFrom-Json).jobId)
send_email -message $("Delete plase 2 scheduled for '$executionTime' with WFA job id : $wfa_phase2_jobid")
 
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
snow_comment -snow_cfg $snow_cfg -comment $("Delete plase 2 scheduled for '$executionTime' with WFA job id : $wfa_phase2_jobid")

