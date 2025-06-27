// Esta función cambia de la seccion de login a la de registro
function showRegister() {
  document.getElementById('login-section').classList.add('hidden');
  document.getElementById('register-section').classList.remove('hidden');
}

// Esta función cambia de la seccion de registro a la de login
function showLogin() {
  document.getElementById('register-section').classList.add('hidden');
  document.getElementById('login-section').classList.remove('hidden');
}

// Esta funcion se encarga de mostrar un mensaje emergente al usuario despues de registrarse
function showPopup(message) {
  const popup = document.getElementById("popup");
  popup.textContent = message;
  popup.classList.remove("hidden");
  popup.classList.add("visible");

  // Aqui después de 3 segundos oculta el mensaje automáticamente
  setTimeout(() => {
    popup.classList.remove("visible");
    popup.classList.add("hidden");
  }, 3000);
}

// Aqui si se registra el usuario muestra la seccion de de login y un mensaje de confirmacion
window.addEventListener('DOMContentLoaded', () => {
  const params = new URLSearchParams(window.location.search);
  if (params.get('registrado') === '1') {
    showLogin();
    showPopup("✅ Registro exitoso. Ya puedes iniciar sesión.");
    window.history.replaceState({}, document.title, window.location.pathname);
  }
});

// Funcion para el login
async function login() {
  const email = document.getElementById('login-email').value;
  const password = document.getElementById('login-password').value;

  try {
    const response = await fetch('/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ correo: email, contrasena: password })
    });

    const result = await response.json();

    // Si el login es exitoso, redirige a la pagina principal de chat(home), si no, muestra un mensaje de error
    if (result.success) {
      window.location.href = "/chats";
    } else {
      alert(result.message || "Error en el login");
    }
  } catch (error) {
    alert("Error de red: " + error.message);
  }
}

// Funcion para cerrar la sesion del usuario
function cerrarSesion() {
  fetch('/logout', {
    method: 'POST'
  }).then(() => {
    window.location.href = '/';
  }).catch(error => {
    alert("Error al cerrar sesión: " + error.message);
  });
}

function mostrarChats() {
  document.getElementById('chat-area').style.display = 'block';
  document.getElementById('contactos-area').style.display = 'none';
  document.getElementById('chat-placeholder').style.display = 'none';
  cargarContactosChat();
}

function mostrarContactos() {
  document.getElementById('chat-area').style.display = 'none';
  document.getElementById('contactos-area').style.display = 'block';
  document.getElementById('chat-placeholder').style.display = 'none';
}

function agregarContacto(event) {
  event.preventDefault();
  const formData = new FormData(event.target);

  fetch('/agregar_contacto', {
    method: 'POST',
    body: formData
  })
    .then(async response => {
      const contentType = response.headers.get("content-type");
      if (!contentType || !contentType.includes("application/json")) {
        const texto = await response.text();
        console.error("Respuesta no JSON:", texto);
        throw new Error("Respuesta no es JSON");
      }
      return response.json();
    })
    .then(data => {
      const mensaje = document.getElementById('mensaje-contacto');
      if (data.success) {
        mensaje.textContent = data.message;
        event.target.reset();
        cargarContactos();
      } else {
        mensaje.textContent = data.message || 'Error al agregar contacto';
      }
    })

}

function cargarContactosChat() {
  fetch('/obtener_contactos')
    .then(res => res.json())
    .then(data => {
      if (data.success) {
        const contenedor = document.getElementById('lista-contactos');
        contenedor.innerHTML = '';
        data.contactos.forEach((c, index) => {
          const btn = document.createElement('button');
          btn.textContent = `${c.nombre} ${c.apellido} - ${c.telefono ?? 'Sin teléfono'}`;
          btn.style.display = 'block';
          btn.style.marginBottom = '10px';
          btn.onclick = () => abrirFormularioMensaje(index, c);
          contenedor.appendChild(btn);
        });
      } else {
        alert('Error al cargar contactos: ' + (data.message || ''));
      }
    });
}

let contactoActual = null;
function abrirFormularioMensaje(index, contacto) {
  contactoActual = contacto;
  document.getElementById('contacto-seleccionado').textContent = `${contacto.nombre} ${contacto.apellido}`;
  document.getElementById('contacto-id').value = contacto.id_usuario;
  document.getElementById('form-mensaje-container').style.display = 'flex';
  seleccionarChat(contacto.id_usuario, `${contacto.nombre} ${contacto.apellido}`);
}

function enviarMensaje(event) {
  event.preventDefault();
  const contactoId = document.getElementById('contacto-id').value;
  const mensaje = document.getElementById('mensaje').value.trim();

  if (!mensaje) return;

  fetch('/enviar_mensaje', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ contacto_id: contactoId, mensaje })
  })
    .then(res => res.json())
    .then(data => {
      const msgDiv = document.getElementById('mensaje-envio');
      if (data.success) {
        document.getElementById('form-enviar-mensaje').reset();
        seleccionarChat(contactoId, window.receptorSeleccionadoNombre || '');
      } else {
        msgDiv.textContent = 'Error al enviar: ' + (data.message || '');
      }
    })
    .catch(() => {
      document.getElementById('mensaje-envio').textContent = 'Error de conexión';
    });
}

function seleccionarChat(idReceptor, nombreReceptor) {
  clearInterval(window.mensajesInterval);

  const placeholder = document.getElementById("chat-placeholder");
  if (placeholder) placeholder.style.display = "none";

  const chatArea = document.getElementById("chat-area");
  if (chatArea) chatArea.style.display = "block";

  document.getElementById("contacto-seleccionado").innerText = nombreReceptor;
  window.receptorSeleccionado = idReceptor;
  window.receptorSeleccionadoNombre = nombreReceptor;

  function actualizarMensajes() {
    fetch(`/mensajes_render/${idReceptor}`)
      .then(response => response.text())
      .then(html => {
        const mensajesDiv = document.getElementById("mensajes");
        mensajesDiv.innerHTML = html;
        mensajesDiv.scrollTop = mensajesDiv.scrollHeight;
      })
      .catch(error => {
        console.error("Error al cargar mensajes:", error);
      });
  }

  actualizarMensajes();

  window.mensajesInterval = setInterval(actualizarMensajes, 5000);
}