import requests
import urllib3
import json
import time
import argparse
import sys
import json
from datetime import datetime, date,  timedelta
from time import sleep
import yaml
import re
import pdb
import subprocess
class wfa_server(object):
 
   def get_credentials(self, wfa_cfg):
      runner = [wfa_cfg['sdklocation'], 'GetPassword', '-p', 'AppDescs.AppID='+wfa_cfg['appid'], '-p']
      runner = runner + ["Query='Safe="+wfa_cfg['safe']+";Folder="+wfa_cfg['folder']+";Object="+wfa_cfg['object']+"'",'-o','Password']
      try:
         output = subprocess.Popen(runner)
      except Exception as e:
         raise(Exception(str(e)))
      else:
         if output.stderr =="":
            self.wfa_cfg['pw'] = output.stdout
         else:
            raise(Exception(str(output.stderr)))
 
   def __init__(self, wf_name, ip, wfa_cfg, request, timeout_secs=300):
 
      self.uuid   = None
 
      self.wf_name      = wf_name
      self.ip           = ip
      self.wfa_cfg  = wfa_cfg
      #self.get_credentials(self.wfa_cfg)
      self.snow_request = request
      self.wfa_payload  = dict()
 
      self.raw_placement_solution = dict()
      self.placement_solution     = dict()
 
      self.timeout_secs = timeout_secs
 
   def start_wf(self):
      if not self.__snow2wfa():
         self.success   = False
         self.reason    = "Unsupported request"
         return
 
      self.__get_wf_uuid()
      wfa_inputs  = []
      for user_input in self.wfa_payload.items():
         wfa_inputs.append( { 'key': user_input[0], 'value': user_input[1] } )
      ui_payload = {
         'userInputValues': wfa_inputs
      }
      result = requests.post('https://' + self.ip + '/rest/workflows/' + self.uuid  + '/jobs/',
         auth=(self.wfa_cfg['user'],self.wfa_cfg['pw']),
         verify=False,
         headers = {'Accept': 'application/json'},
         json=ui_payload )
      if result.status_code == 201:
         self.success = True
         self.job_id = result.json()['jobId']
      else:
         self.success = False
         self.reason  = result.reason
 
   def wait4_wf(self):
      job_status_regex  = re.compile('COMPLETED|FAILED|CANCELED|PAUSED')
      status = requests.get('https://' + self.ip + '/rest/workflows/' + self.uuid + '/jobs/' + str(self.job_id),
         auth=(self.wfa_cfg['user'],self.wfa_cfg['pw']),
         verify=False,
         headers = {'Accept': 'application/json'} )
      start_time        = datetime.now()
      timeout           = timedelta(seconds=self.timeout_secs)
      job_status        = status.json()['jobStatus']
      timedout          = False
      while not job_status_regex.search(job_status['jobStatus']) and not timedout:
         time.sleep(5)
         status = requests.get('https://' + self.ip + '/rest/workflows/' + self.uuid + '/jobs/' + str(self.job_id),
            auth=(self.wfa_cfg['user'],self.wfa_cfg['pw']),
            verify=False,
            headers = {'Accept': 'application/json'} )
         job_status = status.json()['jobStatus']
         timedout = (datetime.now() - start_time) > timeout
 
      if job_status['jobStatus'].upper() == 'COMPLETED':
         raw_ret_vals = job_status['returnParameters']
         for raw_ret_val in raw_ret_vals:
            if raw_ret_val['key'].lower() == 'success':
               if raw_ret_val['value'].lower() == 'true':
                  self.success = True
                  continue
               else:
                  self.success = False
                  continue
            elif raw_ret_val['key'] == 'reason':
               self.reason = raw_ret_val['value']
               continue
            self.placement_solution.update( {raw_ret_val['key']: raw_ret_val['value'] } )
      elif job_status['jobStatus'].upper() == 'CANCELED':
         self.success = False
         self.reason = "The WFA job was cancelled"
      elif job_status['jobStatus'].upper() == 'PAUSED':
         self.success = False
         self.reason = "The WFA job has been paused"
      elif job_status['jobStatus'].upper() == 'FAILED':
         self.success = False
         self.reason = "The WFA job has failed with error message: " + job_status['jobStatus']['errorMessage']
      elif timedout:
         self.success = False
         self.reason = "Timed out waiting for WFA to execute workflow"
 
   def get_placement_solution(self):
     return self.placement_solution
 
   def __get_wf_uuid(self):
      wf = requests.get('https://' + self.ip + '/rest/workflows?name=' + self.wf_name,
         auth=(self.wfa_cfg['user'],self.wfa_cfg['pw']),
         verify=False,
         headers = {'Accept': 'application/json'} )
      self.uuid   = wf.json()[0]['uuid']
 
   def __snow2wfa(self):
      self.wfa_payload = {        
         "RequestID":      self.snow_request['request_item']['number'],
         "Service":        self.snow_request['service']
      }
      if self.snow_request['service'].lower() == 'nas automation':
         self.__nas_automation()
         return True
      else:
         return False
 
   def __nas_automation(self):
      self.wfa_payload.update(
         {    
            "RequestType":                     self.snow_request['variables']['request_type'],
            "ServiceLevel":                    self.snow_request['variables']['service_level'],
            "ServiceName":                     self.snow_request['variables']['service_name'],
            "CorrelationId":                   self.snow_request['number'],
            "Sys_Id":                          self.snow_request['sys_id'],
         }
      )
 
      if self.snow_request['variables']['request_type'].lower() == 'new':
         #----------------------------------------------------------------
         # These are all mandatory fields
         #----------------------------------------------------------------
         self.wfa_payload.update(
            {             
               "Contact":                         self.snow_request['variables']['group_email'],
               "CostCentre":                      self.snow_request['variables']['cost_centre'],
               "EmailAddress":                    self.snow_request['variables']['group_email'],
               "Environment":                     self.snow_request['variables']['environment'],
               "Location":                        self.snow_request['variables']['location'],                            
               "Protocol":                        self.snow_request['variables']['protocol'],              
               "StorageInstanceCount":            self.snow_request['variables']['storage_instances'],
               "StorageRequirement":              self.snow_request['variables']['storage_requirement']
            }
         )
         #----------------------------------------------------------------
         # Add the optional stuff
         #----------------------------------------------------------------
         if "smb_acl_group_contact" in self.snow_request['variables']: self.wfa_payload.update({"SmbAclGroupContact":self.snow_request['variables']['smb_acl_group_contact']})
         if "smb_acl_group_delegate" in self.snow_request['variables']: self.wfa_payload.update({"SmbAclGroupDelegate":self.snow_request['variables']['smb_acl_group_delegate']})
         if "smb_acl_group_approver_1" in self.snow_request['variables']: self.wfa_payload.update({"SmbAclGroupApprover1":self.snow_request['variables']['smb_acl_group_approver_1']})
         if "smb_acl_group_approver_2" in self.snow_request['variables']: self.wfa_payload.update({"SmbAclGroupApprover2":self.snow_request['variables']['smb_acl_group_approver_2']})
         if "dfs_root_path" in self.snow_request['variables']: self.wfa_payload.update({"DfsRootPath":self.snow_request['variables']['dfs_root_path']})
         if "dfs_path_1" in self.snow_request['variables']: self.wfa_payload.update({"DfsPath1":self.snow_request['variables']['dfs_path_1']})
         if "dfs_path_2" in self.snow_request['variables']: self.wfa_payload.update({"DfsPath2":self.snow_request['variables']['dfs_path_2']})
         if "dfs_new_folder" in self.snow_request['variables']: self.wfa_payload.update({"DfsNewFolder":self.snow_request['variables']['dfs_new_folder']})
         if "dfs_folder" in self.snow_request['variables']: self.wfa_payload.update({"DfsFolder":self.snow_request['variables']['dfs_folder']})
         if "nis_domain" in self.snow_request['variables']: self.wfa_payload.update({"NISDomain":self.snow_request['variables']['nis_domain']})
         if "netgroup_rw" in self.snow_request['variables']: self.wfa_payload.update({"Netgroup_RW":self.snow_request['variables']['netgroup_rw']})
         if "netgroup_rw" in self.snow_request['variables']: self.wfa_payload.update({"Netgroup_RW":self.snow_request['variables']['netgroup_rw']})
         if "application_instance" in self.snow_request['variables']: self.wfa_payload.update({"AppShortName":self.snow_request['variables']['application_instance']})
         if "nar_id" in self.snow_request['variables']: self.wfa_payload.update({"NARID":self.snow_request['variables']['nar_id']})
         if "netgroup_ro" in self.snow_request['variables']:
            self.wfa_payload.update(
               {
                  "Netgroup_RO":          self.snow_request['variables']['netgroup_ro']
               }
            )
 
         #----------------------------------------------------------------
         # Add the CVO related parameters passed from SNOW
         #----------------------------------------------------------------
         if self.snow_request['variables']['service_name'].lower().startswith('cvo'):
            self.wfa_payload.update(
            {             
               "LandingZone":                     self.snow_request['variables']['landing_zone'],
               "Platform":                        self.snow_request['variables']['platform'],
               "EKM":                             self.snow_request['variables']['ekm_required']
            }
         )
              
 
      elif self.snow_request['variables']['request_type'].lower() == 'increase / reduce':
         self.wfa_payload.update(
            {
               "StoragePath":          self.snow_request['variables']['existing_storage_path'],
               "StorageRequirement":   self.snow_request['variables']['storage_requirement']
            }
         )
      elif self.snow_request['variables']['request_type'].lower() == 'delete':
         self.wfa_payload.update(
            {
               "StoragePath":          self.snow_request['variables']['existing_storage_path'],
               "Protocol":             self.snow_request['variables']['protocol'],
               "Phase":                self.snow_request['phase']
            }
         )
 
