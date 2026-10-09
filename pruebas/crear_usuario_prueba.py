#!/usr/bin/env python3
"""
Crea (o limpia) usuarios de PRUEBA para desarrollar el dashboard, sin tocar cuentas reales.

    python3 pruebas/crear_usuario_prueba.py ADMIN        # imprime usuario y clave temporal
    python3 pruebas/crear_usuario_prueba.py OPERATIVO
    python3 pruebas/crear_usuario_prueba.py --limpiar    # desactiva TODOS los usuarios demo.*

El usuario nace con clave temporal: al entrar por el dashboard debe cambiarla (y, si es ADMIN,
configurar el segundo factor). Quedan filas desactivadas y de auditoria (son inmutables).
Requiere el contenedor oracle-xe y los modulos bcrypt.
"""
import os, secrets, subprocess, sys, tempfile
import bcrypt

CONTENEDOR = 'oracle-xe'


def sql(sentencias):
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write('SET DEFINE OFF\n' + sentencias + '\nCOMMIT;\n')
        ruta = f.name
    os.chmod(ruta, 0o644)
    try:
        subprocess.run(['docker', 'cp', ruta, f'{CONTENEDOR}:/tmp/demo_usuario.sql'], check=True, capture_output=True)
        r = subprocess.run(['docker', 'exec', CONTENEDOR, 'bash', '-c',
                            'sqlplus -s "system[llanolat]/$ORACLE_PWD@localhost:1521/XEPDB1" @/tmp/demo_usuario.sql'],
                           capture_output=True, text=True)
        if any(x in r.stdout for x in ('ORA-', 'SP2-', 'PLS-')):
            sys.exit(r.stdout)
    finally:
        os.unlink(ruta)


if len(sys.argv) != 2 or sys.argv[1] not in ('ADMIN', 'OPERATIVO', '--limpiar'):
    sys.exit(__doc__)

if sys.argv[1] == '--limpiar':
    sql("UPDATE sesiones_usuario SET revocado = 1 WHERE id_usuario IN (SELECT id_usuario FROM usuarios_app WHERE usuario LIKE 'demo.%');\n"
        "UPDATE usuarios_app SET activo = 0 WHERE usuario LIKE 'demo.%';")
    print('Usuarios demo.* desactivados.')
    sys.exit(0)

rol = sys.argv[1]
usuario = f"demo.{rol.lower()}.{secrets.token_hex(3)}"
clave = 'Tmp-' + secrets.token_urlsafe(9)
h = bcrypt.hashpw(clave.encode(), bcrypt.gensalt(12)).decode()
sql(f"INSERT INTO usuarios_app (usuario,nombre,email,rol,password_hash,debe_cambiar_clave) VALUES "
    f"('{usuario}','Demo {rol.title()} {usuario[-6:]}','{usuario}@example.com','{rol}','{h}',1);")
print(f'usuario: {usuario}\nrol:     {rol}\nclave temporal: {clave}')
