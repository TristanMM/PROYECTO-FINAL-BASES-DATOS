import pyodbc
import mysql.connector
import sys
import os
import logging
import time
from datetime import datetime

# --- CONFIGURACIÓN DEL LOGGING ---
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("replicacion.log", encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)

# --- CONFIGURACIÓN DE BASES DE DATOS ---
IP_LOCAL = "localhost"
SQL_SERVER_CONFIG = {
    "server": IP_LOCAL,
    "database": "BD_Proyecto",
    "driver": "{ODBC Driver 17 for SQL Server}",
}
MYSQL_CONFIG = {
    "host": IP_LOCAL,
    "user": "root",
    "password": "root",
    "database": "BD_Proyecto_Replica",
}


def conectar_a_sql_server():
    try:
        conn_str = f"DRIVER={SQL_SERVER_CONFIG['driver']};SERVER={SQL_SERVER_CONFIG['server']};DATABASE={SQL_SERVER_CONFIG['database']};Trusted_Connection=yes;"
        conn = pyodbc.connect(conn_str)
        logging.info("✅ Conexión a SQL Server exitosa.")
        return conn
    except Exception as e:
        logging.error(f"❌ Error al conectar a SQL Server: {e}")
        return None


def conectar_a_mysql():
    try:
        conn = mysql.connector.connect(**MYSQL_CONFIG)
        logging.info("✅ Conexión a MySQL exitosa.")
        return conn
    except Exception as e:
        logging.error(f"❌ Error al conectar a MySQL: {e}")
        return None


def replicacion_completa():
    logging.info("\n--- INICIANDO REPLICACIÓN COMPLETA ---")
    sql_conn = conectar_a_sql_server()
    mysql_conn = conectar_a_mysql()
    if not sql_conn or not mysql_conn:
        logging.error("❌ No se pudo establecer conexión con una de las bases de datos.")
        return
    sql_cursor = sql_conn.cursor()
    mysql_cursor = mysql_conn.cursor()
    try:
        logging.info(" Leyendo datos encriptados desde SQL Server...")
        sql_cursor.execute(
            "SELECT id_usuario, nombre, apellido, fecha_registro FROM usuarios"
        )
        usuarios = sql_cursor.fetchall()
        sql_cursor.execute(
            "SELECT id_correo, correo, contrasenna, id_usuario FROM correos"
        )
        correos = sql_cursor.fetchall()
        sql_cursor.execute(
            "SELECT id_mensaje, id_emisor, id_receptor, contenido, fecha_hora_envio FROM mensajes"
        )
        mensajes = sql_cursor.fetchall()
        sql_cursor.execute("SELECT id_telefono, telefono, id_usuario FROM telefonos")
        telefonos = sql_cursor.fetchall()
        sql_cursor.execute(
            "SELECT id_usuario, id_contacto_guardado FROM contactos_guardados"
        )
        contactos = sql_cursor.fetchall()
        logging.info(" Vaciando tablas en la base de datos de réplica (MySQL)...")
        mysql_cursor.execute("SET FOREIGN_KEY_CHECKS = 0;")
        mysql_cursor.execute("TRUNCATE TABLE contactos_guardados;")
        mysql_cursor.execute("TRUNCATE TABLE telefonos;")
        mysql_cursor.execute("TRUNCATE TABLE correos;")
        mysql_cursor.execute("TRUNCATE TABLE mensajes;")
        mysql_cursor.execute("TRUNCATE TABLE usuarios;")
        mysql_cursor.execute("SET FOREIGN_KEY_CHECKS = 1;")
        logging.info(" Escribiendo datos encriptados en MySQL...")
        mysql_cursor.executemany(
            "INSERT INTO usuarios VALUES (%s, %s, %s, %s)",
            [tuple(row) for row in usuarios],
        )
        mysql_cursor.executemany(
            "INSERT INTO correos VALUES (%s, %s, %s, %s)",
            [tuple(row) for row in correos],
        )
        mysql_cursor.executemany(
            "INSERT INTO mensajes VALUES (%s, %s, %s, %s, %s)",
            [tuple(row) for row in mensajes],
        )
        mysql_cursor.executemany(
            "INSERT INTO telefonos VALUES (%s, %s, %s)",
            [tuple(row) for row in telefonos],
        )
        mysql_cursor.executemany(
            "INSERT INTO contactos_guardados VALUES (%s, %s)",
            [tuple(row) for row in contactos],
        )
        mysql_conn.commit()
        logging.info(" ¡Replicación encriptada completa finalizada con éxito!")
    except Exception as e:
        logging.error(f"❌ Ocurrió un error durante la replicación: {e}")
        mysql_conn.rollback()
    finally:
        sql_conn.close()
        mysql_conn.close()
        logging.info(" Conexiones cerradas.")


