-- Nos aseguramos de estar usando la base de datos
USE BD_Proyecto;

-- Aquí simplemente probamos y revisamos la información que tiene nuestra base de datos
SELECT * FROM usuarios;
SELECT * FROM correos;
SELECT * FROM telefonos;
SELECT * FROM mensajes;
SELECT * FROM contactos_guardados;
SELECT * FROM sesiones;


DELETE FROM contactos_guardados;
DELETE FROM mensajes;
DELETE FROM correos;
DELETE FROM telefonos;
DELETE FROM sesiones;
DELETE FROM usuarios;
