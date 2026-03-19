const messageTemplate = document.querySelector("#message-template");
const operatorMessages = document.querySelector("#operator-messages");
const operatorForm = document.querySelector("#operator-form");
const operatorInput = document.querySelector("#operator-input");

function roleLabel(role) {
  if (role === "user") {
    return "Participante";
  }

  if (role === "assistant") {
    return "Tu respuesta";
  }

  return "Sistema";
}

function renderMessages(serverMessages) {
  operatorMessages.innerHTML = "";

  const intro = {
    role: "system",
    content: "Espera los mensajes del participante y responde desde aqui."
  };

  [intro, ...serverMessages.map((message) => ({
    role: message.sender === "participant" ? "user" : "assistant",
    content: message.content
  }))].forEach((message) => {
    const fragment = messageTemplate.content.cloneNode(true);
    const messageNode = fragment.querySelector(".message");
    const roleNode = fragment.querySelector(".message-role");
    const contentNode = fragment.querySelector(".message-content");

    messageNode.dataset.role = message.role;
    roleNode.textContent = roleLabel(message.role);
    contentNode.textContent = message.content;
    operatorMessages.appendChild(fragment);
  });

  operatorMessages.scrollTop = operatorMessages.scrollHeight;
}

async function refreshMessages() {
  try {
    const response = await fetch("/api/chat/human/messages");
    const payload = await response.json();

    if (!response.ok) {
      throw new Error(payload.error || "No se pudo actualizar el canal humano.");
    }

    renderMessages(payload.messages || []);
  } catch (error) {
    renderMessages([
      {
        sender: "operator",
        content: `Error: ${error.message}`
      }
    ]);
  }
}

async function sendReply(text) {
  const button = operatorForm.querySelector("button");
  operatorInput.disabled = true;
  button.disabled = true;
  button.textContent = "Enviando...";

  try {
    const response = await fetch("/api/chat/human/send", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        sender: "operator",
        content: text
      })
    });

    const payload = await response.json();

    if (!response.ok) {
      throw new Error(payload.error || "No se pudo enviar tu respuesta.");
    }

    renderMessages(payload.messages || []);
  } catch (error) {
    renderMessages([
      {
        sender: "operator",
        content: `Error: ${error.message}`
      }
    ]);
  } finally {
    operatorInput.disabled = false;
    button.disabled = false;
    button.textContent = "Responder";
    operatorInput.focus();
  }
}

operatorForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  const text = operatorInput.value.trim();
  if (!text) {
    return;
  }

  operatorInput.value = "";
  await sendReply(text);
});

refreshMessages();
window.setInterval(refreshMessages, 2000);