class dbrun(object):
   def __init__(self, db_cfg):
      self.cfg = db_cfg
      self.token = ''
      self.reason = 'Error While Executing DB Run'
      self.success   = False
      self.headers = {
         "accept":      "application/json",
      }
  
   def get_auth_token(self):
      try:
         url = self.cfg['base_url'] + '/auth/system_tokens/'+self.cfg['nar_id']+'/'+self.cfg['env']
         response = requests.get(url=url, verify=False)
         if response.status_code == 200:
            response_dict = json.loads(response.text)
            self.token = response_dict[0]['token']
            expiry = response_dict[0]['expires']
            if expiry <=self.cfg['grace_period']:
               url = self.cfg['base_url'] + '/auth/refresh_system_tokens'
               self.headers.update({ "X-Auth-Token": self.token, "content-type": "application/json"})
               data = {
                  "env":         self.cfg['env'],
                  "nar":         self.cfg['nar_id'],
               }
               data = json.dumps(data)
               response = requests.post(url=url,  headers=self.headers, verify=False, data=data)
               if response.status_code != 200:
                  raise(Exception(response.json()))
         else:
            raise(Exception(response.json()))
      except Exception as e:
         raise(Exception(str(e)))
 
    
#--------------------------------------------------------------------
# Function: wfa()
# This function takes the raw input from WFA. and then translate the input
# in dictionary and return.
#--------------------------------------------------------------------
   def wfa(self, vars, data_var_regex = "raw_req_[0-9]+", match_str = "__res_type=[a-z0-9]+"):
      try:
         var_names = []
         for var_name in vars.keys():
            if re.match(data_var_regex, var_name):
               var_names.append(var_name)
         var_names.sort()
         raw_service_request = dict(req_details=dict())
         for var_name in var_names:
            if re.match(match_str, vars[var_name]):
               data = vars[var_name].split(';')
               res_type = data[0].split('=')[1]
               if not res_type in raw_service_request['req_details']:
                  raw_service_request['req_details'][res_type] = []
               tmp = dict(attr.split('=') for attr in data[1].split(','))
               raw_service_request['req_details'][res_type].append(tmp)
            else:
               attr = vars[var_name].split(';')[1].split('=')[0]
               val = vars[var_name].split(';')[1].split('=')[1]
               raw_service_request[attr] = val
         return raw_service_request
      except Exception as e:
         raise(Exception(str(e)))
 
