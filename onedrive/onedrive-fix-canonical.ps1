
param (
 
  [parameter(Mandatory=$True)]
  [string]$ticket,
 
  [parameter(Mandatory=$True)]
  [string]$region,
 
  [parameter(Mandatory=$True)]
  [string]$setting,
 
  [parameter(Mandatory=$True)]
  [string]$date,
 
  [parameter(Mandatory=$True)]
  [string]$to_address,
 
  [parameter(Mandatory=$True)]
  [string]$from_address,
 
  [parameter(Mandatory=$True)]
  [string]$cc_address
 
)
 
############# Variables #############
$jobid =  $(Get-WfaRestParameter "jobId")
$dfs_path = \\dbg.ads.db.com\lon-gto\NetApp\WFA_Logs\onedrive_migrations
if(-Not(Test-Path  "$dfs_path\logs")){
 
    Get-Wfalogger -Info -message "$($dfs_path)\logs directory not present"
    Throw
}
if(-Not(Test-Path  "$dfs_path\archive")){
 
    Get-Wfalogger -Info -message "$($dfs_path)\archive directory not present"
    Throw
}
$userpaths = "$dfs_path\$region-$date-$setting.csv"
if(-Not(Test-Path  "$userpaths")){
 
    Get-Wfalogger -Info -message "$userpaths not present"
    Throw
}
$log_file_name = "$dfs_path\$ticket-$date-$setting-$jobid.txt"
$mgmt_host = "mgmt_host"
$cred = Get-WfaCredentials -Host $mgmt_host
$cred1 = Get-WfaCredentials -Host $mgmt_host
$host_map = @{
 
       #'lon' = 'lonaswfautb1.uk.db.com';
       'lon' = 'loninspmigb3.uk.db.com'; #OneDrive team's server
       'fra' = 'frainspmigb5.de.db.com'; #OneDrive team's server
       #'fra' = 'fraasstorxb1.de.db.com';
       'sin' = 'sininaiqump1.sg.db.com';
       'nyc' = 'nycasspmigp1.us.db.com';
       'ind' = 'muminfsp0001.in.db.com';
   }
$o = New-PSSessionOption -OutputBufferingMode Drop -IdleTimeout 2147483647
Invoke-Command -ComputerName $host_map[$region.ToLower()] -ScriptBlock { Register-PSSessionConfiguration -Name IPSWITCH -RunAsCredential $using:cred1 } -ErrorAction SilentlyContinue | out-null
 
############# Script Block #############
$sb = {
#Path to user path upload document from RITM
#Set Log File variable to WFA Job ID
$log_file_name = $using:log_file_name
$userpaths = $using:userpaths
$destination_logs = "$using:dfs_path\logs\$using:ticket-$using:region-$using:date-$using:setting-$using:jobid-logs.txt"
$destination_archive = "$using:dfs_path\archive\$using:ticket-$using:region-$using:date-$using:setting-$using:jobid.csv"
$error_count = 0
$email_obj = "$using:dfs_path\email_objects"
$send_email = $true
 
function log2file{
    [CmdletBinding()]
    param(
       [parameter(Mandatory=$true)]
       [string]$message,
       [parameter(Mandatory=$true)]
       [string]$file_name,
       [switch]$log2console
    )
    if ( $log2console ){
       #Write-Host -BackgroundColor Yellow -ForegroundColor Black $message
       Write-Output $message
    }
    $message = (Get-Date -Format "[dd MMM yyyy HH:mm:ss] ").ToString() + ${message}
    Add-Content -Path $file_name -Value $message
}
 
#ACL group to assign access and permissions
$Principal = "DBG\IA-OTHER-ODFB-MIGRATION"
$Permission = "ReadAndExecute"
$content = @()
 
log2file -log2console -file_name $log_file_name -message "$using:setting"
 
$content = Get-Content $userpaths | where {$_ -ne ""}
foreach ($userpath in $content)
    {
    $path = $userpath.split(",")[0]
    $ID = $userpath.split(",")[1]
    log2file -log2console -file_name $log_file_name -message $("Setting " + $using:setting + " for path " + $path + " ID: " +$ID )
    try{
        icacls $path /inheritancelevel:d
        icacls $path /c /q /reset
    }
    catch{
        log2file -log2console -file_name $log_file_name -message "ERROR: Icacls reset failed : $($path) $($Error[0])"
        $error_count += 1
    }
   
    try {
        $Acl = Get-Acl $path
        $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $ID,
        "Modify",      # [System.Security.AccessControl.FileSystemRights]
        "ContainerInherit, ObjectInherit", # [System.Security.AccessControl.InheritanceFlags]
        "none",      # [System.Security.AccessControl.PropagationFlags]
        "Allow"      # [System.Security.AccessControl.AccessControlType]
         )))
        (Get-Item $path).SetAccessControl($Acl)
        log2file -log2console -file_name $log_file_name -message $("Completed setting " + $using:setting + " for path " + $path + " ID: " +$ID )
        }
    catch{
        log2file -log2console -file_name $log_file_name -message "ERROR: $Principal : $($path) $($Error[0])"
        $error_count += 1
    }
    }
    try{
        log2file -log2console -file_name $log_file_name -message "$using:setting Automation complete"
        Move-Item -Path $userpaths -Destination $destination_archive -Force
        Move-Item -Path $log_file_name -Destination $destination_logs -Force
    }
    catch{
        log2file -log2console -file_name $log_file_name -message "Error moving files : $($Error[0])"
    }
 
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
<p class="MsoNormal"><span style="font-size:16.0pt">'+ $using:ticket +' for apply setting ' + $using:setting +' is complete<o:p></o:p></span></p>
<p class="MsoNormal"><span style="font-size:16.0pt"><o:p>&nbsp;</o:p></span></p>
<p class="MsoNormal"><span style="font-size:14.0pt">Errors - '+ $error_count +'<o:p></o:p></span></p>
<p class="MsoNormal"><span style="font-size:16.0pt"><o:p>&nbsp;</o:p></span></p>
<p class="MsoNormal"><span style="font-size:14.0pt">Logs attached for reference<o:p></o:p></span></p>
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
        if($send_email)
        { 
                    $smtpServer = "smtphub.uk.mail.db.com" 
                    $msg = new-object Net.Mail.MailMessage 
                    $smtp = new-object Net.Mail.SmtpClient($smtpServer) 
                  
                    $msg.From = $using:from_address 
                    $msg.To.Add($using:to_address)
        $msg.CC.Add($using:cc_address)
                    $msg.subject = "OneDrive Email $using:setting - $using:ticket" 
                  
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
                  
                    $attachment1 = New-Object System.Net.Mail.Attachment –ArgumentList $destination_logs
                    $msg.Attachments.Add($attachment1)
                 
                    $smtp.Send($msg)
                    $attachment.Dispose();
                    $msg.Dispose();
                 
                    } 
 
    }
    catch{
        log2file -log2console -file_name $destination_logs -message "Error sending email : $($Error[0])"
    }
}
get-wfalogger -info -message "Script execution started on $($host_map[$region.ToLower()])"
$out = Invoke-Command -ComputerName $host_map[$region.ToLower()] -SessionName $jobid -SessionOption $o -ScriptBlock $sb -Credential $(Get-WfaCredentials -Host $mgmt_host) -ConfigurationName IPSWITCH -InDisconnectedSession
get-wfalogger -info -message $($out | out-string)
get-wfalogger -info -message "Logs will be stored in $dfs_path\logs once script completes on remote server"
