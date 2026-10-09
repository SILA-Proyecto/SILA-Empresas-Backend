#!/usr/bin/env python3
"""
Pruebas de seguridad de SILA contra el backend REAL y Oracle (modo jwt).

    cd ~/sila-backend && ./arrancar.sh            # en otra terminal, backend en :8080
    python3 pruebas/seguridad.py                  # sale con codigo 1 si algo falla

Cubre: login por pasos, MFA y anti-replay, renovacion con rotacion y deteccion de reuso, anti-CSRF,
bloqueo e intentos, revocacion inmediata (desactivar y cambiar rol), Idempotency-Key, y una MATRIZ
endpoint x rol que comprueba quien puede llamar a que. Al agregar un endpoint nuevo, agregalo a MATRIZ.

No toca cuentas reales: crea usuarios temporales t.* directamente en Oracle (como dueno del esquema,
por `docker exec`), y al final los desactiva. Quedan filas desactivadas y de auditoria (son inmutables).
Requiere: python3 con `requests` y `bcrypt`, y el contenedor oracle-xe en marcha.
"""
import argparse, base64, hashlib, hmac, os, secrets, struct, subprocess, sys, tempfile, time

import bcrypt
import requests

ap = argparse.ArgumentParser()
ap.add_argument('--base', default='http://localhost:8080')
ap.add_argument('--origin', default='http://localhost:4200')
ap.add_argument('--contenedor', default='oracle-xe')
args = ap.parse_args()
API = args.base + '/api/v1'
ORIGEN = {'Origin': args.origin}
SUF = secrets.token_hex(3)
ok = bad = 0
login_marcas = []   # para no chocar con el limite de 30 logins/min por IP del propio backend


def chk(nombre, cond, extra=''):
    global ok, bad
    if cond:
        ok += 1
        print('  OK   ', nombre)
    else:
        bad += 1
        print('  FALLA', nombre, '->', str(extra)[:200])


def seccion(t):
    print('\n== ' + t)


# ---------- utilidades ----------
def totp(secreto_b32, paso=None):
    k = base64.b32decode(secreto_b32 + '=' * (-len(secreto_b32) % 8))
    s = int(time.time()) // 30 if paso is None else paso
    h = hmac.new(k, struct.pack('>Q', s), hashlib.sha1).digest()
    o = h[-1] & 15
    return '%06d' % ((struct.unpack('>I', h[o:o + 4])[0] & 0x7fffffff) % 10 ** 6)


marcas = {}   # clave -> instantes; el backend limita por minuto, el script se adapta para no chocar con eso


def cupo(clave, maximo):
    while True:
        ahora = time.time()
        marcas[clave] = [m for m in marcas.get(clave, []) if ahora - m < 60]
        if len(marcas[clave]) < maximo:
            marcas[clave].append(ahora)
            return
        time.sleep(2)


def cupo_login(usuario=None):
    cupo('login-ip', 24)
    if usuario:
        cupo('login-' + usuario, 8)


fugas = []   # respuestas que dejaron ver detalles internos (trazas, clases, SQL)


def vigilar(r, metodo, ruta):
    if ruta.startswith('/auditoria/errores'):
        return   # muestra el registro de errores a proposito (solo ADMIN)
    t = r.text
    if any(x in t for x in ('"trace"', 'Exception', 'org.springframework', 'java.', 'ORA-', 'at com.llanolat')):
        fugas.append(f'{metodo} {ruta} -> {r.status_code}: {t[:120]}')


def sid(token):
    """La sesion (familia) que lleva el token de acceso."""
    carga = token.split('.')[1]
    import json as _j
    return _j.loads(base64.urlsafe_b64decode(carga + '=' * (-len(carga) % 4)))['sid']


def llamar(metodo, ruta, token=None, cuerpo=None, cookies=None, hdr=None):
    if isinstance(cuerpo, dict) and 'codigo' in cuerpo:
        cupo('mfa', 8)   # el backend limita los intentos de segundo factor por minuto
    h = dict(ORIGEN)
    if token:
        h['Authorization'] = 'Bearer ' + token
    if hdr:
        h.update(hdr)
    r = requests.request(metodo, API + ruta, json=cuerpo, headers=h, cookies=cookies, timeout=30)
    vigilar(r, metodo, ruta)
    return r


def auth(ruta, cuerpo=None, token=None, cookies=None, hdr=None):
    if ruta == '/login':
        cupo_login(cuerpo.get('usuario') if cuerpo else None)
    elif ruta.startswith(('/mfa/verificar', '/mfa/respaldo', '/mfa/activar')) and token:
        cupo('mfa', 8)
    return llamar('POST', '/auth' + ruta, token, cuerpo, cookies, hdr)


def sql_dueno(sentencias):
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write('SET DEFINE OFF\n' + sentencias + '\nCOMMIT;\n')
        ruta = f.name
    os.chmod(ruta, 0o644)   # el usuario oracle del contenedor tiene que poder leerlo
    try:
        subprocess.run(['docker', 'cp', ruta, f'{args.contenedor}:/tmp/seg_prueba.sql'], check=True, capture_output=True)
        r = subprocess.run(['docker', 'exec', args.contenedor, 'bash', '-c',
                            'sqlplus -s "system[llanolat]/$ORACLE_PWD@localhost:1521/XEPDB1" @/tmp/seg_prueba.sql'],
                           capture_output=True, text=True)
        if 'ORA-' in r.stdout or 'SP2-' in r.stdout or 'PLS-' in r.stdout:
            raise RuntimeError(r.stdout)
    finally:
        os.unlink(ruta)


def hash_clave(c):
    return bcrypt.hashpw(c.encode(), bcrypt.gensalt(12)).decode()


def crear_en_bd(usuario, rol, clave_temp):
    sql_dueno(f"INSERT INTO usuarios_app (usuario,nombre,email,rol,password_hash,debe_cambiar_clave) VALUES "
              f"('{usuario}','Prueba {usuario}','{usuario}@example.com','{rol}','{hash_clave(clave_temp)}',1);")


def entrar_operativo(usuario, temporal, nueva):
    """login -> cambiar clave -> acceso (los OPERATIVO no tienen MFA obligatorio)."""
    j = auth('/login', {'usuario': usuario, 'clave': temporal}).json()
    j = auth('/cambiar-clave', {'clave_actual': temporal, 'clave_nueva': nueva}, j['token_temporal']).json()
    return j['access_token']


def entrar_tmp_operativo():
    u, t, n = f't.tmp.{secrets.token_hex(3)}', 'Tmp-' + secrets.token_urlsafe(9), 'Clave-Tmp-' + secrets.token_hex(5) + '!'
    crear_en_bd(u, 'OPERATIVO', t)
    return entrar_operativo(u, t, n)


# =====================================================================
def esperar_servidor():
    for _ in range(30):
        try:
            if requests.get(args.base + '/actuator/health', timeout=3).status_code == 200:
                return
        except requests.RequestException:
            pass
        time.sleep(2)
    sys.exit('El backend no responde en ' + args.base)


def esperar_sin_limite():
    """Si una corrida anterior saturo el limite de frecuencia, esperar a que la ventana (60 s) se vacie del todo."""
    if llamar('POST', '/auth/login', None, {'usuario': 'sondeo.limite', 'clave': 'x'}).status_code == 429:
        print('(el limite de frecuencia sigue saturado por la corrida anterior; esperando 65 s)')
        time.sleep(65)


esperar_servidor()
esperar_sin_limite()
marcas.clear()

U_ADMIN, U_OPER = f't.admin.{SUF}', f't.oper.{SUF}'
T_ADMIN, T_OPER = 'Tmp-' + secrets.token_urlsafe(9), 'Tmp-' + secrets.token_urlsafe(9)
N_ADMIN, N_OPER = 'Clave-Admin-' + secrets.token_hex(5) + '!', 'Clave-Oper-' + secrets.token_hex(5) + '!'
crear_en_bd(U_ADMIN, 'ADMIN', T_ADMIN)
crear_en_bd(U_OPER, 'OPERATIVO', T_OPER)
cliente_creado = None

