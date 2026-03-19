const chats = {
  "chat-a": {
    kind: "human",
    label: "Chat A",
    messages: [
      {
        role: "system",
        content: "Este canal esta conectado con una persona real. Si tarda en responder, la app seguira actualizando automaticamente."
      }
    ]
  },
  "chat-b": {
    kind: "azure",
    endpoint: "/api/chat/azure",
    label: "Chat B",
    messages: [
      {
        role: "system",
        content: "Este chat responde automaticamente desde Azure OpenAI."
      }
    ]
  }
};

const messageTemplate = document.querySelector("#message-template");
const guessSelect = document.querySelector("#guess-select");
const saveGuessButton = document.querySelector("#save-guess-button");
const guessStatus = document.querySelector("#guess-status");

function roleLabel(role) {
  if (role === "user") {
    return "Participante";
  }

  if (role === "assistant") {
    return "Respuesta";
  }

  return "Sistema";
}

function renderMessages(chatId) {
  const container = document.querySelector(`#${chatId}-messages`);
  container.innerHTML = "";

  chats[chatId].messages.forEach((message) => {
    const fragment = messageTemplate.content.cloneNode(true);
    const messageNode = fragment.querySelector(".message");
    const roleNode = fragment.querySelector(".message-role");
    const contentNode = fragment.querySelector(".message-content");

    messageNode.dataset.role = message.role;
    roleNode.textContent = roleLabel(message.role);
    contentNode.textContent = message.content;
    container.appendChild(fragment);
  });

  container.scrollTop = container.scrollHeight;
}

function setFormBusy(chatId, busy, buttonText = null) {
  const form = document.querySelector(`[data-chat-form="${chatId}"]`);
  const textarea = form.querySelector("textarea");
  const button = form.querySelector("button");

  textarea.disabled = busy;
  button.disabled = busy;
  button.textContent = buttonText || (busy ? "Enviando..." : "Enviar");
}

function mapHumanMessagesForParticipant(serverMessages) {
  const intro = chats["chat-a"].messages[0];
  const mappedMessages = serverMessages.map((message) => ({
    role: message.sender === "participant" ? "user" : "assistant",
    content: message.content
  }));

  chats["chat-a"].messages = [intro, ...mappedMessages];
  renderMessages("chat-a");
}

async function refreshHumanChat() {
  try {
    const response = await fetch("/api/chat/human/messages");
    const payload = await response.json();

    if (!response.ok) {
      throw new Error(payload.error || "No se pudo actualizar el chat humano.");
    }

    mapHumanMessagesForParticipant(payload.messages || []);
  } catch (error) {
    const intro = chats["chat-a"].messages[0];
    chats["chat-a"].messages = [
      intro,
      {
        role: "system",
        content: `Error: ${error.message}`
      }
    ];
    renderMessages("chat-a");
  }
}

async function sendHumanMessage(userText) {
  setFormBusy("chat-a", true);

  try {
    const response = await fetch("/api/chat/human/send", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        sender: "participant",
        content: userText
      })
    });

    const payload = await response.json();

    if (!response.ok) {
      throw new Error(payload.error || "No se pudo enviar el mensaje al operador humano.");
    }

    mapHumanMessagesForParticipant(payload.messages || []);
  } catch (error) {
    const intro = chats["chat-a"].messages[0];
    chats["chat-a"].messages = [
      ...chats["chat-a"].messages,
      {
        role: "system",
        content: `Error: ${error.message}`
      }
    ];
    renderMessages("chat-a");
  } finally {
    setFormBusy("chat-a", false);
  }
}

async function sendAzureMessage(userText) {
  const chat = chats["chat-b"];
  chat.messages.push({ role: "user", content: userText });
  renderMessages("chat-b");
  setFormBusy("chat-b", true, "Pensando...");

  try {
    const response = await fetch(chat.endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        messages: chat.messages.filter((message) => message.role !== "system")
      })
    });

    const payload = await response.json();

    if (!response.ok) {
      throw new Error(payload.error || "No se pudo obtener respuesta del servidor.");
    }

    chat.messages.push({ role: "assistant", content: payload.reply });
  } catch (error) {
    chat.messages.push({
      role: "system",
      content: `Error: ${error.message}`
    });
  } finally {
    setFormBusy("chat-b", false);
    renderMessages("chat-b");
  }
}

document.querySelectorAll("[data-chat-form]").forEach((form) => {
  form.addEventListener("submit", async (event) => {
    event.preventDefault();

    const chatId = form.dataset.chatForm;
    const textarea = form.querySelector("textarea");
    const userText = textarea.value.trim();

    if (!userText) {
      return;
    }

    textarea.value = "";

    if (chatId === "chat-a") {
      await sendHumanMessage(userText);
      return;
    }

    await sendAzureMessage(userText);
  });
});

saveGuessButton.addEventListener("click", () => {
  if (!guessSelect.value) {
    guessStatus.textContent = "Selecciona un chat antes de guardar tu conclusion.";
    return;
  }

  const selectedChat = guessSelect.value === "chat-a" ? "Chat A" : "Chat B";
  const savedAt = new Date().toLocaleString("es-MX");

  localStorage.setItem("turing-test-guess", JSON.stringify({
    selectedChat,
    savedAt
  }));

  guessStatus.textContent = `Conclusion guardada: ${selectedChat} (${savedAt}).`;
});

const previousGuess = localStorage.getItem("turing-test-guess");
if (previousGuess) {
  const parsedGuess = JSON.parse(previousGuess);
  guessStatus.textContent = `Ultima conclusion guardada: ${parsedGuess.selectedChat} (${parsedGuess.savedAt}).`;
}

Object.keys(chats).forEach(renderMessages);
refreshHumanChat();
window.setInterval(refreshHumanChat, 2000);
