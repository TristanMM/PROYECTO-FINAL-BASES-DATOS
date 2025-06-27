# Importacion de las librerias necesarias
from flask import Flask, render_template, request, session, jsonify, redirect, url_for
import pyodbc
import mysql.connector
import uuid
import time
import os
from datetime import datetime, timedelta

# Aqui creamos la aplicacion usando el Framework Flask
app = Flask(__name__)
app.secret_key = "root123"

SQL_SERVER_CONFIG = {
    "driver": "{ODBC Driver 17 for SQL Server}",
    "server": "localhost",
    "database": "BD_Proyecto",
    "timeout": 3,
}
MYSQL_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "root",
    "database": "BD_Proyecto_Replica",
    "connection_timeout": 3,
}

# --- GESTIÓN DEL ESTADO DE LA BASE DE DATOS ---
DB_STATUS_FILE = "estado_db.txt"


def get_db_status():
    try:
        with open(DB_STATUS_FILE, "r") as f:
            status = f.read().strip()
            return status if status in ["principal", "secundaria"] else "principal"
    except FileNotFoundError:
        return "principal"


def set_db_status(status):
    with open(DB_STATUS_FILE, "w") as f:
        f.write(status)
    print(f" ESTADO DE LA BASE DE DATOS CAMBIADO A: {status.upper()} ")


def get_connection():
    status = get_db_status()

    if status == "principal":
        try:
            conn_str = (
                f"DRIVER={SQL_SERVER_CONFIG['driver']};"
                f"SERVER={SQL_SERVER_CONFIG['server']};"
                f"DATABASE={SQL_SERVER_CONFIG['database']};"
                f"Trusted_Connection=yes;"
                f"ConnectionTimeout={SQL_SERVER_CONFIG['timeout']};"
            )
            conn = pyodbc.connect(conn_str)
            print("✅ Conexión a SQL Server (Principal) exitosa.")
            return conn, "sqlserver"
        except pyodbc.Error as ex:
            print(f"❌ FALLO AL CONECTAR CON SQL SERVER: {ex}")
            print("--- INICIANDO FAILOVER A MYSQL ---")
            set_db_status("secundaria")
            try:
                conn = mysql.connector.connect(**MYSQL_CONFIG)
                print("✅ Conexión a MySQL (Secundaria) exitosa.")
                return conn, "mysql"
            except mysql.connector.Error as mysql_ex:
                print(f"❌ FALLO CRÍTICO: MySQL también está caído: {mysql_ex}")
                return None, None
    else:
        try:
            conn = mysql.connector.connect(**MYSQL_CONFIG)
            print("✅ Conexión a MySQL (Secundaria) exitosa.")
            return conn, "mysql"
        except mysql.connector.Error as ex:
            print(f"❌ FALLO CRÍTICO: MySQL (secundaria activa) está caído: {ex}")
            return None, None


# --- FUNCIÓN PARA OBTENER RESULTADOS DE SPs ---
def get_sp_result(cursor, db_type):
    """Obtiene el resultado de un SP de manera compatible."""
    if db_type == "sqlserver":
        return cursor.fetchone()
    elif db_type == "mysql":
        for result in cursor.stored_results():
            return result.fetchone()
    return None

#--- RUTAS DEL FAILOVER ---
@app.route("/login", methods=["POST"])
def login():
    data = request.get_json()
    correo = data.get("correo")
    contrasena = data.get("contrasena")

    conn, db_type = get_connection()
    if not conn:
        return jsonify(
            {
                "success": False,
                "message": "Error crítico: Ambas bases de datos están inaccesibles.",
            }
        )

    try:
        cursor = conn.cursor(dictionary=True) if db_type == "mysql" else conn.cursor()

        if db_type == "sqlserver":
            cursor.execute("{CALL sp_validar_login(?, ?)}", (correo, contrasena))
            row = cursor.fetchone()
            is_success = row and row.Success
            user_id = row.UserID if is_success else None
            message = row.Message if row else "Credenciales incorrectas"

        elif db_type == "mysql":
            cursor.callproc("sp_validar_login_mysql", [correo, contrasena])
            row = get_sp_result(cursor, db_type)
            is_success = row and row.get("Success") == 1
            user_id = row.get("UserID") if is_success else None
            message = row.get("Message") if row else "Credenciales incorrectas"

        if is_success:
            token = str(uuid.uuid4())
            if db_type == "sqlserver":
                cursor.execute("{CALL sp_crear_sesion(?, ?, ?)}", (user_id, token, 30))
            elif db_type == "mysql":
                cursor.callproc("sp_crear_sesion_mysql", [user_id, token, 30])

            conn.commit()
            session["token"] = token
            return jsonify({"success": True})
        else:
            return jsonify({"success": False, "message": message})

    except Exception as e:
        print(f"ERROR EN /login: {e}")
        return jsonify({"success": False, "message": f"Error interno: {e}"})
    finally:
        if conn:
            conn.close()