#--------------------------------------------------------------------
# Function: post_request()
# This function is used to make a post call to the DBRun.
# To pass the extra-vars to ansible we can use the variable "params".
# We need to specify the name, type and value for that extra var variable.
#--------------------------------------------------------------------     
   def post_request(self, db_run_params, snow_request):
      try:
         url = self.cfg['base_url'] + '/executor/executions'
         data = {
            "env" :          self.cfg['env'],
            "action":        self.cfg['action'],
            "component":     self.cfg['component'],
            "continue_with_allowed_servers":      self.cfg['continue_with_allowed_servers'],
            "narId":         self.cfg['nar_id'],
            "impacted_nar":  self.cfg['nar_id'],
            "description":   self.cfg['description'],
            "queued":        self.cfg['queued'],
            "user":          self.cfg['user'],
            "force_continue":self.cfg['force_continue'],
            "instance":      self.cfg['instance'],
            "param":         [{"name":"raw_service_request", "type":"dictionary", "value":db_run_params}],
            "snow_id":       "",
            "text_output":   self.cfg['text_output'],
         }
         data = json.dumps(data)
         self.headers.update({ "X-Auth-Token": self.token, "content-type": "application/json"})
         response = requests.post(url=url,  headers=self.headers, verify=False, data=data)  
         if response.status_code == 200:
            response_dict = json.loads(response.text)
            self.success = True
            return response_dict['audit_id']
         else:
            raise(Exception(response.json()))
      except Exception as e:
         raise(Exception(str(e)))
 
