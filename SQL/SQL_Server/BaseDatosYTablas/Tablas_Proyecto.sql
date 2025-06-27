-- Verificar si la base de datos existe y crearla si no
IF NOT EXISTS (SELECT *
    FROM sys.databases
    WHERE name = 'BD_Proyecto')
BEGIN
 CREATE DATABASE BD_Proyecto;
END
GO

USE BD_Proyecto;
GO

-- 1. CREACIÓN DE TABLAS
CREATE TABLE usuarios(
 id_usuario INT IDENTITY(1,1) PRIMARY KEY,
 nombre VARCHAR(25) NOT NULL,
 apellido VARCHAR(25),
 fecha_registro DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE)
);

CREATE TABLE mensajes (
 id_mensaje INT PRIMARY KEY IDENTITY(1,1),
 id_emisOR INT NOT NULL,
 id_receptOR INT NOT NULL,
 contenido VARBINARY(MAX) NOT NULL,
 fecha_hora_envio DATETIME NOT NULL DEFAULT GETDATE(),
 CONSTRAINT FK_mensajes_emisOR FOREIGN KEY (id_emisor) REFERENCES usuarios(id_usuario),
 CONSTRAINT FK_mensajes_receptOR FOREIGN KEY (id_receptor) REFERENCES usuarios(id_usuario)
);

CREATE TABLE correos (
 id_correo INT PRIMARY KEY IDENTITY(1,1),
 correo VARCHAR(70) NOT NULL UNIQUE,
 contrasenna VARBINARY(MAX) NOT NULL,
 id_usuario INT NOT NULL,
 CONSTRAINT FK_correos_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
);

CREATE TABLE telefonos (
 id_telefono INT PRIMARY KEY IDENTITY(1,1),
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
 id_sesiON INT IDENTITY(1,1) PRIMARY KEY,
 id_usuario INT NOT NULL,
 token VARCHAR(255) NOT NULL UNIQUE,
 fecha_inicio DATETIME DEFAULT GETDATE(),
 fecha_expiraciON DATETIME,
 CONSTRAINT FK_sesiones_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
);
GO