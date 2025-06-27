-- Nos aseguramos de estar usando la base de datos
USE BD_Proyecto;
GO

-- 2. CONFIGURACIÓN DE ENCRIPTACIÓN
-- Creamos una clave maestra para la base de datos, protegida por una contraseña.
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Root12345';
GO

-- Creamos un certificado para usarlo en la encriptación.
CREATE CERTIFICATE CertificadoProyecto WITH SUBJECT = 'Certificado para encriptar datos del proyecto';
GO

-- Creamos la clave simétrica que realmente hará la encriptación, protegida por el certificado.
CREATE SYMMETRIC KEY ClaveSimetricaProyecto
WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE CertificadoProyecto;
GO

-- 3. CREACIÓN DE PROCEDIMIENTOS ALMACENADOS

-- Procedimiento para registrar un nuevo usuario
CREATE  OR ALTER PROCEDURE sp_registrar_usuario
    @nombre VARCHAR(25),
    @apellido VARCHAR(25),
    @correo VARCHAR(70),
    @contrasena VARCHAR(25),
    @telefono VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_usuario_nuevo INT;
    DECLARE @contrasena_encriptada VARBINARY(MAX);

    -- Abrimos la clave simétrica para poder usarla
    OPEN SYMMETRIC KEY ClaveSimetricaProyecto DECRYPTION BY CERTIFICATE CertificadoProyecto;

    -- Encriptamos la contraseña
    SET @contrasena_encriptada = ENCRYPTBYKEY(KEY_GUID('ClaveSimetricaProyecto'), @contrasena);

    -- Cerramos la clave
    CLOSE SYMMETRIC KEY ClaveSimetricaProyecto;

    -- Usamos una transacción para asegurar la integridad de los datos
    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO usuarios (nombre, apellido) VALUES (@nombre, @apellido);
        SET @id_usuario_nuevo = SCOPE_IDENTITY();

        INSERT INTO correos (id_usuario, correo, contrasenna) VALUES (@id_usuario_nuevo, @correo, @contrasena_encriptada);

        INSERT INTO telefonos (id_usuario, telefono) VALUES (@id_usuario_nuevo, @telefono);

        COMMIT TRANSACTION;
        SELECT 1 AS 'Success', 'Usuario registrado correctamente' AS 'Message', @id_usuario_nuevo AS 'UserID';
    END TRY
    BEGIN CATCH
        -- Si algo falla, revertimos todos los cambios
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SELECT 0 AS 'Success', ERROR_MESSAGE() AS 'Message', -1 AS 'UserID';
    END CATCH
END
GO

-- Procedimiento para validar el login de un usuario
CREATE PROCEDURE sp_validar_login
    @correo VARCHAR(70),
    @contrasena VARCHAR(25)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_usuario INT;
    DECLARE @contrasena_desencriptada VARCHAR(25);

    BEGIN TRY
        OPEN SYMMETRIC KEY ClaveSimetricaProyecto DECRYPTION BY CERTIFICATE CertificadoProyecto;

        SELECT @id_usuario = u.id_usuario,
               @contrasena_desencriptada = CONVERT(VARCHAR(25), DECRYPTBYKEY(c.contrasenna))
        FROM usuarios u
        JOIN correos c ON u.id_usuario = c.id_usuario
        WHERE c.correo = @correo;

        CLOSE SYMMETRIC KEY ClaveSimetricaProyecto;

        IF (@id_usuario IS NOT NULL AND @contrasena_desencriptada = @contrasena)
        BEGIN
            SELECT 1 AS 'Success', 'Login correcto' AS 'Message', @id_usuario AS 'UserID';
        END
        ELSE
        BEGIN
            SELECT 0 AS 'Success', 'Correo o contraseña incorrectos' AS 'Message', -1 AS 'UserID';
        END
    END TRY
    BEGIN CATCH
        IF EXISTS (SELECT * FROM sys.openkeys WHERE key_name = 'ClaveSimetricaProyecto')
            CLOSE SYMMETRIC KEY ClaveSimetricaProyecto;

        SELECT 0 AS 'Success', ERROR_MESSAGE() AS 'Message', -1 AS 'UserID';
    END CATCH
END
GO

-- Procedimiento para enviar un mensaje a un usuario
CREATE OR ALTER PROCEDURE sp_enviar_mensaje
		@id_emisor INT,
		@id_receptor INT,
		@contenido_mensaje NVARCHAR(MAX)
	AS
	BEGIN
		SET NOCOUNT ON;
		DECLARE @contenido_encriptado VARBINARY(MAX);

		BEGIN TRY
			OPEN SYMMETRIC KEY ClaveSimetricaProyecto DECRYPTION BY CERTIFICATE CertificadoProyecto;
			SET @contenido_encriptado = ENCRYPTBYKEY(KEY_GUID('ClaveSimetricaProyecto'), @contenido_mensaje);
			CLOSE SYMMETRIC KEY ClaveSimetricaProyecto;

			INSERT INTO mensajes (id_emisor, id_receptor, contenido)
			VALUES (@id_emisor, @id_receptor, @contenido_encriptado);

			SELECT 1 AS 'Success', 'Mensaje enviado' AS 'Message';
		END TRY
		BEGIN CATCH
			IF EXISTS (SELECT * FROM sys.openkeys WHERE key_name = 'ClaveSimetricaProyecto')
				CLOSE SYMMETRIC KEY ClaveSimetricaProyecto;
			SELECT 0 AS 'Success', ERROR_MESSAGE() AS 'Message';
		END CATCH
	END
	GO