class snow(object):
 
   def __init__(self, snow_cfg):
      self.api = snow_cfg
     
      self.proxies = {
        'https':  self.api['proxy']
      }
      self.snow_general_headers = {
         "Content-Type":      "application/json",
         "Accept":            "application/json",  
         "Authorization":     "Bearer "
      }
      self.snow_auth_headers = {
          "Content-Type":"application/x-www-form-urlencoded",
      }
#--------------------------------------------------------------------
# Function: get_auth_token()
# This fuction fetches the refresh token and access token from service Now.
# The refresh token will be stored in cfg file, which will be used everytime to fetch access token.
# if refresh token is not available in that case, username and password stored in config will be used.
# Each refresh Token is valid for some specific days, So every time we fetch a new refresh token, we will
# update the same in cfg.
#--------------------------------------------------------------------
 
   def get_auth_token(self):
      try:
         payload = "client_id="+ self.api['client_id'] +"&client_secret="+ self.api['client_secret']
         set_days = int(self.api['days'])
         if self.api['refresh_token'] != "" and self.api['refresh_token_timestamp'] + timedelta(days=set_days) >= datetime.today():
            payload = payload + "&grant_type=refresh_token&refresh_token="+self.api['refresh_token']
         else:
            payload = payload + "&grant_type=password&username="+ self.api['user'] +"&password="+self.api['pw']
         url = self.api['base_url'] + '/oauth_token.do'
         response = requests.post(url, data=payload,  headers=self.snow_auth_headers, proxies = self.proxies)
 
         if response.status_code == 200:
            response_dict = json.loads(response.text)
            self.snow_general_headers['Authorization'] = self.snow_general_headers['Authorization'] + response_dict["access_token"]
            if self.api['refresh_token'] == "" or self.api['refresh_token'] != response_dict["refresh_token"]: 
               with open('snow-interface.cfg', 'r') as yamlfile:
                  cur_yaml = yaml.safe_load(yamlfile)         
                  cur_yaml['snow']['refresh_token'] = response_dict["refresh_token"]
                  cur_yaml['snow']['refresh_token_timestamp'] = datetime.today()
               with open('snow-interface.cfg', 'w') as yamlfile:
                  yaml.safe_dump(cur_yaml, yamlfile)
         else:
            raise(Exception(response.json()))
      except Exception as e:
         raise(Exception(str(e)))
 
