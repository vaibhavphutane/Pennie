#!/usr/bin/env python3
"""Use the public REA MCP stdio server without changing global client settings.
REA_COMMAND=/path/to/rea python3 scripts/rea_mcp.py [requests.json]
Request file: [{"name":"open_binary","arguments":{...}}, ...]
Complete MCP responses and canonical tool schemas are retained in docs/evidence.
"""
import json, os, pathlib, select, subprocess, sys, time

out = pathlib.Path('docs/evidence')
out.mkdir(parents=True, exist_ok=True)
command = os.environ.get('REA_COMMAND', 'rea')
with (out / 'rea-server.stderr').open('w') as err:
    process = subprocess.Popen([command, '--mcp'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=err, text=True, bufsize=1)
    counter = 0
    def call(method, params):
        global counter
        counter += 1
        process.stdin.write(json.dumps({'jsonrpc':'2.0','id':counter,'method':method,'params':params})+'\n')
        process.stdin.flush()
        # readline is bounded by the caller's process timeout; MCP notifications are skipped.
        for line in process.stdout:
            message = json.loads(line)
            if message.get('id') == counter:
                if 'error' in message: raise RuntimeError(message['error'])
                return message['result']
        raise RuntimeError('REA server exited')
    try:
        init = call('initialize', {'protocolVersion':'2024-11-05','capabilities':{},'clientInfo':{'name':'WriteDock-evidence','version':'1.0'}})
        (out/'rea-initialize.json').write_text(json.dumps(init, indent=2))
        process.stdin.write(json.dumps({'jsonrpc':'2.0','method':'notifications/initialized'})+'\n'); process.stdin.flush()
        catalog = call('tools/list', {})
        (out/'rea-tools.json').write_text(json.dumps(catalog, indent=2))
        print('REA MCP connected; tools:', len(catalog['tools']), flush=True)
        if len(sys.argv)>1:
            requests = json.loads(pathlib.Path(sys.argv[1]).read_text())
            for i, request in enumerate(requests):
                result = call('tools/call',request)
                dest = out / ('rea-'+pathlib.Path(sys.argv[1]).stem+'-'+str(i)+'-'+request['name']+'.json')
                dest.write_text(json.dumps(result,indent=2))
                print(str(dest), 'isError:',result.get('isError',False), flush=True)
    finally:
        process.stdin.close()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                # Stop only this owned server process. Do not delete retained provider resources.
                process.kill(); process.wait(timeout=5)
                print('Owned MCP server stopped after cleanup timeout; inspect retained provider diagnostics.', file=sys.stderr)