try:
    # ------------------------------------------------------------
    seccion('1. Sin credenciales')
    r = llamar('GET', '/catalogos/clientes')
    chk('GET protegido sin token -> 401', r.status_code == 401 and r.json()['code'] == 20013, r.text)
    chk('health abierto (sin detalles)', requests.get(args.base + '/actuator/health').json() == {'groups': ['liveness', 'readiness'], 'status': 'UP'})
    r = llamar('GET', '/catalogos/clientes', hdr={'X-Rol': 'ADMIN', 'X-Usuario': 'intruso'})
    chk('cabeceras X-Rol/X-Usuario ya no sirven -> 401', r.status_code == 401)

    r = llamar('GET', '/ruta/que/no/existe', acc_tmp := entrar_tmp_operativo())
    chk('ruta inexistente -> 404 en el formato uniforme, sin detalles', r.status_code == 404 and r.json().get('code') == 20007 and 'trace' not in r.text, r.text)
    r = llamar('PATCH', '/catalogos/clientes', acc_tmp, {})
    chk('metodo no permitido -> 4xx uniforme', 400 <= r.status_code < 500 and 'code' in r.json(), r.text)

    seccion('2. Login incorrecto')
    a, b = auth('/login', {'usuario': 'no.existe', 'clave': 'x'}), auth('/login', {'usuario': U_ADMIN, 'clave': 'mala'})
    chk('usuario inexistente y clave mala -> 401', a.status_code == 401 and b.status_code == 401)
    chk('mismo mensaje (no revela quien existe)', a.json()['message'] == b.json()['message'])
    chk('cuerpo vacio -> 400', auth('/login', {'usuario': '', 'clave': ''}).status_code == 400)

    seccion('3. ADMIN: clave temporal -> cambiar -> MFA obligatorio')
    j = auth('/login', {'usuario': U_ADMIN, 'clave': T_ADMIN}).json()
    chk('estado CAMBIAR_CLAVE sin access_token', j.get('estado') == 'CAMBIAR_CLAVE' and 'access_token' not in j, j)
    t = j['token_temporal']
    chk('token temporal NO abre la API (403)', llamar('GET', '/catalogos/clientes', t).status_code == 403)
    chk('clave debil -> 400 con campo marcado',
        (lambda r: r.status_code == 400 and 'clave_nueva' in r.json().get('fields', {}))(
            auth('/cambiar-clave', {'clave_actual': T_ADMIN, 'clave_nueva': 'corta'}, t)))
    chk('clave actual incorrecta -> 401', auth('/cambiar-clave', {'clave_actual': 'otra', 'clave_nueva': N_ADMIN}, t).status_code == 401)
    j = auth('/cambiar-clave', {'clave_actual': T_ADMIN, 'clave_nueva': N_ADMIN}, t).json()
    chk('tras cambiar: MFA_ENROLAR', j.get('estado') == 'MFA_ENROLAR', j)
    t = j['token_temporal']
    chk('activar sin configurar -> 409', auth('/mfa/activar', {'codigo': '123456'}, t).status_code == 409)
    cfg = auth('/mfa/configurar', None, t).json()
    chk('configurar da secreto y otpauth://', cfg.get('otpauth_uri', '').startswith('otpauth://totp/'), cfg)
    secreto = cfg['secreto']
    chk('codigo erroneo -> 401', auth('/mfa/activar', {'codigo': '000000'}, t).status_code == 401)
    r = auth('/mfa/activar', {'codigo': totp(secreto)}, t)
    j = r.json()
    chk('activar MFA -> OK con access_token', j.get('estado') == 'OK' and j.get('access_token'), j)
    sc = r.headers.get('Set-Cookie', '')
    chk('cookie HttpOnly, SameSite=Strict, Path=/api/v1/auth', all(x in sc for x in ('HttpOnly', 'SameSite=Strict', 'Path=/api/v1/auth')), sc)
    chk('el token de renovacion no va en el cuerpo', 'refresh' not in r.text)
    acc_admin, ck1 = j['access_token'], r.cookies.get('sila_refresh')
    codigos = j.get('codigos_respaldo', [])
    chk('al activar el MFA llegan 10 codigos de respaldo con formato XXXXX-XXXXX',
        len(codigos) == 10 and all(len(c) == 11 and c[5] == '-' for c in codigos) and len(set(codigos)) == 10, codigos)
    chk('los codigos de respaldo no vuelven a aparecer en /auth/yo', 'codigo' not in llamar('GET', '/auth/yo', acc_admin).text.lower())

    seccion('4. Token de acceso y renovacion')
    chk('/auth/yo', llamar('GET', '/auth/yo', acc_admin).json().get('usuario') == U_ADMIN)
    chk('firma alterada -> 401', llamar('GET', '/catalogos/clientes', acc_admin[:-3] + 'abc').status_code == 401)
    r = auth('/refresh', cookies={'sila_refresh': ck1})
    ck2 = r.cookies.get('sila_refresh')
    chk('refresh: nuevo access y cookie rotada', r.status_code == 200 and ck2 and ck2 != ck1, r.text)
    chk('reusar la cookie vieja -> 401', auth('/refresh', cookies={'sila_refresh': ck1}).status_code == 401)
    chk('el reuso revoca toda la familia', auth('/refresh', cookies={'sila_refresh': ck2}).status_code == 401)
    chk('sin cookie -> 401', auth('/refresh').status_code == 401)
    chk('Origin ajeno -> 403 (anti-CSRF)', auth('/refresh', cookies={'sila_refresh': ck2}, hdr={'Origin': 'http://evil.example'}).status_code == 403)

    seccion('5. Login con MFA y anti-replay')
    j = auth('/login', {'usuario': U_ADMIN, 'clave': N_ADMIN}).json()
    chk('MFA_REQUERIDO', j.get('estado') == 'MFA_REQUERIDO', j)
    t = j['token_temporal']
    chk('codigo incorrecto -> 401', auth('/mfa/verificar', {'codigo': '999999'}, t).status_code == 401)
    rx = auth('/mfa/verificar', {'codigo': totp(secreto)}, acc_admin)
    chk('token de ACCESO no sirve en /mfa/verificar -> 401|403', rx.status_code in (401, 403), str(rx.status_code) + ' ' + rx.text)
    paso = int(time.time()) // 30 + 1   # el actual ya se consumio al activar; el siguiente entra por la tolerancia
    r = auth('/mfa/verificar', {'codigo': totp(secreto, paso)}, t)
    chk('codigo valido -> OK', r.json().get('estado') == 'OK', r.text)
    acc_admin = r.json()['access_token']
    t = auth('/login', {'usuario': U_ADMIN, 'clave': N_ADMIN}).json()['token_temporal']
    r = auth('/mfa/verificar', {'codigo': totp(secreto, paso)}, t)
    chk('reusar el mismo codigo -> 401', r.status_code == 401 and 'usado' in r.text, r.text)

    seccion('5b. Codigos de respaldo del segundo factor')
    def a_mfa():
        return auth('/login', {'usuario': U_ADMIN, 'clave': N_ADMIN}).json()['token_temporal']
    r = auth('/mfa/respaldo', {'codigo_respaldo': 'ZZZZZ-ZZZZZ'}, a_mfa())
    chk('codigo de respaldo incorrecto -> 401', r.status_code == 401, r.text)
    r = auth('/mfa/respaldo', {'codigo_respaldo': codigos[0]}, a_mfa())
    j = r.json()
    chk('codigo de respaldo valido -> OK y avisa cuantos quedan (9)', j.get('estado') == 'OK' and j.get('codigos_restantes') == 9, r.text)
    acc_admin = j['access_token']
    chk('trae cookie de sesion', bool(r.cookies.get('sila_refresh')))
    r = auth('/mfa/respaldo', {'codigo_respaldo': codigos[0]}, a_mfa())
    chk('el mismo codigo NO sirve dos veces -> 401', r.status_code == 401, r.text)
    r = auth('/mfa/respaldo', {'codigo_respaldo': codigos[1].lower().replace('-', ' ')}, a_mfa())
    chk('se acepta en minuscula y sin guion (queda 8)', r.json().get('codigos_restantes') == 8, r.text)
    acc_admin = r.json()['access_token']
    chk('token de ACCESO no sirve en /mfa/respaldo (login) -> 403', auth('/mfa/respaldo', {'codigo_respaldo': codigos[2]}, acc_admin).status_code == 403)
    chk('GET restantes -> 8', llamar('GET', '/auth/mfa/respaldo', acc_admin).json() == {'restantes': 8})
    chk('regenerar con clave mala -> 401', llamar('POST', '/auth/mfa/respaldo/regenerar', acc_admin, {'clave_actual': 'mala', 'codigo': codigos[4]}).status_code == 401)
    chk('regenerar sin codigo MFA -> 400', llamar('POST', '/auth/mfa/respaldo/regenerar', acc_admin, {'clave_actual': N_ADMIN}).status_code == 400)
    r = llamar('POST', '/auth/mfa/respaldo/regenerar', acc_admin, {'clave_actual': N_ADMIN, 'codigo': codigos[4]})
    nuevos = r.json().get('codigos_respaldo', [])
    chk('regenerar -> 10 codigos nuevos distintos de los anteriores', r.status_code == 200 and len(nuevos) == 10 and not set(nuevos) & set(codigos), r.text)
    rv = auth('/mfa/respaldo', {'codigo_respaldo': codigos[3]}, a_mfa())
    chk('los codigos viejos dejan de servir -> 401', rv.status_code == 401, rv.text)
    chk('GET restantes -> 10', llamar('GET', '/auth/mfa/respaldo', acc_admin).json() == {'restantes': 10})
    # --- acciones sensibles con sesion abierta: piden el segundo factor (aqui con codigos de respaldo)
    perfil = {'nombre': 'Admin Prueba Editado', 'email': U_ADMIN.replace('@', '_') + '@prueba.local'}
    chk('editar mis datos sin codigo -> 400', llamar('PUT', '/auth/yo', acc_admin, perfil).status_code == 400)
    chk('editar mis datos con codigo malo -> 401', llamar('PUT', '/auth/yo', acc_admin, {**perfil, 'codigo': '123456'}).status_code == 401)
    r = llamar('PUT', '/auth/yo', acc_admin, {**perfil, 'codigo': nuevos[0]})
    chk('editar mis datos con codigo valido -> 200 y cambia', r.status_code == 200 and r.json().get('nombre') == perfil['nombre'] and r.json().get('email') == perfil['email'].lower(), r.text)
    chk('el rol y el usuario no cambian', r.json().get('rol') == 'ADMIN' and r.json().get('usuario') == U_ADMIN, r.text)
    rr = llamar('PUT', '/auth/yo', acc_admin, {**perfil, 'codigo': nuevos[0]})
    chk('el codigo de respaldo usado no sirve otra vez -> 401', rr.status_code == 401, str(rr.status_code) + ' ' + rr.text)
    chk('correo invalido -> 400', llamar('PUT', '/auth/yo', acc_admin, {**perfil, 'email': 'no-es-correo', 'codigo': nuevos[1]}).status_code == 400)
    r = auth('/cambiar-clave', {'clave_actual': N_ADMIN, 'clave_nueva': N_ADMIN + 'x1!Zq9'}, acc_admin)
    chk('cambiar clave con sesion abierta sin codigo -> 400', r.status_code == 400, r.text)
    chk('un OPERATIVO sin MFA no puede regenerar -> 409', llamar('POST', '/auth/mfa/respaldo/regenerar', entrar_tmp_operativo(), {'clave_actual': 'x', 'codigo': '123456'}).status_code in (401, 409))

    seccion('6. OPERATIVO')
    acc_oper = entrar_operativo(U_OPER, T_OPER, N_OPER)
    chk('OPERATIVO entra sin MFA tras cambiar la clave', bool(acc_oper))

    # ------------------------------------------------------------
    seccion('7. MATRIZ endpoint x rol (sin token / OPERATIVO / ADMIN)')
    G = 999999999   # id inexistente: nunca modifica datos
    MATRIZ = [
        # metodo, ruta, cuerpo, esperado sin token, OPERATIVO, ADMIN   (conjuntos de codigos aceptables)
        ('GET', '/auth/yo', None, {401}, {200}, {200}),
        ('PUT', '/auth/yo', {}, {401}, {400}, {400}),
        ('GET', '/catalogos/clientes?size=1', None, {401}, {200}, {200}),
        ('GET', '/catalogos/proveedores?size=1', None, {401}, {200}, {200}),
        ('GET', '/catalogos/productos?size=1', None, {401}, {200}, {200}),
        ('GET', '/periodos?size=1', None, {401}, {200}, {200}),
        ('GET', '/periodos/actual', None, {401}, {200}, {200}),
        ('GET', '/periodos/anios', None, {401}, {200}, {200}),
        ('GET', '/ventas', None, {401}, {200}, {200}),
        ('GET', '/inventario', None, {401}, {200}, {200}),
        ('GET', '/facturas', None, {401}, {200}, {200}),
        ('GET', '/finanzas/categorias', None, {401}, {200}, {200}),
        ('POST', '/catalogos/clientes', {}, {401}, {400}, {400}),
        ('POST', '/catalogos/proveedores', {}, {401}, {400}, {400}),
        ('PUT', f'/catalogos/clientes/{G}', {}, {401}, {400}, {400}),
        ('PUT', f'/catalogos/proveedores/{G}', {}, {401}, {400}, {400}),
        ('PUT', f'/catalogos/productos/{G}', {}, {401}, {400}, {400}),
        ('POST', '/catalogos/productos', {}, {401}, {403}, {400}),
        ('PATCH', f'/catalogos/clientes/{G}/estado', {'activo': True}, {401}, {403}, {404, 409}),
        ('PATCH', f'/catalogos/proveedores/{G}/estado', {'activo': True}, {401}, {403}, {404, 409}),
        ('PATCH', f'/catalogos/productos/{G}/estado', {'activo': True}, {401}, {403}, {404, 409}),
        ('PATCH', f'/catalogos/productos/{G}/precio', {'precio_base': 1, 'tarifa_iva': 0}, {401}, {403}, {404, 409}),
        ('POST', '/periodos/anio/1999', None, {401}, {403}, {400}),
        ('PATCH', f'/periodos/{G}/estado', {'estado': 'CERRADA'}, {401}, {403}, {404}),
        ('GET', '/acopio/recepciones?size=1', None, {401}, {200}, {200}),
        ('GET', '/acopio/umbrales', None, {401}, {200}, {200}),
        ('GET', '/acopio/calidad?size=1', None, {401}, {200}, {200}),
        ('GET', '/acopio/pago-lecheros?size=1', None, {401}, {200}, {200}),
        ('POST', '/acopio/recepciones', {}, {401}, {400}, {400}),
        ('GET', '/acopio/precios?size=1', None, {401}, {200}, {200}),
        ('GET', '/acopio/saldos?size=1', None, {401}, {200}, {200}),
        ('GET', '/acopio/pagos?size=1', None, {401}, {200}, {200}),
        ('POST', '/acopio/precios', {}, {401}, {403}, {400}),
        ('POST', '/acopio/pagos', {}, {401}, {403}, {400}),
        ('POST', f'/acopio/pagos/{G}/anular', {'motivo': 'Motivo de prueba largo'}, {401}, {403}, {404}),
        ('GET', '/produccion/lotes?size=1', None, {401}, {200}, {200}),
        ('GET', '/produccion/ajustes?size=1', None, {401}, {200}, {200}),
        ('POST', '/produccion/lotes', {}, {401}, {400}, {400}),
        ('POST', '/produccion/ajustes', {}, {401}, {400}, {400}),
        ('GET', '/inventario/resumen', None, {401}, {200}, {200}),
        ('GET', '/inventario/alertas-caducidad?size=1', None, {401}, {200}, {200}),
        ('GET', '/ventas?size=1', None, {401}, {200}, {200}),
        ('GET', f'/ventas/{G}', None, {401}, {404}, {404}),
        ('GET', '/ventas/precios?id_cliente=1&size=1', None, {401}, {200}, {200}),
        ('POST', '/ventas', {}, {401}, {400}, {400}),
        ('POST', f'/ventas/{G}/anular', {'motivo': 'Motivo de prueba largo'}, {401}, {403}, {404}),
        ('GET', '/precios-cliente?size=1', None, {401}, {200}, {200}),
        ('PUT', '/precios-cliente', {'id_cliente': G, 'id_producto': G, 'precio': 1}, {401}, {403}, {404}),
        ('PATCH', f'/precios-cliente/{G}/estado', {'activo': False}, {401}, {403}, {404}),
        ('GET', '/cartera/clientes?size=1', None, {401}, {200}, {200}),
        ('GET', '/cartera/resumen', None, {401}, {200}, {200}),
        ('GET', '/cartera/abonos?size=1', None, {401}, {200}, {200}),
        ('GET', f'/cartera/clientes/{G}/ventas-pendientes', None, {401}, {200}, {200}),
        ('POST', '/cartera/abonos', {}, {401}, {400}, {400}),
        ('POST', '/cartera/castigos', {'id_cliente': G, 'motivo': 'Motivo de prueba largo'}, {401}, {403}, {404, 409}),
        ('GET', '/parametros', None, {401}, {200}, {200}),
        ('PUT', '/parametros/NO_EXISTE', {'valor': 1}, {401}, {403}, {404}),
        ('GET', '/auth/sesiones', None, {401}, {200}, {200}),
        ('GET', '/auth/mfa/respaldo', None, {401}, {200}, {200}),
        ('POST', '/auth/mfa/respaldo/regenerar', {}, {401}, {400}, {400}),
        ('DELETE', '/auth/sesiones/no-existe', None, {401}, {404}, {404}),
        ('GET', '/auditoria/accesos?size=1', None, {401}, {403}, {200}),
        ('GET', '/auditoria/cambios?size=1', None, {401}, {403}, {200}),
        ('GET', '/auditoria/errores?size=1', None, {401}, {403}, {200}),
        ('GET', f'/usuarios/{G}/sesiones', None, {401}, {403}, {404}),
        ('POST', f'/usuarios/{G}/cerrar-sesiones', None, {401}, {403}, {404}),
        ('GET', '/usuarios?size=1', None, {401}, {403}, {200}),
        ('GET', f'/usuarios/{G}', None, {401}, {403}, {404}),
        ('POST', '/usuarios', {}, {401}, {403}, {400}),
        ('PUT', f'/usuarios/{G}', {'nombre': 'Nombre Valido', 'email': 'a@b.co', 'rol': 'OPERATIVO'}, {401}, {403}, {404}),
        ('PATCH', f'/usuarios/{G}/estado', {'activo': True}, {401}, {403}, {404}),
        ('POST', f'/usuarios/{G}/desbloquear', None, {401}, {403}, {404}),
        ('POST', f'/usuarios/{G}/restablecer-clave', None, {401}, {403}, {404}),
        ('POST', f'/usuarios/{G}/restablecer-mfa', None, {401}, {403}, {404}),
    ]
    fallos = []
    for m, ruta, cuerpo, e_none, e_op, e_adm in MATRIZ:
        for quien, tok, esperado in (('sin token', None, e_none), ('OPERATIVO', acc_oper, e_op), ('ADMIN', acc_admin, e_adm)):
            r = llamar(m, ruta, tok, cuerpo, hdr={'Idempotency-Key': secrets.token_hex(16)} if m == 'POST' else None)
            if r.status_code not in esperado:
                fallos.append(f'{m} {ruta} como {quien}: {r.status_code} (esperado {sorted(esperado)})')
    chk(f'{len(MATRIZ) * 3} combinaciones endpoint x rol se comportan como se espera', not fallos, '\n         '.join(fallos))

    # ------------------------------------------------------------
    seccion('8. Revocacion inmediata')
    u_rev, u_rol = f't.rev.{SUF}', f't.rol.{SUF}'
    creados = {}
    for u, rol in ((u_rev, 'OPERATIVO'), (u_rol, 'OPERATIVO')):
        r = llamar('POST', '/usuarios', acc_admin, {'usuario': u, 'nombre': f'Prueba {u}', 'email': f'{u}@example.com', 'rol': rol})
        chk(f'ADMIN crea {u} (201, clave temporal de 16)', r.status_code == 201 and len(r.json().get('clave_temporal', '')) == 16, r.text)
        creados[u] = r.json()
    tok_rev = entrar_operativo(u_rev, creados[u_rev]['clave_temporal'], 'Rev-' + secrets.token_hex(6) + '!')
    tok_rol = entrar_operativo(u_rol, creados[u_rol]['clave_temporal'], 'Rol-' + secrets.token_hex(6) + '!')
    chk('ambos usuarios operan', llamar('GET', '/catalogos/clientes?size=1', tok_rev).status_code == 200
        and llamar('GET', '/catalogos/clientes?size=1', tok_rol).status_code == 200)
    r = llamar('PATCH', f"/usuarios/{creados[u_rev]['usuario']['id_usuario']}/estado", acc_admin, {'activo': False})
    chk('ADMIN desactiva al usuario', r.status_code == 200 and r.json()['activo'] is False, r.text)
    chk('su token (aun vigente 15 min) deja de servir AL INSTANTE -> 401', llamar('GET', '/catalogos/clientes?size=1', tok_rev).status_code == 401)
    uu = creados[u_rol]['usuario']
    r = llamar('PUT', f"/usuarios/{uu['id_usuario']}", acc_admin, {'nombre': uu['nombre'], 'email': uu['email'], 'rol': 'ADMIN'})
    chk('ADMIN le cambia el rol', r.status_code == 200 and r.json()['rol'] == 'ADMIN', r.text)
    chk('el token con el rol anterior deja de servir AL INSTANTE -> 401', llamar('GET', '/catalogos/clientes?size=1', tok_rol).status_code == 401)
    me = llamar('GET', '/auth/yo', acc_admin).json()['id_usuario']
    for etiqueta, m, ruta, cuerpo in (('desactivarse a si mismo', 'PATCH', f'/usuarios/{me}/estado', {'activo': False}),
                                     ('quitarse el rol ADMIN', 'PUT', f'/usuarios/{me}', {'nombre': 'Prueba Admin', 'email': f'{U_ADMIN}@example.com', 'rol': 'OPERATIVO'}),
                                     ('restablecer su propia clave', 'POST', f'/usuarios/{me}/restablecer-clave', None),
                                     ('quitarse el segundo factor', 'POST', f'/usuarios/{me}/restablecer-mfa', None)):
        chk(f'nadie puede {etiqueta} -> 409', llamar(m, ruta, acc_admin, cuerpo).status_code == 409)

    # ------------------------------------------------------------
    seccion('9. Idempotency-Key')
    doc = 'T' + secrets.token_hex(5).upper()
    cuerpo = {'tipo_documento': 'CC', 'numero_documento': doc, 'nombre': 'PRUEBA IDEMPOTENCIA', 'email': f'{doc.lower()}@example.com'}
    clave = 'prueba-' + secrets.token_hex(8)
    r1 = llamar('POST', '/catalogos/clientes', acc_admin, cuerpo, hdr={'Idempotency-Key': clave})
    chk('primera vez: 201 (crea el cliente)', r1.status_code == 201, r1.text)
    cliente_creado = r1.json().get('id_cliente')
    r2 = llamar('POST', '/catalogos/clientes', acc_admin, cuerpo, hdr={'Idempotency-Key': clave})
    chk('repetida: misma respuesta, marcada como repetida, SIN duplicar',
        r2.status_code == 201 and r2.headers.get('Idempotency-Replayed') == 'true' and r2.json() == r1.json(), r2.text)
    r3 = llamar('POST', '/catalogos/clientes', acc_admin, {**cuerpo, 'nombre': 'OTRO NOMBRE'}, hdr={'Idempotency-Key': clave})
    chk('misma clave, contenido distinto -> 422', r3.status_code == 422 and r3.json()['code'] == 20017, r3.text)
    r4 = llamar('POST', '/catalogos/clientes', acc_admin, cuerpo, hdr={'Idempotency-Key': 'otra-' + secrets.token_hex(8)})
    chk('otra clave, mismo documento -> 409 (duplicado real, no se oculta)', r4.status_code == 409, r4.text)
    chk('clave con formato invalido -> 400', llamar('POST', '/catalogos/clientes', acc_admin, cuerpo, hdr={'Idempotency-Key': 'corta'}).status_code == 400)
    r5 = llamar('POST', '/ventas', acc_admin, {}, hdr={})
    chk('rutas de ventas/cartera/facturacion EXIGEN la clave -> 400', r5.status_code == 400 and 'Idempotency-Key' in r5.text, r5.text)
    r6 = llamar('POST', '/catalogos/clientes', acc_oper, cuerpo, hdr={'Idempotency-Key': clave})
    chk('la clave es por usuario: otro usuario no recibe la respuesta ajena (no es 2xx repetido)',
        r6.headers.get('Idempotency-Replayed') != 'true', r6.text)
    # un fallo (4xx) no queda guardado: se puede reintentar la misma clave corregida
    clave_f = 'fallo-' + secrets.token_hex(8)
    chk('un 4xx no se guarda', llamar('POST', '/catalogos/clientes', acc_admin, {}, hdr={'Idempotency-Key': clave_f}).status_code == 400)
    doc2 = 'T' + secrets.token_hex(5).upper()
    r7 = llamar('POST', '/catalogos/clientes', acc_admin, {**cuerpo, 'numero_documento': doc2, 'email': f'{doc2.lower()}@example.com'}, hdr={'Idempotency-Key': clave_f})
    chk('tras un fallo, la misma clave puede usarse con la solicitud ya corregida', r7.status_code == 201, r7.text)
    cliente_creado = [cliente_creado, r7.json().get('id_cliente')]

    # ------------------------------------------------------------
    seccion('9b. Sesiones')
    u_ses = f't.ses.{SUF}'
    r = llamar('POST', '/usuarios', acc_admin, {'usuario': u_ses, 'nombre': 'Prueba Sesiones', 'email': f'{u_ses}@example.com', 'rol': 'OPERATIVO'})
    id_ses, pw_ses = r.json()['usuario']['id_usuario'], r.json()['clave_temporal']
    nueva_ses = 'Ses-' + secrets.token_hex(6) + '!'
    tok_a = entrar_operativo(u_ses, pw_ses, nueva_ses)                       # sesion A (cambiar clave la abre)
    rb = auth('/login', {'usuario': u_ses, 'clave': nueva_ses}); tok_b = rb.json()['access_token']; ck_b = rb.cookies.get('sila_refresh')
    rc = auth('/login', {'usuario': u_ses, 'clave': nueva_ses}); tok_c = rc.json()['access_token']
    lista = llamar('GET', '/auth/sesiones', tok_b).json()
    chk('lista mis sesiones (A, B y C)', len(lista) == 3, lista)
    chk('marca cual es la actual y trae IP y navegador', [s['actual'] for s in lista].count(True) == 1
        and all(s.get('ip') and s.get('user_agent') for s in lista), lista)
    chk('el sid del token coincide con la sesion marcada como actual', [s['familia'] for s in lista if s['actual']] == [sid(tok_b)])
    r = llamar('DELETE', f'/auth/sesiones/{sid(tok_c)}', tok_b)
    chk('cerrar la OTRA sesion -> 204', r.status_code == 204, r.text)
    chk('su token de acceso (C) deja de servir AL INSTANTE -> 401', llamar('GET', '/catalogos/clientes?size=1', tok_c).status_code == 401)
    chk('mi token (B) sigue sirviendo', llamar('GET', '/catalogos/clientes?size=1', tok_b).status_code == 200)
    chk('cerrar una sesion ajena o inexistente -> 404', llamar('DELETE', '/auth/sesiones/00000000-0000-0000-0000-000000000000', tok_b).status_code == 404)
    chk('otro usuario no puede cerrar mis sesiones (404)', llamar('DELETE', f"/auth/sesiones/{[s['familia'] for s in llamar('GET', '/auth/sesiones', tok_b).json()][0]}", acc_oper).status_code == 404)
    tok_d = auth('/login', {'usuario': u_ses, 'clave': nueva_ses}).json()['access_token']
    r = llamar('POST', '/auth/sesiones/cerrar-otras', tok_b)
    chk('cerrar las demas deja la actual: cierra A y D (2)', r.status_code == 200 and r.json() == {'cerradas': 2}, r.text)
    chk('las sesiones A y D murieron, la B vive', llamar('GET', '/catalogos/clientes?size=1', tok_d).status_code == 401
        and llamar('GET', '/catalogos/clientes?size=1', tok_a).status_code == 401
        and llamar('GET', '/catalogos/clientes?size=1', tok_b).status_code == 200)
    r = auth('/logout', cookies={'sila_refresh': ck_b})
    chk('logout corta tambien el token de acceso vigente -> 401', r.status_code == 204 and llamar('GET', '/catalogos/clientes?size=1', tok_b).status_code == 401)
    tok_e = auth('/login', {'usuario': u_ses, 'clave': nueva_ses}).json()['access_token']
    r = llamar('POST', f'/usuarios/{id_ses}/cerrar-sesiones', acc_admin)
    chk('ADMIN cierra todas las sesiones de otra persona', r.status_code == 200, r.text)
    chk('su token deja de servir AL INSTANTE', llamar('GET', '/catalogos/clientes?size=1', tok_e).status_code == 401)
    tok_f = auth('/login', {'usuario': u_ses, 'clave': nueva_ses}).json()['access_token']
    r = llamar('POST', '/auth/sesiones/cerrar-todas', tok_f)
    chk('cerrar TODAS (incluida la actual)', r.status_code == 200 and llamar('GET', '/catalogos/clientes?size=1', tok_f).status_code == 401, r.text)

    seccion('9c. Registro de accesos y auditoria (ADMIN)')
    r = llamar('GET', f'/auditoria/accesos?usuario={u_ses}&size=50', acc_admin)
    eventos = {e['evento'] for e in r.json().get('items', [])}
    chk('los eventos quedan registrados con IP', r.status_code == 200 and {'LOGIN_OK', 'LOGOUT', 'CLAVE_CAMBIADA', 'SESION_CERRADA', 'SESIONES_CERRADAS'} <= eventos
        and all(e['ip'] for e in r.json()['items'] if e['evento'] == 'LOGIN_OK'), eventos)
    r = llamar('GET', '/auditoria/accesos?evento=LOGIN_FALLIDO&size=5', acc_admin)
    chk('se filtran por evento', r.status_code == 200 and all(e['evento'] == 'LOGIN_FALLIDO' for e in r.json()['items']), r.text)
    r = llamar('GET', '/auditoria/accesos?evento=USUARIO_DESCONOCIDO&usuario=no.existe&size=5', acc_admin)
    chk('los intentos con usuarios inexistentes tambien quedan (senal de ataque)', r.status_code == 200 and r.json()['total'] >= 1, r.text)
    hoy = time.strftime('%Y-%m-%d', time.gmtime())
    rf = llamar('GET', f'/auditoria/accesos?desde={hoy}&hasta={hoy}&size=1', acc_admin)
    chk('filtro por fechas (UTC)', rf.status_code == 200 and rf.json().get('total', 0) >= 1, rf.text)
    chk('orden invalido -> 400', llamar('GET', '/auditoria/accesos?sort=password,asc', acc_admin).status_code == 400)
    rc2 = llamar('GET', '/auditoria/cambios?tabla=USUARIOS_APP&size=1', acc_admin)
    chk('cambios de auditoria con valor anterior y nuevo', rc2.status_code == 200 and rc2.json().get('total', 0) >= 1, rc2.text)
    chk('log de errores accesible', llamar('GET', '/auditoria/errores?size=1', acc_admin).status_code == 200)
    chk('un OPERATIVO no ve la auditoria -> 403', llamar('GET', '/auditoria/accesos', acc_oper).status_code == 403)

    seccion('9d. Acopio y produccion (una pasada; proveedor y producto desechables, costo 0)')
    hoy_co = (__import__('datetime').datetime.now(__import__('datetime').timezone(__import__('datetime').timedelta(hours=-5)))).strftime('%Y-%m-%d')
    def con_clave(m, ruta, tok, cuerpo=None):
        return llamar(m, ruta, tok, cuerpo, hdr={'Idempotency-Key': 'k-' + secrets.token_hex(10)})
    r = llamar('GET', '/acopio/umbrales', acc_oper)
    chk('umbrales de calidad: 10 C y 18 Dornic', r.status_code == 200 and float(r.json()['temperatura_max']) == 10 and float(r.json()['acidez_max']) == 18, r.text)
    doc = 'T' + secrets.token_hex(5).upper()
    r = llamar('POST', '/catalogos/proveedores', acc_oper, {'tipo_documento': 'NIT', 'numero_documento': doc, 'nombre': 'PRUEBA ACOPIO ' + doc, 'tipo_proveedor': 'LECHERO'})
    prov = r.json().get('id_proveedor'); chk('proveedor lechero de prueba creado', r.status_code == 201 and prov, r.text)
    cuerpo_ok = {'id_proveedor': prov, 'litros': 100.5, 'temperatura': 8, 'acidez': 16}
    r = con_clave('POST', '/acopio/recepciones', acc_oper, cuerpo_ok)
    chk('recepcion dentro de umbrales -> 201 APROBADO con la fecha de hoy en Colombia', r.status_code == 201 and r.json()['estado_calidad'] == 'APROBADO' and r.json()['fecha'] == hoy_co and r.json()['proveedor'].startswith('PRUEBA ACOPIO'), r.text)
    r = con_clave('POST', '/acopio/recepciones', acc_oper, {**cuerpo_ok, 'temperatura': 12})
    chk('temperatura alta -> 201 RECHAZADO con motivo (un rechazo no es un error)', r.status_code == 201 and r.json()['estado_calidad'] == 'RECHAZADO' and 'Temperatura' in (r.json()['motivo_rechazo'] or ''), r.text)
    r = llamar('POST', '/acopio/recepciones', acc_oper, cuerpo_ok)
    chk('sin Idempotency-Key -> 400 (la recepcion crea registros que no se borran)', r.status_code == 400 and 'Idempotency-Key' in r.text, r.text)
    r = con_clave('POST', '/acopio/recepciones', acc_oper, {**cuerpo_ok, 'fecha': '2099-01-01'})
    chk('fecha futura -> 400 con el campo marcado', r.status_code == 400 and 'fecha' in r.json().get('fields', {}), r.text)
    r = llamar('GET', f'/acopio/recepciones?id_proveedor={prov}', acc_oper)
    chk('listado filtrado por proveedor: 2 entregas', r.status_code == 200 and r.json()['total'] == 2, r.text)
    r = llamar('GET', f'/acopio/pago-lecheros?id_proveedor={prov}', acc_oper)
    it = (r.json().get('items') or [{}])[0]
    chk('pago a lecheros separa lo aprobado (100.5) de lo rechazado (100.5)', float(it.get('litros_a_pagar', -1)) == 100.5 and float(it.get('litros_rechazados', -1)) == 100.5, r.text)
    chk('calidad por proveedor: 50% de rechazo', next((float(x['porcentaje_rechazo']) for x in llamar('GET', '/acopio/calidad?size=100', acc_oper).json()['items'] if x['id_proveedor'] == prov), None) == 50.0)

    # --- precio de la leche, pagos a lecheros y cuentas de la quincena
    per_act = llamar('GET', '/periodos/actual', acc_admin).json()
    chk('un OPERATIVO no fija precios -> 403', con_clave('POST', '/acopio/precios', acc_oper, {'id_proveedor': prov, 'precio_litro': 1500}).status_code == 403)
    r = con_clave('POST', '/acopio/precios', acc_admin, {'id_proveedor': prov, 'precio_litro': 1500})
    chk('ADMIN fija el precio por litro -> 201 y queda vigente', r.status_code == 201 and float(r.json()['precio_litro']) == 1500 and r.json()['vigente'] is True, r.text)
    chk('precio invalido (0) -> 400', con_clave('POST', '/acopio/precios', acc_admin, {'id_proveedor': prov, 'precio_litro': 0}).status_code == 400)
    r = con_clave('POST', '/acopio/recepciones', acc_oper, {'id_proveedor': prov, 'litros': 10, 'temperatura': 8, 'acidez': 16})
    chk('la recepcion nueva fija precio 1500 y valor 15000', r.status_code == 201 and float(r.json()['precio_litro']) == 1500 and float(r.json()['valor_total']) == 15000, r.text)
    rech = llamar('GET', f'/acopio/recepciones?id_proveedor={prov}&estado_calidad=RECHAZADO', acc_oper).json()['items'][0]
    chk('la leche rechazada vale 0', float(rech['valor_total']) == 0, str(rech))
    ant = llamar('GET', f'/acopio/recepciones?id_proveedor={prov}&estado_calidad=APROBADO&sort=id_recepcion,asc', acc_oper).json()['items'][0]
    chk('una recepcion anterior conserva su precio (el por defecto, 2000 -> 201000)', float(ant['precio_litro']) == 2000 and float(ant['valor_total']) == 201000, str(ant))
    pago = {'id_proveedor': prov, 'id_periodo_liquidado': per_act['id_periodo'], 'monto': 100000, 'metodo_pago': 'TRANSFERENCIA', 'referencia_pago': 'PRUEBA'}
    chk('un OPERATIVO no registra pagos -> 403', con_clave('POST', '/acopio/pagos', acc_oper, pago).status_code == 403)
    chk('pago sin Idempotency-Key -> 400', llamar('POST', '/acopio/pagos', acc_admin, pago).status_code == 400)
    r = con_clave('POST', '/acopio/pagos', acc_admin, pago)
    chk('ADMIN paga 100000 -> 201 VIGENTE', r.status_code == 201 and r.json()['estado'] == 'VIGENTE' and float(r.json()['monto']) == 100000, r.text)
    id_pago = r.json().get('id_pago')
    r = con_clave('POST', '/acopio/pagos', acc_admin, {**pago, 'monto': 200000})
    chk('pagar mas que el saldo (116000) -> rechazado', r.status_code in (400, 409, 422) and r.json().get('code') == 20005, r.text)
    sp = next((x for x in llamar('GET', '/acopio/saldos?size=100', acc_admin).json()['items'] if x['id_proveedor'] == prov), {})
    chk('saldo del lechero: comprado 216000 - pagado 100000 = 116000', float(sp.get('total_comprado', 0)) == 216000 and float(sp.get('total_pagado', 0)) == 100000 and float(sp.get('saldo', 0)) == 116000, str(sp))
    it = (llamar('GET', f"/acopio/pago-lecheros?id_proveedor={prov}", acc_oper).json().get('items') or [{}])[0]
    chk('pago-lecheros trae valor, pagado y saldo de la quincena', float(it.get('valor_leche', 0)) == 216000 and float(it.get('valor_pagado', 0)) == 100000 and float(it.get('saldo', 0)) == 116000, str(it))
    cu = llamar('GET', f"/periodos/{per_act['id_periodo']}", acc_oper).json()
    chk('la quincena muestra leche comprada, pagada y por pagar', all(k in cu for k in ('leche_comprada', 'leche_pagada', 'leche_por_pagar', 'caja_neta', 'total_cobrado', 'total_vendido')) and float(cu['leche_comprada']) >= 216000 and float(cu['leche_pagada']) >= 100000, str(cu))
    chk('la quincena: por pagar = comprada - pagada', abs(float(cu['leche_por_pagar']) - (float(cu['leche_comprada']) - float(cu['leche_pagada']))) < 0.01)
    chk('un OPERATIVO no anula pagos -> 403', con_clave('POST', f'/acopio/pagos/{id_pago}/anular', acc_oper, {'motivo': 'Intento de un operativo'}).status_code == 403)
    r = con_clave('POST', f'/acopio/pagos/{id_pago}/anular', acc_admin, {'motivo': 'Pago de prueba anulado'})
    chk('ADMIN anula el pago -> ANULADO', r.status_code == 200 and r.json()['estado'] == 'ANULADO', r.text)
    r = con_clave('POST', f'/acopio/pagos/{id_pago}/anular', acc_admin, {'motivo': 'Segunda anulacion'})
    chk('anular dos veces -> 409', r.status_code == 409, r.text)
    sp = next((x for x in llamar('GET', '/acopio/saldos?size=100', acc_admin).json()['items'] if x['id_proveedor'] == prov), {})
    chk('al anular, el saldo vuelve a 216000', float(sp.get('saldo', 0)) == 216000, str(sp))
    chk('el historial de precios lista el nuevo', llamar('GET', f'/acopio/precios?id_proveedor={prov}', acc_oper).json()['total'] == 1)

    sku = 'TP' + secrets.token_hex(4).upper()
    r = llamar('POST', '/catalogos/productos', acc_admin, {'codigo_sku': sku, 'nombre': 'PRUEBA PRODUCCION ' + sku, 'unidad_medida': 'UND', 'precio_base': 1000, 'tarifa_iva': 0})
    prod = r.json().get('id_producto'); chk('producto de prueba creado (stock 0)', r.status_code == 201 and prod, r.text)
    lote_body = {'id_producto': prod, 'litros_leche_usados': 50, 'cantidad_obtenida': 40, 'costo_por_litro': 0}
    r = con_clave('POST', '/produccion/lotes', acc_oper, lote_body)
    lote = r.json()
    chk('lote -> 201 con codigo SKU-AAAAMMDD-001, rendimiento 80 % y vence en 21 dias',
        r.status_code == 201 and lote['codigo_lote'] == f"{sku}-{hoy_co.replace('-', '')}-001" and float(lote['porcentaje_rendimiento']) == 80.0 and lote['dias_restantes'] == 21, r.text)
    r = llamar('GET', f'/inventario?texto={sku}', acc_oper)
    chk('el stock subio a 40', r.status_code == 200 and float(r.json()['items'][0]['stock_actual']) == 40, r.text)
    r = con_clave('POST', '/produccion/lotes', acc_oper, {**lote_body, 'fecha_vencimiento': '2000-01-01'})
    chk('vencimiento anterior a la produccion -> 400 con el campo marcado', r.status_code == 400 and 'fecha_vencimiento' in r.json().get('fields', {}), r.text)
    r = con_clave('POST', '/produccion/ajustes', acc_oper, {'id_producto': prod, 'tipo_ajuste': 'MERMA', 'cantidad': 5, 'observacion': 'Prueba de merma'})
    chk('merma de 5 por OPERATIVO -> 201 con delta -5', r.status_code == 201 and float(r.json()['cantidad_delta']) == -5, r.text)
    r = con_clave('POST', '/produccion/ajustes', acc_oper, {'id_producto': prod, 'tipo_ajuste': 'INGRESO_INICIAL', 'cantidad': 5, 'observacion': 'No debe poder'})
    chk('sumar stock (INGRESO_INICIAL) por OPERATIVO -> 403: es solo ADMIN', r.status_code == 403 and r.json()['code'] == 20008, r.text)
    r = con_clave('POST', '/produccion/ajustes', acc_admin, {'id_producto': prod, 'tipo_ajuste': 'CORRECCION_MAS', 'cantidad': 2, 'observacion': 'Correccion de prueba'})
    chk('correccion hacia arriba por ADMIN -> 201 con delta +2', r.status_code == 201 and float(r.json()['cantidad_delta']) == 2, r.text)
    r = con_clave('POST', '/produccion/ajustes', acc_oper, {'id_producto': prod, 'tipo_ajuste': 'MERMA', 'cantidad': 1000, 'observacion': 'Dejaria negativo'})
    chk('un ajuste que dejaria el stock negativo -> 409 (stock insuficiente)', r.status_code == 409 and r.json()['code'] == 20002, r.text)
    chk('stock final 37 (40 - 5 + 2)', float(llamar('GET', f'/inventario?texto={sku}', acc_oper).json()['items'][0]['stock_actual']) == 37)
    chk('listados de lotes y ajustes del producto', llamar('GET', f'/produccion/lotes?id_producto={prod}', acc_oper).json()['total'] == 1
        and llamar('GET', f'/produccion/ajustes?id_producto={prod}', acc_oper).json()['total'] == 2)
    r = llamar('GET', '/inventario/alertas-caducidad?dias_maximos=30', acc_oper)
    chk('alertas con ventana de 30 dias incluyen el lote nuevo (vence en 21)', r.status_code == 200 and any(a['codigo_lote'] == lote['codigo_lote'] for a in r.json()['items']), r.text[:200])
    chk('alertas con la ventana normal (7 dias) NO lo incluyen', not any(a['codigo_lote'] == lote['codigo_lote'] for a in llamar('GET', '/inventario/alertas-caducidad', acc_oper).json()['items']))
    r = llamar('GET', '/inventario/resumen', acc_oper)
    chk('resumen del inventario', r.status_code == 200 and {'total_productos', 'productos_sin_stock', 'valor_total'} <= set(r.json()), r.text)
    # limpieza: desactivar lo desechable (los registros quedan; no se pueden borrar)
    llamar('PATCH', f'/catalogos/productos/{prod}/estado', acc_admin, {'activo': False})
    llamar('PATCH', f'/catalogos/proveedores/{prov}/estado', acc_admin, {'activo': False})

    seccion('9e. Ventas, precios pactados, cartera y parametros (una pasada; valores de pocos pesos)')
    CONT = {'tipo_documento': 'CC', 'numero_documento': 'P' + secrets.token_hex(5).upper(), 'nombre': 'PRUEBA VENTAS', 'email': 'pv@example.com'}
    r = llamar('POST', '/catalogos/clientes', acc_oper, CONT); cli = r.json().get('id_cliente')
    chk('cliente de prueba creado (cupo 0)', r.status_code == 201 and cli, r.text)
    r = llamar('PUT', f'/catalogos/clientes/{cli}', acc_admin, {'nombre': 'PRUEBA VENTAS', 'email': 'pv@example.com', 'limite_credito': 1000})
    chk('ADMIN le da cupo de 1000', r.status_code == 200 and float(r.json()['limite_credito']) == 1000, r.text)
    sku2 = 'TV' + secrets.token_hex(4).upper()
    r = llamar('POST', '/catalogos/productos', acc_admin, {'codigo_sku': sku2, 'nombre': 'PRUEBA VENTAS ' + sku2, 'unidad_medida': 'UND', 'precio_base': 10, 'tarifa_iva': 19})
    prod2 = r.json().get('id_producto'); chk('producto de prueba: precio 10, IVA 19 %', r.status_code == 201 and prod2, r.text)
    r = con_clave('POST', '/produccion/ajustes', acc_admin, {'id_producto': prod2, 'tipo_ajuste': 'INGRESO_INICIAL', 'cantidad': 20, 'observacion': 'Stock inicial de prueba'})
    chk('stock inicial 20', r.status_code == 201, r.text)
    r = llamar('GET', '/catalogos/clientes?texto=222222222222', acc_oper)
    cf = next((c['id_cliente'] for c in r.json()['items'] if c['numero_documento'] == '222222222222'), None)
    chk('existe el cliente CONSUMIDOR FINAL', cf is not None, r.text)
    r = llamar('GET', f'/ventas/precios?id_cliente={cli}&texto={sku2}', acc_oper)
    it = r.json()['items'][0]
    chk('punto de venta: sin acuerdo, el precio aplicable es el de lista (10)', float(it['precio_aplicable']) == 10 and it['precio_pactado'] is None, r.text)

    lin = [{'id_producto': prod2, 'cantidad': 2}]
    r = con_clave('POST', '/ventas', acc_oper, {'id_cliente': cf, 'tipo_venta': 'CONTADO', 'lineas': lin, 'pagos': [{'metodo_pago': 'EFECTIVO', 'monto': 10}, {'metodo_pago': 'TRANSFERENCIA', 'monto': 13.8, 'referencia': 'REF-1'}]})
    v1 = r.json()
    chk('contado con DOS medios (efectivo + transferencia) que suman el total 23,80 -> 201',
        r.status_code == 201 and float(v1['venta']['total_venta']) == 23.8 and len(v1['pagos']) == 2 and v1['venta']['estado_pago'] == 'PAGADA' and float(v1['venta']['saldo_pendiente']) == 0, r.text)
    chk('la linea trae subtotal 20 e IVA 3,80, sin precio pactado', float(v1['lineas'][0]['subtotal']) == 20 and float(v1['lineas'][0]['valor_iva']) == 3.8 and v1['lineas'][0]['precio_pactado'] is False)
    chk('la fecha de la venta es hoy en Colombia', v1['venta']['fecha_venta'][:10] == hoy_co, v1['venta']['fecha_venta'])
    chk('el stock bajo a 18', float(llamar('GET', f'/inventario?texto={sku2}', acc_oper).json()['items'][0]['stock_actual']) == 18)
    r = con_clave('POST', '/ventas', acc_oper, {'id_cliente': cf, 'tipo_venta': 'CONTADO', 'lineas': lin, 'pagos': [{'metodo_pago': 'EFECTIVO', 'monto': 20}]})
    chk('pagos que no suman el total -> 400', r.status_code == 400 and 'suman' in r.text, r.text)
    r = con_clave('POST', '/ventas', acc_oper, {'id_cliente': cf, 'tipo_venta': 'CONTADO', 'lineas': lin})
    chk('contado sin pagos -> 400 con el campo marcado', r.status_code == 400 and 'pagos' in r.json().get('fields', {}), r.text)
    r = con_clave('POST', '/ventas', acc_oper, {'id_cliente': cli, 'tipo_venta': 'CREDITO', 'lineas': lin, 'pagos': [{'metodo_pago': 'EFECTIVO', 'monto': 23.8}]})
    chk('credito con pagos -> 400', r.status_code == 400, r.text)
    r = llamar('POST', '/ventas', acc_oper, {'id_cliente': cf, 'tipo_venta': 'CONTADO', 'lineas': lin, 'pagos': [{'metodo_pago': 'EFECTIVO', 'monto': 23.8}]})
    chk('sin Idempotency-Key -> 400', r.status_code == 400 and 'Idempotency-Key' in r.text, r.text)
    r = con_clave('POST', '/ventas', acc_oper, {'id_cliente': cf, 'tipo_venta': 'CONTADO', 'lineas': [{'id_producto': prod2, 'cantidad': 1000}], 'pagos': [{'metodo_pago': 'EFECTIVO', 'monto': 11.9}]})
    chk('mas de lo que hay en stock -> 409 (stock insuficiente)', r.status_code == 409 and r.json()['code'] == 20002, r.text)
    r = con_clave('POST', '/ventas', acc_oper, {'id_cliente': cf, 'tipo_venta': 'CREDITO', 'lineas': lin})
    chk('credito a quien tiene cupo 0 (consumidor final) -> 409 (cupo)', r.status_code == 409 and r.json()['code'] == 20003, r.text)

    r = llamar('PUT', '/precios-cliente', acc_oper, {'id_cliente': cli, 'id_producto': prod2, 'precio': 12})
    chk('un OPERATIVO no puede fijar precios pactados -> 403', r.status_code == 403, r.text)
    r = llamar('PUT', '/precios-cliente', acc_admin, {'id_cliente': cli, 'id_producto': prod2, 'precio': 12})
    pc = r.json()
    chk('ADMIN pacta 12 con el cliente (10 de lista: +2)', r.status_code == 200 and float(pc['precio']) == 12 and float(pc['diferencia']) == 2, r.text)
    r = llamar('GET', f'/ventas/precios?id_cliente={cli}&texto={sku2}', acc_oper)
    it = r.json()['items'][0]
    chk('punto de venta: a ese cliente se le muestra 12 (pactado), a otro seguiria en 10', float(it['precio_aplicable']) == 12 and float(it['precio_pactado']) == 12 and float(it['precio_base']) == 10, r.text)
    chk('a otro cliente se le muestra el de lista', float(llamar('GET', f'/ventas/precios?id_cliente={cf}&texto={sku2}', acc_oper).json()['items'][0]['precio_aplicable']) == 10)

    plazo = [x for x in llamar('GET', '/parametros', acc_oper).json() if x['clave'] == 'PLAZO_CREDITO_DIAS'][0]
    chk('parametros: plazo de credito = 30 y el IVA por defecto = 19 existe', float(plazo['valor']) == 30 and any(x['clave'] == 'IVA_DEFECTO_PORCENTAJE' and float(x['valor']) == 19 for x in llamar('GET', '/parametros', acc_oper).json()))
    chk('un OPERATIVO no cambia parametros -> 403', llamar('PUT', '/parametros/PLAZO_CREDITO_DIAS', acc_oper, {'valor': 45}).status_code == 403)
    chk('valor fuera de rango -> 400 (plazo maximo 365)', llamar('PUT', '/parametros/PLAZO_CREDITO_DIAS', acc_admin, {'valor': 9999}).status_code == 400)
    r = llamar('PUT', '/parametros/PLAZO_CREDITO_DIAS', acc_admin, {'valor': 45})
    chk('ADMIN cambia el plazo a 45 dias', r.status_code == 200 and float(r.json()['valor']) == 45, r.text)
    r = con_clave('POST', '/ventas', acc_oper, {'id_cliente': cli, 'tipo_venta': 'CREDITO', 'lineas': [{'id_producto': prod2, 'cantidad': 1}]})
    v2 = r.json()
    import datetime as _d
    vence = (_d.date.fromisoformat(hoy_co) + _d.timedelta(days=45)).isoformat()
    chk('venta a CREDITO con el precio pactado: 12 + IVA 2,28 = 14,28, PENDIENTE, vence con el plazo NUEVO (45 dias)',
        r.status_code == 201 and float(v2['venta']['total_venta']) == 14.28 and v2['venta']['estado_pago'] == 'PENDIENTE'
        and v2['venta']['fecha_vencimiento'] == vence and v2['lineas'][0]['precio_pactado'] is True and float(v2['lineas'][0]['precio_lista']) == 10, r.text)
    llamar('PUT', '/parametros/PLAZO_CREDITO_DIAS', acc_admin, {'valor': 30})
    chk('el plazo vuelve a 30', float([x for x in llamar('GET', '/parametros', acc_oper).json() if x['clave'] == 'PLAZO_CREDITO_DIAS'][0]['valor']) == 30)

    r = llamar('GET', f'/cartera/clientes?texto=PRUEBA VENTAS', acc_oper)
    chk('cartera: el cliente aparece debiendo 14,28 con estado de credito', r.status_code == 200 and any(float(c['saldo_deudor']) == 14.28 for c in r.json()['items']), r.text[:200])
    chk('ventas pendientes del cliente', len(llamar('GET', f'/cartera/clientes/{cli}/ventas-pendientes', acc_oper).json()) == 1)
    chk('resumen de cartera', {'total_cartera', 'clientes_con_deuda', 'clientes_en_mora', 'cartera_vencida'} <= set(llamar('GET', '/cartera/resumen', acc_oper).json()))
    chk('un OPERATIVO no anula ventas -> 403', llamar('POST', f"/ventas/{v1['venta']['id_venta']}/anular", acc_oper, {'motivo': 'Intento de un operativo'}).status_code == 403)
    r = con_clave('POST', f"/ventas/{v1['venta']['id_venta']}/anular", acc_admin, {'motivo': 'Venta de prueba anulada'})
    chk('ADMIN anula la venta de contado: queda ANULADA y el stock vuelve', r.status_code == 200 and r.json()['venta']['estado_pago'] == 'ANULADA'
        and float(llamar('GET', f'/inventario?texto={sku2}', acc_oper).json()['items'][0]['stock_actual']) == 19, r.text)
    r = con_clave('POST', f"/ventas/{v1['venta']['id_venta']}/anular", acc_admin, {'motivo': 'Segunda anulacion'})
    chk('anular dos veces -> 409', r.status_code == 409, r.text)

    r = con_clave('POST', '/cartera/abonos', acc_oper, {'id_cliente': cli, 'monto': 14.28, 'metodo_pago': 'EFECTIVO'})
    rec = r.json()
    chk('abono de 14,28 -> 201 con recibo, saldo restante 0 y un solo abono aplicado a esa venta',
        r.status_code == 201 and float(rec['saldo_restante']) == 0 and len(rec['abonos']) == 1 and rec['abonos'][0]['id_venta'] == v2['venta']['id_venta'], r.text)
    chk('la venta paso a PAGADA', llamar('GET', f"/ventas/{v2['venta']['id_venta']}", acc_oper).json()['venta']['estado_pago'] == 'PAGADA')
    r = con_clave('POST', '/cartera/abonos', acc_oper, {'id_cliente': cli, 'monto': 1, 'metodo_pago': 'EFECTIVO'})
    chk('abonar mas de lo que se debe -> error (no hay deuda)', r.status_code in (400, 409), r.text)
    r = con_clave('POST', f"/ventas/{v2['venta']['id_venta']}/anular", acc_admin, {'motivo': 'Intento con abonos'})
    chk('una venta con abonos no se puede anular -> 409', r.status_code == 409, r.text)
    chk('historial de abonos por recibo', llamar('GET', f"/cartera/abonos?id_recibo={rec['id_recibo']}", acc_oper).json()['total'] == 1)
    chk('un OPERATIVO no castiga cartera -> 403', llamar('POST', '/cartera/castigos', acc_oper, {'id_cliente': cli, 'motivo': 'Intento de un operativo'}).status_code == 403)
    r = con_clave('POST', '/cartera/castigos', acc_admin, {'id_cliente': cli, 'motivo': 'Cliente sin deuda: debe rechazarse'})
    chk('castigar a quien no debe nada -> 409', r.status_code == 409, r.text)
    # limpieza: lo desechable se desactiva (las ventas quedan: son de solo insercion)
    llamar('PATCH', f"/precios-cliente/{pc['id_precio']}/estado", acc_admin, {'activo': False})
    llamar('PATCH', f'/catalogos/productos/{prod2}/estado', acc_admin, {'activo': False})
    llamar('PATCH', f'/catalogos/clientes/{cli}/estado', acc_admin, {'activo': False})

    seccion('10. Bloqueo por intentos y limite de frecuencia')
    u_blq = f't.blq.{SUF}'
    r = llamar('POST', '/usuarios', acc_admin, {'usuario': u_blq, 'nombre': 'Prueba Bloqueo', 'email': f'{u_blq}@example.com', 'rol': 'OPERATIVO'})
    id_blq, pw_blq = r.json()['usuario']['id_usuario'], r.json()['clave_temporal']
    for i in range(4):
        r = auth('/login', {'usuario': u_blq, 'clave': f'mal{i}'})
    chk('intentos 1 a 4 -> 401', r.status_code == 401)
    r = auth('/login', {'usuario': u_blq, 'clave': 'mal5'})
    chk('5.o intento -> 423 cuenta bloqueada', r.status_code == 423 and r.json()['code'] == 20014, r.text)
    chk('bloqueada: ni con la clave correcta entra -> 423', auth('/login', {'usuario': u_blq, 'clave': pw_blq}).status_code == 423)
    r = llamar('POST', f'/usuarios/{id_blq}/desbloquear', acc_admin)
    chk('ADMIN desbloquea', r.status_code == 200 and r.json()['bloqueado'] is False, r.text)
    chk('tras desbloquear entra (CAMBIAR_CLAVE)', auth('/login', {'usuario': u_blq, 'clave': pw_blq}).json().get('estado') == 'CAMBIAR_CLAVE')

    seccion('11. Cierre de sesion')
    j = auth('/login', {'usuario': U_OPER, 'clave': N_OPER})
    ck = j.cookies.get('sila_refresh')
    chk('login normal de OPERATIVO', bool(ck), j.text)
    r = auth('/logout', cookies={'sila_refresh': ck})
    chk('logout 204 y cookie borrada', r.status_code == 204 and 'Max-Age=0' in r.headers.get('Set-Cookie', ''), r.headers)
    chk('tras logout la cookie no renueva', auth('/refresh', cookies={'sila_refresh': ck}).status_code == 401)

    chk('NINGUNA respuesta de toda la corrida dejo ver trazas, clases ni SQL', not fugas, fugas[:3])

    seccion('12. Limite de frecuencia (ultimo: satura el limite unos 60 s)')
    # directo, sin el regulador de ritmo del script: tiene que ser una rafaga de verdad
    codigos = [llamar('POST', '/auth/login', None, {'usuario': f'rafaga{i % 3}', 'clave': 'x'}).status_code for i in range(40)]
    chk('una rafaga de logins termina en 429', 429 in codigos, set(codigos))

finally:
    # limpieza: desactivar usuarios y clientes de prueba, cerrar sus sesiones
    try:
        ids = cliente_creado if isinstance(cliente_creado, list) else [cliente_creado]
        sql = ("UPDATE sesiones_usuario SET revocado = 1 WHERE id_usuario IN (SELECT id_usuario FROM usuarios_app WHERE usuario LIKE 't.%');\n"
               "UPDATE usuarios_app SET activo = 0, bloqueado_hasta = NULL, intentos_fallidos = 0 WHERE usuario LIKE 't.%';\n")
        for i in ids:
            if i:
                sql += f"UPDATE clientes SET activo = 0 WHERE id_cliente = {int(i)};\n"
        sql_dueno(sql)
    except Exception as e:  # la limpieza no debe ocultar el resultado
        print('  (aviso) no se pudo limpiar:', str(e)[:200])

print(f'\nRESULTADO: {ok} OK, {bad} FALLAS')
sys.exit(1 if bad else 0)