#--------------------------------------------------------------------
# Function: add_snow_worknotes()
# This fuction used to add the worknotes to serviceNow ticket
#--------------------------------------------------------------------
 
   def add_snow_worknotes(self, comment):
      try:  
         url = self.api['base_url'] + '/api/global/v1/srm_task_api/task/update_actions'
 
         data = {
            'action': "comment",
            'correlation_id': self.api['correlation_id'] ,
            'sys_id': self.api['sys_id'],
            'work_notes': comment,
            }
         response = requests.post(url,headers=self.snow_general_headers,json=data, proxies = self.proxies)
         if response.status_code != 200:
            raise(Exception(response.json()))
      except Exception as e:
         raise(Exception(str(e)))
 
#--------------------------------------------------------------------
# Function: set_req_status()
# This fuction is used to update the status of serviceNow ticket and add comments
#--------------------------------------------------------------------
 
   def set_req_status(self, status, cancel_reason="",comments=""):
      try:
         url = self.api['base_url'] + '/api/global/v1/srm_task_api/task/update_actions'
        
         data = {
            'action': status,
            'correlation_id': self.api['correlation_id'] ,
            'sys_id': self.api['sys_id'],
            }
 
         if cancel_reason != "":
            data['u_cancellation_reason'] = cancel_reason
 
         if comments != "":
            data['comments'] = comments
 
         response = requests.post(url, headers=self.snow_general_headers, json=data, proxies = self.proxies)
     
         if response.status_code != 200:
            raise(Exception(response.json()))
      except Exception as e:
         raise(Exception(str(e)))
 
   def get_req(self, snow_req_number):
      response = requests.get(self.api['base_url'] + '/api/now/table/sc_request?sysparm_query=number%3D' + snow_req_number + '&sysparm_display_value=true',
         headers=self.snow_general_headers, proxies = self.proxies
      )
      if response.status_code == 200:
         return response.json()
      else:
         raise(Exception(response.json()))
 
   #------- Adding CVO related dependency --------#
 
   def tag_correlation_id(self):
      try:  
         url = self.api['base_correlation_url'] + '/api/global/v1/srm_task_api/task/update_actions'
         data = {
            'action': "correlation",
            'correlation_id': self.api['correlation_id'] ,
            'sys_id': self.api['sys_id'],
            }
         response = requests.post(url,headers=self.snow_general_headers,json=data, proxies = self.proxies)
         if response.status_code != 200:
            raise(Exception(response.json()))
      except Exception as e:
         #raise(Exception(str(e)))
         pass
 
##########################################################################
# MAIN
##########################################################################
#-------------------------------------------------------------------------
# ServiceNOW JSON Format
#  number             - Service Catalog Task Number
#  short_description  - e.g. "NAS Provisioning"
#  service            - "NAS Automation"
#  service_level      - "NAS Premium, NAS Standard, NAS Fabric"
#  opened_at          - yyyy-mm-dd hh24:mi:ss
#  status             -  success/failure
#  request_item:
#     cat_item:               - values = "NAS Provisioning"
#     u_requested_for:
#        name
#        user_name
#        email
#  variables:
#     --------------- Always present ------------
#     service_name            - values = "NAS Premium|Fabric Premium"
#     request_type            - values = "New|Increase/Decrease|Delete"
#     cost_centre
#     application_instance
#     nar_id
#     environment
#     location
#     owner
#     group_email
#     Protocol                - values = "NFS|SMB"
#     --------------- Request Specific ------------
#     storage_requirement     - request_type = New|Increase/Reduce
#     storage_instances       - request_type = New|Increase/Reduce && service_name = "NAS Premium"
#     netgroup_rw             - request_type = New && service_name = "NAS Premium"
#     netgroup_ro             - request_type = New && service_name = "NAS Premium"
#     existing_storage_path   - request_type = Delete
#-------------------------------------------------------------------------
 
