-- Nos aseguramos de estar usando la base de datos
USE BD_Proyecto;


SET @llave_secreta = 'root123';


-- -----------------------------------------------------
-- sp_registrar_usuario_mysql
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_registrar_usuario_mysql(
    IN p_nombre VARCHAR(25),
    IN p_apellido VARCHAR(25),
    IN p_correo VARCHAR(70),
    IN p_contrasena VARCHAR(25),
    IN p_telefono VARCHAR(20)
)
BEGIN
    DECLARE id_usuario_nuevo INT;
    DECLARE contrasena_encriptada BLOB;
    
    -- Manejador de errores para la transacción
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 0 AS 'Success', 'Error: No se pudo registrar el usuario. Se revirtió la transacción.' AS 'Message', -1 AS 'UserID';
    END;

    -- Encriptamos la contraseña usando la función de MySQL
    SET contrasena_encriptada = AES_ENCRYPT(p_contrasena, @llave_secreta);

    START TRANSACTION;
        -- Insertar el nuevo usuario y obtener su ID
        INSERT INTO usuarios (nombre, apellido, fecha_registro) VALUES (p_nombre, p_apellido, CURDATE());
        SET id_usuario_nuevo = LAST_INSERT_ID();
        
        -- Insertar el correo y la contraseña encriptada
        INSERT INTO correos (id_usuario, correo, contrasenna) VALUES (id_usuario_nuevo, p_correo, contrasena_encriptada);
        
        -- Insertar el teléfono
        INSERT INTO telefonos (id_usuario, telefono) VALUES (id_usuario_nuevo, p_telefono);
    COMMIT;
    
    SELECT 1 AS 'Success', 'Usuario registrado correctamente' AS 'Message', id_usuario_nuevo AS 'UserID';
END$$
DELIMITER ;


-- -----------------------------------------------------
-- sp_validar_login_mysql
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_validar_login_mysql(
    IN p_correo VARCHAR(70),
    IN p_contrasena VARCHAR(25)
)
BEGIN
    DECLARE v_id_usuario INT;
    DECLARE v_contrasena_desencriptada VARCHAR(25);

    -- Obtenemos el ID del usuario y desencriptamos su contraseña
    SELECT 
        u.id_usuario,
        CAST(AES_DECRYPT(c.contrasenna, @llave_secreta) AS CHAR(25))
    INTO 
        v_id_usuario, v_contrasena_desencriptada
    FROM usuarios u
    JOIN correos c ON u.id_usuario = c.id_usuario
    WHERE c.correo = p_correo;

    -- Comparamos la contraseña proporcionada con la guardada
    IF (v_id_usuario IS NOT NULL AND v_contrasena_desencriptada = p_contrasena) THEN
        SELECT 1 AS 'Success', 'Login correcto' AS 'Message', v_id_usuario AS 'UserID';
    ELSE
        SELECT 0 AS 'Success', 'Correo o contraseña incorrectos' AS 'Message', -1 AS 'UserID';
    END IF;
END$$
DELIMITER ;


-- -----------------------------------------------------
-- sp_enviar_mensaje_mysql
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_enviar_mensaje_mysql(
    IN p_id_emisor INT,
    IN p_id_receptor INT,
    IN p_contenido_mensaje TEXT
)
BEGIN
    DECLARE contenido_encriptado BLOB;
    SET contenido_encriptado = AES_ENCRYPT(p_contenido_mensaje, @llave_secreta);

    INSERT INTO mensajes (id_emisor, id_receptor, contenido, fecha_hora_envio)
    VALUES (p_id_emisor, p_id_receptor, contenido_encriptado, NOW());

    SELECT 1 AS 'Success', 'Mensaje enviado' AS 'Message';
END$$
DELIMITER ;


