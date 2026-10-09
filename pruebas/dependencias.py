#!/usr/bin/env python3
"""
Busca vulnerabilidades conocidas en las librerias del backend (Maven) consultando la base publica OSV
(https://osv.dev, de Google). Solo se envian nombres y versiones de librerias publicas, ningun dato de SILA.

    cd ~/sila-backend && python3 pruebas/dependencias.py          # codigo 1 si hay hallazgos

Para el dashboard: cd ~/Documentos/dashboard/dashboard-app && npm audit --omit=dev
"""
import json, subprocess, sys, tempfile, os
import requests

with tempfile.TemporaryDirectory() as d:
    salida = os.path.join(d, 'deps.txt')
    r = subprocess.run(['./mvnw', '-q', '-o', 'dependency:list', f'-DoutputFile={salida}', '-DincludeScope=runtime'],
                       capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(salida):
        sys.exit('No se pudo listar las dependencias:\n' + r.stdout[-500:] + r.stderr[-500:])
    lineas = [l.strip() for l in open(salida) if l.strip().count(':') >= 4 and not l.startswith('The following')]

libs = []
for l in lineas:
    partes = l.split(':')
    libs.append((partes[0] + ':' + partes[1], partes[3]))
libs = sorted(set(libs))
print(f'{len(libs)} librerias de ejecucion')

consultas = [{'package': {'name': n, 'ecosystem': 'Maven'}, 'version': v} for n, v in libs]
resp = requests.post('https://api.osv.dev/v1/querybatch', json={'queries': consultas}, timeout=60)
resp.raise_for_status()
hallazgos = []
for (n, v), res in zip(libs, resp.json()['results']):
    for vuln in res.get('vulns', []):
        hallazgos.append((n, v, vuln['id']))

if not hallazgos:
    print('Sin vulnerabilidades conocidas en OSV.')
    sys.exit(0)

for n, v, vid in hallazgos:
    d = requests.get(f'https://api.osv.dev/v1/vulns/{vid}', timeout=30).json()
    sev = (d.get('database_specific') or {}).get('severity', '?')
    arreglo = []
    for a in d.get('affected', []):
        for rg in a.get('ranges', []):
            arreglo += [e['fixed'] for e in rg.get('events', []) if 'fixed' in e]
    print(f"- {n} {v}: {vid} [{sev}] {d.get('summary', '')[:110]}  (corregido en: {', '.join(sorted(set(arreglo))) or 'n/d'})")
print(f'\n{len(hallazgos)} hallazgos.')
sys.exit(1)