def replicacion_diferencial():
    logging.info("\n--- INICIANDO REPLICACIÓN DIFERENCIAL (NUEVOS MENSAJES) ---")
    archivo_estado = "ultimo_mensaje_replicado.txt"
    ultimo_id = 0
    sql_conn = None  # Inicializamos las variables de conexión
    mysql_conn = None

    try:
        if os.path.exists(archivo_estado):
            with open(archivo_estado, "r") as f:
                ultimo_id = int(f.read().strip())
        logging.info(f" Último ID de mensaje replicado: {ultimo_id}")
    except:
        logging.warning(
            " No se pudo leer el archivo de estado. Se realizará una replicación completa para asegurar la consistencia."
        )
        replicacion_completa()
        return

    sql_conn = conectar_a_sql_server()
    mysql_conn = conectar_a_mysql()

    if not sql_conn or not mysql_conn:
        # Cerramos cualquier conexión que sí se haya podido abrir
        if sql_conn:
            sql_conn.close()
        if mysql_conn:
            mysql_conn.close()
        return

    id_mas_reciente = ultimo_id
    try:
        sql_cursor = sql_conn.cursor()
        mysql_cursor = mysql_conn.cursor()

        sql_cursor.execute(
            "SELECT id_mensaje, id_emisor, id_receptor, contenido, fecha_hora_envio FROM mensajes WHERE id_mensaje > ?",
            (ultimo_id,),
        )
        nuevos_mensajes = sql_cursor.fetchall()

        if not nuevos_mensajes:
            logging.info(" No hay mensajes nuevos para replicar.")
            # Salimos de la función si no hay nada que hacer
            return

        logging.info(f" Se encontraron {len(nuevos_mensajes)} mensajes nuevos.")
        mysql_cursor.executemany(
            "REPLACE INTO mensajes VALUES (%s, %s, %s, %s, %s)",
            [tuple(row) for row in nuevos_mensajes],
        )
        mysql_conn.commit()
        id_mas_reciente = max(row.id_mensaje for row in nuevos_mensajes)
        logging.info(
            f" Replicación diferencial finalizada. Último ID procesado: {id_mas_reciente}"
        )

    except Exception as e:
        logging.error(f"❌ Ocurrió un error durante la replicación diferencial: {e}")
        if mysql_conn:
            mysql_conn.rollback()
    finally:
        # Guardar el último ID procesado para la próxima ejecución
        with open(archivo_estado, "w") as f:
            f.write(str(id_mas_reciente))

        if sql_conn:
            sql_conn.close()
        if mysql_conn:
            mysql_conn.close()
        logging.info(" Conexiones cerradas.")


if __name__ == "__main__":
    contador_ciclos = 0
    segundos_espera = 60  # 1 minuto

    logging.info(" INICIANDO SERVICIO DE REPLICACIÓN")

    try:
        while True:
            contador_ciclos += 1
            logging.info(f"--- CICLO {contador_ciclos} ---")

            # LA REPLICACIÓN DIFERENCIAL SE EJECUTA SIEMPRE, CADA MINUTO.
            replicacion_diferencial()

            # LA REPLICACIÓN COMPLETA SE EJECUTA ADEMÁS DE LA DIFERENCIAL,
            # PERO SOLO EN LOS CICLOS PARES (CADA 2 MINUTOS).
            if contador_ciclos % 2 == 0:
                logging.info(
                    "El contador es par. Ejecutando réplica completa adicional."
                )
                replicacion_completa()

            logging.info(f" En espera durante {segundos_espera} segundos...")
            time.sleep(segundos_espera)

    except KeyboardInterrupt:
        logging.info("\n Proceso de replicación detenido por el usuario.")
