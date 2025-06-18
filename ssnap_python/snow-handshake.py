import argparse
import subprocess
import json
import os
 
nfs_snow_req_str  = '                                    \
   {                                                \
      "number":            "TASK0006557792",           \
      "short_description": "NAS Automation",      \
      "service":           "NAS Automation",    \
      "service_level":     "NAS Premium",  \
      "opened_at":         "2020-10-25 08:00:00",   \
      "sys_id":            "b2f77353dbdca01443239616f3961926",                \
      "url":               https://dbunitydev1.service-now.com,          \
      "request_item": {                             \
         "cat_item":       "NAS Premium",      \
         "number":         "RITM6791273",           \
         "u_requested_for": {                       \
            "email": todd.urie@cgi.com,           \
            "name":  "todd"                         \
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
         "group_email":          todd.urie@cgi.com, \
         "protocol":             "NFS",             \
         "storage_requirement":  1,                 \
         "storage_instances":    1,                 \
         "nis_domain":           "de.db.com",          \
         "netgroup_rw":          "rw",              \
         "netgroup_ro":          "ro",                \
         "number":               "TASK0006557792",     \
         "sys_id":               "b2f77353dbdca01443239616f3961926"           \
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
            "email": todd.urie@cgi.com,           \
            "name":  "todd"                         \
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
         "group_email":          todd.urie@cgi.com \
         "Protocol":             "SMB",             \
         "storage_requirement":  1,                 \
         "storage_instances":    1,                 \
         "nis_domain":           "de.db.com",          \
         "netgroup_rw":          "rw",              \
         "netgroup_ro":          "ro"              \
      }                                             \
   }'
 
snow_req_str = nfs_snow_req_str
 
parser = argparse.ArgumentParser()
parser.add_argument('-c', '--cfg-file',      required=False,   default='snow-interface.cfg')
parser.add_argument('-r', '--snow-req',      required=False,   default=snow_req_str)
parser.add_argument('-S', '--skip-dbrun',    required=False,   action='store_true')
parser.add_argument('-s', '--skip-snow',     required=False,   action='store_true')
parser.add_argument('-w', '--dump-wfa',      required=False,   action='store_true')
parser.add_argument(      '--dump-stdout',   required=False,   action='store_true')
 
arg_list = []
 
args = parser.parse_args()
main_file = "/home/snowop2/anaconda3/bin/python3 /home/snowop2/opt/bin/snow-interface.py"
if args.cfg_file:
    arg_list = arg_list + ["-c", args.cfg_file ]
    main_file = main_file + ' ' + '-c' + ' ' + args.cfg_file
if args.snow_req:
    arg_list = arg_list + ["-r", args.snow_req ]
    snow_req = json.loads(args.snow_req)
    main_file = main_file + ' ' + '-r' + ' ' + "'" + args.snow_req +  "'"
if args.skip_dbrun:
    arg_list = arg_list + ["--skip-dbrun"]
    main_file = main_file + ' ' + '--skip-dbrun'
if args.skip_snow:
    arg_list = arg_list + ['--skip-snow']
    main_file = main_file + ' ' + '--skip-snow'
if args.dump_wfa:
    arg_list = arg_list + ['--dump-wfa']
    main_file = main_file + ' ' + '--dump-wfa'
if args.dump_stdout:
    arg_list = arg_list + ['--dump-stdout']
    main_file = main_file + ' ' + '--dump-stdout'
 
python_exe = "/home/snowop2/anaconda3/bin/python3"
#main_file = "/home/bryce/opt/bin/snow-interface.py"
main_file = main_file + ' ' + '>/dev/null' + ' ' + '</dev/null' + ' ' + '2>/dev/null' + ' ' + '&'
 
runner = [python_exe, main_file] + arg_list
os.system(main_file)
result = { "status": "success", "result": { "correlation_id": snow_req['number']}}
result['result'].update({'message': 'Sub Process Execution Started Successfully.'})
print(json.dumps(result))
# try:
#     subprocess.Popen(runner)
# except Exception as e:
#     result = { "status": "failure", "result": { "correlation_id": snow_req['number']}}
#     result['result'].update({'error': str(e)})
#     print(json.dumps(result)) 
# else:
#     result = { "status": "success", "result": { "correlation_id": snow_req['number']}}
#     result['result'].update({'message': 'Sub Process Execution Started Successfully.'})
#     print(json.dumps(result))