nfs_snow_req_str  = '                                    \
   {                                                \
      "number":            "TASK0006557792",           \
      "short_description": "NAS Automation",      \
      "service":           "NAS Automation",    \
      "opened_at":         "2020-10-25 08:00:00",   \
      "sys_id":            "b2f77353dbdca01443239616f3961926",                \
      "url":               https://dbunitydev1.service-now.com,          \
      "request_item": {                             \
         "cat_item":       "NAS Premium",      \
         "number":         "RITM6791273",           \
         "u_requested_for": {                       \
            "email": jai.waghela@db.com,           \
            "name":  "jai"                         \
         }                                         \
      },                                            \
      "variables": {                                \
         "service_name":         "NAS Premium",     \
         "request_type":         "New",             \
         "cost_centre":          "12345",           \
         "application_instance": "app_short_name",  \
         "nar_id":               "12345-1",         \
         "environment":          "DEV",             \
         "location":             "LON",             \
         "group_email":          jai.waghela@db.com, \
         "protocol":             "NFS",             \
         "storage_requirement":  1,                 \
         "storage_instances":    1,                 \
         "nis_domain":           "uk.db.com",          \
         "netgroup_rw":          "rw",              \
         "netgroup_ro":          "ro",                \
         "number":               "TASK0006557792",     \
         "sys_id":               "b2f77353dbdca01443239616f3961926"           \
         "service_level":     "NAS Premium",  \
      }                                             \
   }'
 
smb_snow_req_str  = '                                    \
   {                                                \
      "number":            "TASK0066047",           \
      "short_description": "NAS Provisioning",      \
      "opened_at":         "2020-10-25 08:00:00",   \
      "sys_id":            "abc...",                \
      "url":               "https:// ...",          \
      "request_item": {                             \
         "cat_item":       "NAS Premium",      \
         "number":         "RITM6791273",           \
         "u_requested_for": {                       \
            "email": jai.waghela@db.com,           \
            "name":  "jai"                         \
         }                                         \
      },                                            \
      "variables": {                                \
         "service_name":         "NAS Premium",     \
         "request_type":         "New",             \
         "cost_centre":          "12345",           \
         "application_instance": "app_short_name",  \
         "nar_id":               "12345-1",         \
         "environment":          "DEV",             \
         "location":             "HWV",             \
         "group_email":          jai.waghela@db.com, \
         "Protocol":             "SMB",             \
         "storage_requirement":  1,                 \
         "storage_instances":    1,                 \
         "nis_domain":           "db_run",          \
         "netgroup_rw":          "rw",              \
         "netgroup_ro":          "ro"              \
      }                                             \
   }'
 
#--------------------------------------------------------------------
# FUNCTION: set_test_comment()
# this method is created just to test the python script commenting to serviceNow.
# So that ServiceNow can read the comments from workNotes and trigger remediation or backup
# tasks. This function will only execute when we pass skip DBrun as argument while executing file.
#--------------------------------------------------------------------
 
def set_test_comment(snow_request, snow_srvr):
   if snow_request['variables']['request_type'].lower() == 'new':
      if snow_request['variables']['environment'].lower() == 'prd':
         snow_srvr.add_snow_worknotes("BACKUP REQUIRED: " + """Please Create a backup for Following Storage -
         \n Volume: DUMMY NAME \n Qtree: DUMMY NAME \n Vsrver: DUMMY NAME""")
      comment =  """Your NAS Premium request is now fully complete and your storage is available for use
      \nMount Path: loninengclsp01svm2:/loninengclsp01svm2_data_001_nfs/premium_dev_00001\nRead/Write Access: s-db-uat-pwsao-db-nfs
      \nYou will need to add your host to the above netgroup to access the storage."""
   elif snow_request['variables']['request_type'].lower() == 'increase / reduce':
      comment = """Your NAS Premium request is now fully complete and your storage has been modified
      \nMount Path: loninengclsp01svm2:/loninengclsp01svm2_data_001_nfs/premium_dev_00001
      \nYou will need to remount the storage from your host for the modification to become active."""
   elif snow_request['variables']['request_type'].lower() == 'delete':
      comment = """Your NAS Premium request is now fully complete and access has been removed to your storage as requested
      \nMount Path: loninengclsp01svm2:/loninengclsp01svm2_data_001_nfs/premium_dev_00001
      \nThe storage will be completely deleted in 14 days."""
 
   if snow_request['variables']['request_type'].lower() == 'delete':
      if 'phase' in snow_request and snow_request['phase'] == '1':
         snow_srvr.add_snow_worknotes("DELETION REQUIRED: " + """Please Delete the Following Storage -
         \n Volume: DUMMY NAME
         \n Qtree: DUMMY NAME \n Vsrver: DUMMY NAME""")
         snow_srvr.set_req_status("comment", comments = comment)
      else:
         snow_srvr.set_req_status("completed")
   else:
      snow_srvr.set_req_status("completed", comments = comment)
 
