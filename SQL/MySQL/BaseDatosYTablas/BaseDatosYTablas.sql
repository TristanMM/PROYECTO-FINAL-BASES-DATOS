-- Verificar si la base de datos existe y crearla si no
CREATE DATABASE IF NOT EXISTS BD_Proyecto;

USE BD_Proyecto;

-- 1. CREACIÓN DE TABLAS
CREATE TABLE usuarios (
  id_usuario INT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(25) NOT NULL,
  apellido VARCHAR(25),
  fecha_registro DATE NOT NULL DEFAULT CURRENT_DATE()
);

CREATE TABLE mensajes (
  id_mensaje INT AUTO_INCREMENT PRIMARY KEY,
  id_emisor INT NOT NULL,
  id_receptor INT NOT NULL,
  contenido LONGBLOB NOT NULL,
  fecha_hora_envio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT FK_mensajes_emisor FOREIGN KEY (id_emisor) REFERENCES usuarios(id_usuario),
  CONSTRAINT FK_mensajes_receptor FOREIGN KEY (id_receptor) REFERENCES usuarios(id_usuario)
);

CREATE TABLE correos (
  id_correo INT AUTO_INCREMENT PRIMARY KEY,
  correo VARCHAR(70) NOT NULL UNIQUE,
  contrasenna LONGBLOB NOT NULL,
  id_usuario INT NOT NULL,
  CONSTRAINT FK_correos_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
);

CREATE TABLE telefonos (
  id_telefono INT AUTO_INCREMENT PRIMARY KEY,
  telefono VARCHAR(20) NOT NULL UNIQUE,
  id_usuario INT NOT NULL,
  CONSTRAINT FK_telefonos_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
);

CREATE TABLE contactos_guardados (
  id_usuario INT NOT NULL,
  id_contacto_guardado INT NOT NULL,
  PRIMARY KEY (id_usuario, id_contacto_guardado),
  FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario),
  FOREIGN KEY (id_contacto_guardado) REFERENCES usuarios(id_usuario)
);

CREATE TABLE sesiones (
  id_sesion INT AUTO_INCREMENT PRIMARY KEY,
  id_usuario INT NOT NULL,
  token VARCHAR(255) NOT NULL UNIQUE,
  fecha_inicio DATETIME DEFAULT CURRENT_TIMESTAMP,
  fecha_expiracion DATETIME,
  CONSTRAINT FK_sesiones_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
);