@app.route("/registrar", methods=["POST"])
def registrar():
    nombre = request.form["nombre"]
    apellido = request.form["apellido"]
    correo = request.form["correo"]
    contrasena = request.form["contrasena"]
    telefono = request.form["telefono"]

    conn, db_type = get_connection()
    if not conn:
        return "❌ Error crítico de conexión a la base de datos"

    try:
        cursor = conn.cursor(dictionary=True) if db_type == "mysql" else conn.cursor()

        if db_type == "sqlserver":
            cursor.execute(
                "{CALL sp_registrar_usuario(?, ?, ?, ?, ?)}",
                (nombre, apellido, correo, contrasena, telefono),
            )
            row = cursor.fetchone()
        elif db_type == "mysql":
            cursor.callproc(
                "sp_registrar_usuario_mysql",
                [nombre, apellido, correo, contrasena, telefono],
            )
            row = get_sp_result(cursor, db_type)

        conn.commit()

        is_success = row and (
            row.Success if db_type == "sqlserver" else row.get("Success") == 1
        )
        message = (
            (row.Message if db_type == "sqlserver" else row.get("Message"))
            if row
            else "Error desconocido."
        )

        if is_success:
            return redirect(url_for("index", registrado="1"))
        else:
            return f"❌ Error en el registro: {message}"

    except Exception as e:
        print(f"ERROR EN /registrar: {e}")
        return f"❌ Error en el registro: {e}"
    finally:
        if conn:
            conn.close()


def obtener_usuario_actual():
    token = session.get("token")
    if not token:
        return None

    conn, db_type = get_connection()
    if not conn:
        return None

    try:
        cursor = conn.cursor(dictionary=True) if db_type == "mysql" else conn.cursor()

        if db_type == "sqlserver":
            cursor.execute("{CALL sp_validar_sesion(?)}", (token,))
            row = cursor.fetchone()
            user_id = row.id_usuario if row else None
        elif db_type == "mysql":
            cursor.callproc(
                "sp_validar_sesion_mysql",
                [
                    token,
                ],
            )
            row = get_sp_result(cursor, db_type)
            user_id = row.get("id_usuario") if row else None

        return user_id
    except Exception as e:
        print(f"Error al obtener usuario actual: {e}")
        return None
    finally:
        if conn:
            conn.close()


@app.route("/enviar_mensaje", methods=["POST"])
def enviar_mensaje():
    emisor_id = obtener_usuario_actual()
    if not emisor_id:
        return jsonify({"success": False, "message": "No autorizado"}), 401

    data = request.get_json()
    receptor_id = data.get("contacto_id")
    mensaje = data.get("mensaje")

    conn, db_type = get_connection()
    if not conn:
        return jsonify({"success": False, "message": "Error de conexión a BD"}), 500

    try:
        cursor = conn.cursor()
        if db_type == "sqlserver":
            cursor.execute(
                "{CALL sp_enviar_mensaje(?, ?, ?)}", (emisor_id, receptor_id, mensaje)
            )
        elif db_type == "mysql":
            cursor.callproc(
                "sp_enviar_mensaje_mysql", [emisor_id, receptor_id, mensaje]
            )

        conn.commit()
        return jsonify({"success": True})
    except Exception as e:
        print(f"ERROR EN /enviar_mensaje: {e}")
        return jsonify({"success": False, "message": str(e)})
    finally:
        if conn:
            conn.close()


@app.route("/logout", methods=["POST"])
def logout():
    token = session.pop("token", None)
    if token:
        conn, db_type = get_connection()
        if conn:
            try:
                cursor = conn.cursor()
                if db_type == "sqlserver":
                    cursor.execute("{CALL sp_cerrar_sesion(?)}", (token,))
                elif db_type == "mysql":
                    cursor.callproc(
                        "sp_cerrar_sesion_mysql",
                        [
                            token,
                        ],
                    )
                conn.commit()
            except Exception as e:
                print(f"Error al cerrar sesión en BD: {e}")
            finally:
                if conn:
                    conn.close()
    return redirect(url_for("index"))


@app.route("/")
def index():
    return render_template("login_index.html")