#--------------------------------------------------------------------
# FUNCTION: get_sysid()
# This method is created to fetch sysid of serviceNow tickets.
# In ideal scenario we would not need it because ServiceNow will send us sysid along with its payload
# But in case of CVO its a special case for which we might mbe running automation without ServiceNow.
#--------------------------------------------------------------------
 
def get_sysid(snow_request):
    snow_sysid_cfg = {
    "base_url" : f"{cfg['snow']['table_api_url']}/sc_task?sysparm_query=number={snow_request['number']}",
    "task" : snow_request['number'],
    "proxies" : {"https": cfg['snow']['proxy']},
    "headers" : {
                            "Content-Type" : "application/json",
                            "Authorization" : "Basic bmFzX2F1dG9tYXRpb25faW50ZXJmYWNlOk5mMkoxeE1N"}
        }
    try:
        response = requests.get(snow_sysid_cfg['base_url'],
            headers=snow_sysid_cfg['headers'], proxies = snow_sysid_cfg['proxies']
        )
        if response.status_code == 200:
            out = json.loads(response.text)        
            return out['result'][0]['sys_id']
        else:
            raise(Exception(response.json()))
   
    except Exception as e:
            raise(Exception(str(e)))
 
 
snow_req_str = nfs_snow_req_str
urllib3.disable_warnings (urllib3.exceptions.InsecureRequestWarning)
 
parser = argparse.ArgumentParser()
parser.add_argument('-c', '--cfg-file',      required=False,   default='snow-interface.cfg')
parser.add_argument('-r', '--snow-req',      required=False,   default=snow_req_str)
parser.add_argument('-S', '--skip-dbrun',    required=False,   action='store_true')
parser.add_argument('-s', '--skip-snow',     required=False,   action='store_true')
parser.add_argument('-w', '--dump-wfa',      required=False,   action='store_true')
parser.add_argument(      '--dump-stdout',   required=False,   action='store_true')
parser.add_argument('-t', '--tag-correlation',   required=False,   action='store_true')
 
args = parser.parse_args()
 
try:
   with open(args.cfg_file) as cfg_file:
      cfg = yaml.safe_load(cfg_file)
except FileNotFoundError:
   msg = "Cfg file not found: " + args.cfg_file
   raise Exception(msg)
 
snow_req = json.loads(args.snow_req)
#snow_req['variables'].update( { 'storage_instances': 1 } )
if not "storage_instances" in snow_req['variables']:
   snow_req['variables'].update( { 'storage_instances': 1 } )
if snow_req['variables']['service_name'].lower() == 'fsu':
   snow_req['variables'].update( { 'nar_id': '62655-2' } )
if snow_req['variables']['service_name'].lower() == 'ediscovery':
   snow_req['variables'].update( { 'nar_id': '62655-2' } )
 
#---- Get sys_id for manual cvo invocation -----#
if snow_req['variables']['service_name'].lower().startswith('cvo'):
   if not "sys_id" in snow_req:
      sys_id = get_sysid(snow_req)
      snow_req.update( { 'sys_id': sys_id } )
     
snow_cfg = {
   "base_url": snow_req['url'],
   "sys_id":   snow_req['sys_id'],
   "correlation_id":   snow_req['number']
}
snow_cfg.update(cfg['snow'])
 
snow_srvr = snow( snow_cfg )
 
#--------------------------------------------------------------------
# If we are using the serviceNow to log results. Then First thing we need to do
# is fetching the access Token
#--------------------------------------------------------------------
 
if not args.skip_snow:
   snow_srvr.get_auth_token()
   #---- Tag correlation for manual CVO allocation ------#
   if args.tag_correlation:
      snow_srvr.tag_correlation_id()
 