-- -----------------------------------------------------
-- sp_obtener_mensajes_mysql
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_obtener_mensajes_mysql(
    IN p_id_usuario1 INT,
    IN p_id_usuario2 INT
)
BEGIN
    SELECT
        id_emisor,
        id_receptor,
        CAST(AES_DECRYPT(contenido, @llave_secreta) AS CHAR(10000)) AS contenido,
        fecha_hora_envio
    FROM mensajes
    WHERE (id_emisor = p_id_usuario1 AND id_receptor = p_id_usuario2)
       OR (id_emisor = p_id_usuario2 AND id_receptor = p_id_usuario1)
    ORDER BY fecha_hora_envio ASC;
END$$
DELIMITER ;


-- -----------------------------------------------------
-- sp_crear_sesion_mysql
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_crear_sesion_mysql(
    IN p_id_usuario INT,
    IN p_token VARCHAR(255),
    IN p_minutos_expiracion INT
)
BEGIN
    INSERT INTO sesiones (id_usuario, token, fecha_inicio, fecha_expiracion)
    VALUES (p_id_usuario, p_token, NOW(), DATE_ADD(NOW(), INTERVAL p_minutos_expiracion MINUTE));
    
    SELECT 1 AS 'Success', 'Sesión creada' AS 'Message';
END$$
DELIMITER ;


-- -----------------------------------------------------
-- sp_validar_sesion_mysql
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_validar_sesion_mysql(
    IN p_token VARCHAR(255)
)
BEGIN
    SELECT id_usuario
    FROM sesiones
    WHERE token = p_token AND fecha_expiracion > NOW();
END$$
DELIMITER ;


-- -----------------------------------------------------
-- sp_cerrar_sesion_mysql
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_cerrar_sesion_mysql(
    IN p_token VARCHAR(255)
)
BEGIN
    DELETE FROM sesiones WHERE token = p_token;
    SELECT 1 AS 'Success', 'Sesión cerrada' AS 'Message';
END$$
DELIMITER ;


-- -----------------------------------------------------
-- sp_agregar_contacto_mysql
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_agregar_contacto_mysql(
    IN p_id_usuario_actual INT,
    IN p_telefono_contacto VARCHAR(20)
)
BEGIN
    DECLARE v_id_contacto_a_guardar INT;
    
    -- Buscamos el ID del usuario que tiene el número de teléfono
    SELECT id_usuario INTO v_id_contacto_a_guardar 
    FROM telefonos 
    WHERE telefono = p_telefono_contacto
    LIMIT 1;

    IF v_id_contacto_a_guardar IS NULL THEN
        SELECT 0 AS 'Success', 'No se encontró un usuario con ese teléfono.' AS 'Message';
    ELSEIF p_id_usuario_actual = v_id_contacto_a_guardar THEN
        SELECT 0 AS 'Success', 'No te puedes agregar a ti mismo como contacto.' AS 'Message';
    ELSE
        -- Verificamos si ya existe antes de insertar
        IF NOT EXISTS (SELECT 1 FROM contactos_guardados WHERE id_usuario = p_id_usuario_actual AND id_contacto_guardado = v_id_contacto_a_guardar) THEN
            INSERT INTO contactos_guardados (id_usuario, id_contacto_guardado)
            VALUES (p_id_usuario_actual, v_id_contacto_a_guardar);
            SELECT 1 AS 'Success', 'Contacto agregado correctamente.' AS 'Message';
        ELSE
            SELECT 0 AS 'Success', 'Este contacto ya existe en tu lista.' AS 'Message';
        END IF;
    END IF;
END$$
DELIMITER ;


-- -----------------------------------------------------
-- sp_obtener_contactos_mysql
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_obtener_contactos_mysql(
    IN p_id_usuario_actual INT
)
BEGIN
    SELECT
        u.id_usuario,
        u.nombre,
        u.apellido,
        t.telefono
    FROM contactos_guardados cg
    JOIN usuarios u ON cg.id_contacto_guardado = u.id_usuario
    LEFT JOIN telefonos t ON u.id_usuario = t.id_usuario
    WHERE cg.id_usuario = p_id_usuario_actual;
END$$