-- Procedimiento para obtener y mostrar los mensajes en el chat
CREATE OR ALTER PROCEDURE sp_obtener_mensajes
		@id_usuario1 INT,
		@id_usuario2 INT
	AS
	BEGIN
		SET NOCOUNT ON;
		BEGIN TRY
			OPEN SYMMETRIC KEY ClaveSimetricaProyecto DECRYPTION BY CERTIFICATE CertificadoProyecto;

			SELECT
				id_emisor,
				id_receptor,
				CONVERT(NVARCHAR(MAX), DECRYPTBYKEY(contenido)) AS contenido,
				fecha_hora_envio
			FROM mensajes
			WHERE (id_emisor = @id_usuario1 AND id_receptor = @id_usuario2)
			   OR (id_emisor = @id_usuario2 AND id_receptor = @id_usuario1)
			ORDER BY fecha_hora_envio ASC;

			CLOSE SYMMETRIC KEY ClaveSimetricaProyecto;
		END TRY
		BEGIN CATCH
			IF EXISTS (SELECT * FROM sys.openkeys WHERE key_name = 'ClaveSimetricaProyecto')
				CLOSE SYMMETRIC KEY ClaveSimetricaProyecto;
            
			SELECT 'Error al obtener mensajes' AS 'ErrorMessage';
		END CATCH
	END
	GO

-- Procedimiento para crear la sesion de un usuario
CREATE PROCEDURE sp_crear_sesion
    @id_usuario INT,
    @token VARCHAR(255),
    @minutos_expiracion INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO sesiones (id_usuario, token, fecha_inicio, fecha_expiracion)
        VALUES (@id_usuario, @token, GETDATE(), DATEADD(minute, @minutos_expiracion, GETDATE()));
        
        SELECT 1 AS 'Success', 'Sesión creada' AS 'Message';
    END TRY
    BEGIN CATCH
        SELECT 0 AS 'Success', ERROR_MESSAGE() AS 'Message';
    END CATCH
END
GO

-- Procedimiento para validar un token de sesión y obtener el ID de usuario
CREATE PROCEDURE sp_validar_sesion
    @token VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_usuario
    FROM sesiones
    WHERE token = @token AND fecha_expiracion > GETDATE();
END
GO

-- Procedimiento para cerrar una sesión
CREATE OR ALTER PROCEDURE sp_cerrar_sesion
    @token VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DELETE FROM sesiones WHERE token = @token;
        SELECT 1 AS 'Success', 'Sesión cerrada' AS 'Message';
    END TRY
    BEGIN CATCH
        SELECT 0 AS 'Success', ERROR_MESSAGE() AS 'Message';
    END CATCH
END
GO

-- Procedimiento para agregar un contacto a la lista de un usuario
CREATE PROCEDURE sp_agregar_contacto
    @id_usuario_actual INT,
    @telefono_contacto VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_contacto_a_guardar INT;

    -- Buscamos el ID del usuario que tiene el número de teléfono proporcionado
    SELECT @id_contacto_a_guardar = id_usuario FROM telefonos WHERE telefono = @telefono_contacto;

    IF @id_contacto_a_guardar IS NULL
    BEGIN
        SELECT 0 AS 'Success', 'No se encontró un usuario con ese teléfono.' AS 'Message';
        RETURN;
    END

    -- Verificamos que el usuario no se esté agregando a sí mismo
    IF @id_usuario_actual = @id_contacto_a_guardar
    BEGIN
        SELECT 0 AS 'Success', 'No te puedes agregar a ti mismo como contacto.' AS 'Message';
        RETURN;
    END

    BEGIN TRY
        -- Verificamos si el contacto ya existe para evitar duplicados
        IF NOT EXISTS (SELECT 1 FROM contactos_guardados WHERE id_usuario = @id_usuario_actual AND id_contacto_guardado = @id_contacto_a_guardar)
        BEGIN
            INSERT INTO contactos_guardados (id_usuario, id_contacto_guardado)
            VALUES (@id_usuario_actual, @id_contacto_a_guardar);
            SELECT 1 AS 'Success', 'Contacto agregado correctamente.' AS 'Message';
        END
        ELSE
        BEGIN
            SELECT 0 AS 'Success', 'Este contacto ya existe en tu lista.' AS 'Message';
        END
    END TRY
    BEGIN CATCH
        SELECT 0 AS 'Success', ERROR_MESSAGE() AS 'Message';
    END CATCH
END
GO

-- Procedimiento para obtener y mostrar la lista de contactos de un usuario
CREATE PROCEDURE sp_obtener_contactos
    @id_usuario_actual INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        u.id_usuario,
        u.nombre,
        u.apellido,
        t.telefono
    FROM contactos_guardados cg
    JOIN usuarios u ON cg.id_contacto_guardado = u.id_usuario
    LEFT JOIN telefonos t ON u.id_usuario = t.id_usuario
    WHERE cg.id_usuario = @id_usuario_actual;
END
GO