#--------------------------------------------------------------------
# Calling WFA with all the inputs passed from ServiceNow.
# In Case of any error in WFA.Log that error message to ServiceNow if not Skipped.
#  Add "MANUAL REMEDIATION REQUIRED" as special key for all errors.
#--------------------------------------------------------------------
try:
   if not args.skip_snow:
      snow_srvr.add_snow_worknotes("Snow Request Sent to WFA :: " + json.dumps(snow_req))
   wfa = wfa_server(cfg['wfa']['wf_name'], cfg['wfa']['host'], cfg['wfa'], snow_req )
   wfa.start_wf()
 
   if not wfa.success:
      if not args.skip_snow:      
         snow_srvr.add_snow_worknotes("MANUAL REMEDIATION REQUIRED: " + wfa.reason)
      sys.exit(0)
     
   wfa.wait4_wf()
 
   if not wfa.success:
      if not args.skip_snow:
         snow_srvr.add_snow_worknotes("MANUAL REMEDIATION REQUIRED: " + wfa.reason)
      sys.exit(0)
         
   if wfa.success:
      if not args.skip_snow:
         snow_srvr.add_snow_worknotes(yaml.dump(wfa.get_placement_solution()))
         snow_srvr.add_snow_worknotes(wfa.reason)
         if args.skip_dbrun:
            set_test_comment(snow_req, snow_srvr)
        
      
   if args.dump_wfa:
       print(yaml.dump(wfa.get_placement_solution()))
 
except Exception as e:
      if not args.skip_snow:
         snow_srvr.add_snow_worknotes("MANUAL REMEDIATION REQUIRED: WFA Python Code failed with Below Exception :: " + str(e))
      else:
         print("MANUAL REMEDIATION REQUIRED: WFA Python Code failed with Below Exception :: " + str(e))
      sys.exit(0)
 
#--------------------------------------------------------------------
# Calling DBRun with all the inputs passed from WFA If not skipped.
# Also Calling the translation method accroding to the 'req_source' passed from WFA.
#  Add "MANUAL REMEDIATION REQUIRED" as special key for all errors to serviceNow.
# Also Adding the Accesstoken to the inputs to the serviceNow. SO that DB run can also access the serviceNow
#--------------------------------------------------------------------
 
try:
   db = dbrun(cfg['dbrun'])
   translate = getattr(db, wfa.get_placement_solution()['req_source'], None)
   db_run_params = translate(wfa.get_placement_solution())
   if not args.skip_dbrun:
      if not args.skip_snow:
         if 'servicenow' in db_run_params['req_details']:
            for i in range(len(db_run_params['req_details']['servicenow'])):
               db_run_params['req_details']['servicenow'][i].update({'access_token': snow_srvr.snow_general_headers['Authorization']})
      db.get_auth_token()
      #print(json.dumps(db_run_params))
      if not args.skip_snow:
         snow_srvr.add_snow_worknotes("Payload Sent to DBRun :: " + json.dumps(db_run_params))    
      job_id = db.post_request(db_run_params, snow_req)
      with open("/home/snowop2/opt/bin/dbrun_payload/"+snow_req['request_item']['number']+"-"+str(job_id)+".txt", "a") as f:
         f.write(json.dumps(db_run_params))
      if not args.skip_snow:
         snow_srvr.add_snow_worknotes("DBRun Ansible Execution Audit Id :: " + str(job_id))
   if args.dump_wfa and args.skip_dbrun:
      print(yaml.safe_dump(db_run_params))
except Exception as e:
  
   if not args.skip_snow:
      snow_srvr.add_snow_worknotes("MANUAL REMEDIATION REQUIRED: Python Code failed with Below Exception :: " + str(e))
   else:
      print("MANUAL REMEDIATION REQUIRED: DBRun Python Code failed with Below Exception :: " + str(e))
   sys.exit(0)
    
 
if wfa.success and (args.skip_dbrun or db.success):
   status = "success"
else:
   status = "failure"
 
result = { "status": status, "result": { "correlation_id": snow_cfg['correlation_id']}}
if status == "failure":
   if not wfa.success:
      result['result'].update( {'error': wfa.reason} )
   else:
      result['result'].update( {'error': db.reason} )
else:
   result['result'].update( {'Message': "Every thing worked successfully"} )
 
if not args.skip_snow:
   snow_srvr.add_snow_worknotes("Python Child Code finished :: " + json.dumps(result))