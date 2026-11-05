#!/usr/bin/env python3
"""Install the Mac mini service; preserve the website and independent update host."""
from pathlib import Path
from datetime import datetime, timezone
import json
import os
import plistlib
import shutil
import subprocess

project = Path(__file__).resolve().parent.parent
root = Path('/Users/miel/server/typing-pet-share')
nginx = Path('/Users/miel/.config/nginx/conf.d/typing-pet.conf')
config = '/Users/miel/.config/nginx/nginx.conf'
nginx_bin = '/opt/homebrew/opt/nginx/bin/nginx'
uid = os.getuid()
stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
os.umask(0o077)
for folder in ['releases', 'data', 'logs', 'backups', 'deploy/launchd']:
    (root / folder).mkdir(parents=True, exist_ok=True)
release = root / 'releases' / stamp
release.mkdir()
for name in ['share_dev_server.py', 'backup_share_service.py']:
    shutil.copy2(project / 'scripts' / name, release / name)
for name in ['pyproject.toml', 'uv.lock']:
    shutil.copy2(project / 'scripts/share-service' / name, release / name)
subprocess.run(['/opt/homebrew/bin/uv', 'sync', '--project', str(release), '--frozen'], check=True)
original = nginx.read_text()
updated = original
if 'location ^~ /share-api/' not in updated:
    updated = '''map "$request_method:$uri" $typing_pet_update_method_allowed {
    default 0;
    ~^(GET|HEAD): 1;
    ~^(POST|DELETE):/share-api/v1/shares(?:/|$) 1;
}
''' + updated
    updated = updated.replace('if ($request_method !~ ^(GET|HEAD)$) { return 405; }',
                              'if ($typing_pet_update_method_allowed = 0) { return 405; }', 1)
    updated = updated.replace('    location = /latest {', '''    # Pack exchange is independent of the static site and update distribution.
    location ^~ /share-api/ {
        proxy_pass http://127.0.0.1:17868/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For "";
        proxy_set_header Cookie "";
        proxy_set_header Authorization "";
        proxy_set_header Referer "";
        client_max_body_size 50m;
        client_body_timeout 30s;
        proxy_connect_timeout 3s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
        access_log off;
        proxy_hide_header Cache-Control;
        add_header Cache-Control "no-store" always;
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header X-Content-Type-Options "nosniff" always;
    }

    location = /latest {''', 1)
    if updated == original or 'POST|DELETE' not in updated: raise SystemExit('Unexpected nginx configuration; no changes applied')
shutil.copy2(nginx, root / 'backups' / ('nginx-' + stamp + '.conf'))
nginx.write_text(updated)
try:
    subprocess.run([nginx_bin, '-t', '-c', config], check=True)
except BaseException:
    nginx.write_text(original)
    raise
current = root / 'current'
previous = current.resolve() if current.exists() else None
pending = root / '.current-new'
if pending.is_symlink(): pending.unlink()
pending.symlink_to(release, target_is_directory=True)
pending.replace(current)
labels = []
for suffix, script, schedule in [('', 'share_dev_server.py', None), ('-backup', 'backup_share_service.py', {'Hour': 4, 'Minute': 20})]:
    label = 'com.miel.typing-pet-share' + suffix
    job = {'Label': label, 'ProgramArguments': [str(current / '.venv/bin/python'), str(current / script)],
           'WorkingDirectory': str(root), 'EnvironmentVariables': {
               'TYPINGPET_SHARE_STATE_DIR': str(root / 'data'), 'TYPINGPET_SHARE_PORT': '17868',
               'TYPINGPET_SHARE_MODE': 'production', 'PYTHONUNBUFFERED': '1'},
           'StandardOutPath': str(root / 'logs' / (label + '.out.log')),
           'StandardErrorPath': str(root / 'logs' / (label + '.err.log'))}
    if schedule: job['StartCalendarInterval'] = schedule
    else: job.update(RunAtLoad=True, KeepAlive=True, ThrottleInterval=10)
    source = root / 'deploy/launchd' / (label + '.plist')
    installed = Path.home() / 'Library/LaunchAgents' / source.name
    source.write_bytes(plistlib.dumps(job)); shutil.copy2(source, installed)
    subprocess.run(['launchctl', 'bootout', f'gui/{uid}/{label}'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['launchctl', 'bootstrap', f'gui/{uid}', str(installed)], check=True)
    labels.append({'owner': 'typing-pet-share', 'source': str(source), 'installed': str(installed), 'label': label,
                   'domain': f'gui/{uid}', 'log_paths': [job['StandardOutPath'], job['StandardErrorPath']]})
subprocess.run([nginx_bin, '-s', 'reload', '-c', config], check=True)
doc = {'id': 'typing-pet-share', 'root': str(root), 'descriptor': str(root / 'service.json'), 'version': 1,
       'paths': {'source': [str(current)], 'deploy': [str(root / 'deploy')], 'data': [str(root / 'data')],
                 'logs': [str(root / 'logs')], 'backups': [str(root / 'backups')], 'config': [], 'state': [], 'output': []},
       'launchd': labels, 'compose': None, 'nginx_configs': [str(nginx)], 'nginx_mirrors': [],
       'legacy_compose': [], 'monitoring_checks': [], 'secret_profiles': [], 'exceptions': []}
(root / 'service.json').write_text(json.dumps(doc, indent=2) + '\n')
registry = Path('/Users/miel/server/infra/services/registry.json')
registry_data = json.loads(registry.read_text())
registry_data['services']['typing-pet-share'] = {k: doc[k] for k in ['id', 'root', 'descriptor']}
registry.write_text(json.dumps(registry_data, indent=2, ensure_ascii=False) + '\n')
print('Installed Typing Pet share service at https://pet.miel.ing/share-api')