@app.route("/chats")
def pagina_principal():
    user_id = obtener_usuario_actual()
    if user_id:
        return render_template("home_index.html")
    else:
        session.pop("token", None)
        return redirect(url_for("index"))


@app.route("/mensajes_render/<int:id_receptor>")
def renderizar_mensajes(id_receptor):
    id_emisor = obtener_usuario_actual()
    if not id_emisor:
        return "No autorizado", 401

    conn, db_type = get_connection()
    if not conn:
        return "Error al conectar con la BD", 500

    try:
        cursor = conn.cursor(dictionary=True) if db_type == "mysql" else conn.cursor()

        if db_type == "sqlserver":
            cursor.execute("{CALL sp_obtener_mensajes(?, ?)}", (id_emisor, id_receptor))
            mensajes = cursor.fetchall()
            mensajes = [
                dict(zip([column[0] for column in cursor.description], row))
                for row in mensajes
            ]
        elif db_type == "mysql":
            cursor.callproc("sp_obtener_mensajes_mysql", [id_emisor, id_receptor])
            mensajes = []
            for result in cursor.stored_results():
                mensajes.extend(result.fetchall())

        html = ""
        for msg in mensajes:
            clase = "enviado" if msg.get("id_emisor") == id_emisor else "recibido"
            contenido = (
                str(msg.get("contenido", "")).replace("<", "&lt;").replace(">", "&gt;")
            )
            html += f"""
            <div class="mensaje {clase}">
              <p>{contenido}</p>
              <small>{msg.get('fecha_hora_envio')}</small>
            </div>
            """
        return html
    except Exception as e:
        print(f"ERROR EN /mensajes_render: {e}")
        return f"Error al cargar mensajes: {str(e)}", 500
    finally:
        if conn:
            conn.close()


@app.route("/obtener_contactos", methods=["GET"])
def obtener_contactos():
    id_usuario = obtener_usuario_actual()
    if not id_usuario:
        return jsonify({"success": False, "message": "Sesión no válida"}), 401

    conn, db_type = get_connection()
    if not conn:
        return jsonify({"success": False, "message": "Error de conexión a BD"}), 500

    try:
        cursor = conn.cursor(dictionary=True) if db_type == "mysql" else conn.cursor()

        if db_type == "sqlserver":
            cursor.execute("{CALL sp_obtener_contactos(?)}", (id_usuario,))
            contactos = [
                dict(zip([column[0] for column in cursor.description], row))
                for row in cursor.fetchall()
            ]
        elif db_type == "mysql":
            cursor.callproc(
                "sp_obtener_contactos_mysql",
                [
                    id_usuario,
                ],
            )
            contactos = []
            for result in cursor.stored_results():
                contactos.extend(result.fetchall())

        return jsonify({"success": True, "contactos": contactos})
    except Exception as e:
        print(f"ERROR EN /obtener_contactos: {e}")
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        if conn:
            conn.close()


@app.route("/agregar_contacto", methods=["POST"])
def agregar_contacto():
    id_usuario = obtener_usuario_actual()
    if not id_usuario:
        return jsonify({"success": False, "message": " Sesión no válida"}), 401

    telefono = request.form.get("telefono")

    if not telefono:
        return jsonify({"success": False, "message": "❌ Teléfono es obligatorio"}), 400

    conn, db_type = get_connection()
    if not conn:
        return jsonify({"success": False, "message": "Error de conexión"}), 500

    try:
        cursor = conn.cursor(dictionary=True) if db_type == "mysql" else conn.cursor()

        if db_type == "sqlserver":
            cursor.execute("{CALL sp_agregar_contacto(?, ?)}", (id_usuario, telefono))
            row = cursor.fetchone()
        elif db_type == "mysql":
            cursor.callproc("sp_agregar_contacto_mysql", [id_usuario, telefono])
            row = get_sp_result(cursor, db_type)

        conn.commit()

        is_success = row and (
            row.Success if db_type == "sqlserver" else row.get("Success") == 1
        )
        message = (
            (row.Message if db_type == "sqlserver" else row.get("Message"))
            if row
            else "Error desconocido."
        )

        if is_success:
            return jsonify({"success": True, "message": message})
        else:
            return jsonify({"success": False, "message": message}), 404

    except Exception as e:
        print(f"ERROR EN /agregar_contacto: {e}")
        return jsonify({"success": False, "message": "❌ Error: " + str(e)}), 500
    finally:
        if conn:
            conn.close()


if __name__ == "__main__":
    if not os.path.exists(DB_STATUS_FILE):
        set_db_status("principal")
    app.run(debug=True)
