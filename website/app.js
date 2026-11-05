const conversations = [
  {
    id: "maya",
    name: "Maya Chen",
    initial: "M",
    network: "instagram",
    networkName: "Instagram",
    preview: "Saturday. Our usual spot?",
    time: "now",
    unread: 0,
    messages: [
      { side: "received", text: "Coffee and a very long catch-up?" },
      { side: "sent", text: "My two favorite things ☕" },
      { side: "received", text: "Saturday. Our usual spot?" },
      { side: "sent", text: "Wouldn’t miss it." },
    ],
  },
  {
    id: "weekend",
    name: "Weekend club",
    initial: "W",
    network: "whatsapp",
    networkName: "WhatsApp",
    preview: "A very good plan, actually.",
    time: "2m",
    unread: 2,
    messages: [
      { side: "received", text: "A whole Saturday with absolutely no plans?" },
      { side: "sent", text: "I have one tiny suggestion…" },
      { side: "sent", postcard: true },
      { side: "received", text: "A very good plan, actually." },
    ],
  },
  {
    id: "dad",
    name: "Dad",
    initial: "D",
    network: "imessage",
    networkName: "iMessage",
    preview: "Saved you the last slice 🍰",
    time: "12m",
    unread: 0,
    messages: [
      { side: "received", text: "Made your favorite cake." },
      { side: "sent", text: "This is excellent news." },
      { side: "received", text: "Saved you the last slice 🍰" },
      { side: "sent", text: "On my way. Don’t let it out of your sight." },
    ],
  },
  {
    id: "studio",
    name: "Studio pals",
    initial: "S",
    network: "telegram",
    networkName: "Telegram",
    preview: "Same time tomorrow?",
    time: "25m",
    unread: 1,
    messages: [
      { side: "received", text: "Today was a good one." },
      { side: "sent", text: "Good ideas. Even better company." },
      { side: "received", text: "Same time tomorrow?" },
      { side: "sent", text: "You bring the ideas. I’ll bring the snacks." },
    ],
  },
  {
    id: "alex",
    name: "Alex Rivera",
    initial: "A",
    network: "messenger",
    networkName: "Messenger",
    preview: "This reminded me of you ✳",
    time: "38m",
    unread: 2,
    messages: [
      { side: "received", text: "Walked past our old bookshop today." },
      { side: "sent", text: "Is the little orange cat still there?" },
      { side: "received", text: "Still asleep in exactly the same spot." },
      { side: "received", text: "This reminded me of you ✳" },
    ],
  },
];

const state = { network: "all", scope: "all", query: "", selected: "maya" };
const list = document.querySelector("#conversation-list");
const pane = document.querySelector("#chat-pane");
const heading = pane.querySelector(".chat-heading");
const messageList = document.querySelector("#chat-messages");
const composer = document.querySelector("#demo-composer");
const messageInput = document.querySelector("#demo-message");
const search = document.querySelector("#conversation-search");
const announcement = document.querySelector("#demo-announcement");
const networkButtons = [...document.querySelectorAll("[data-network]")];
const scopeButtons = [...document.querySelectorAll("[data-scope]")];
const appearanceButtons = [...document.querySelectorAll(".theme-swatch")];
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function platformImage(network) {
  const image = document.createElement("img");
  image.src = `assets/platforms/${network}.svg`;
  image.alt = "";
  image.width = 10;
  image.height = 10;
  return image;
}

function avatar(conversation) {
  return element("span", `avatar avatar-${conversation.id}`, conversation.initial);
}

function filteredConversations() {
  return conversations.filter((conversation) =>
    (state.network === "all" || conversation.network === state.network) &&
    (state.scope === "all" || conversation.unread > 0) &&
    conversation.name.toLowerCase().includes(state.query.toLowerCase().trim())
  );
}

function renderList() {
  const visible = filteredConversations();
  list.replaceChildren();
  document.querySelector("#inbox-count").textContent = visible.reduce((total, conversation) => total + conversation.unread, 0);

  if (visible.length === 0) {
    list.append(element("p", "empty-conversations", "No one here. Try another name or filter."));
    return;
  }

  for (const conversation of visible) {
    const row = element("button", "conversation-row");
    row.type = "button";
    row.classList.toggle("is-selected", conversation.id === state.selected);
    row.setAttribute("aria-pressed", String(conversation.id === state.selected));
    row.setAttribute("aria-label", `${conversation.name}, ${conversation.networkName}${conversation.unread ? `, ${conversation.unread} unread` : ""}`);
    const portrait = element("span", "row-avatar");
    const platform = element("span", "platform-dot");
    platform.append(platformImage(conversation.network));
    portrait.append(avatar(conversation), platform);
    const copy = element("span", "row-copy");
    copy.append(element("span", "row-name", conversation.name), element("span", "row-preview", conversation.preview));
    const meta = element("span", "row-meta");
    meta.append(element("span", "row-time", conversation.time));
    if (conversation.unread > 0) meta.append(element("span", "row-unread", conversation.unread));
    row.append(portrait, copy, meta);
    row.addEventListener("click", () => {
      state.selected = conversation.id;
      for (const button of list.querySelectorAll("button")) {
        const selected = button === row;
        button.classList.toggle("is-selected", selected);
        button.setAttribute("aria-pressed", String(selected));
      }
      renderChat();
      announcement.textContent = `Previewing ${conversation.name} on ${conversation.networkName}.`;
    });
    list.append(row);
  }
}

function postcard() {
  const card = element("div", "postcard");
  card.append(element("small", "", "You’re invited to"), element("span", "", "a little offline time."));
  const star = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  star.classList.add("postcard-star");
  star.setAttribute("aria-hidden", "true");
  const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
  use.setAttribute("href", "#asterisk");
  star.append(use);
  card.append(star);
  return card;
}

function renderMessages(conversation, animateLast = false) {
  messageList.replaceChildren(element("p", "chat-day", "Today"));
  for (const [index, message] of conversation.messages.entries()) {
    const bubble = element("div", `message ${message.side}`);
    if (message.postcard) {
      bubble.classList.add("message-postcard");
      bubble.append(postcard());
    } else {
      bubble.textContent = message.text;
    }
    if (animateLast && index === conversation.messages.length - 1) bubble.classList.add("just-sent");
    messageList.append(bubble);
  }
  const last = conversation.messages[conversation.messages.length - 1];
  if (last.side === "sent") {
    messageList.append(element("p", "message-receipt", last.demo ? "Demo reply · only in this tab" : "Delivered ✓✓"));
  }
  messageList.scrollTop = messageList.scrollHeight;
}

function renderChat() {
  const conversation = conversations.find((item) => item.id === state.selected);
  heading.replaceChildren();
  messageList.replaceChildren();
  messageInput.disabled = !conversation;
  composer.querySelector("button").disabled = !conversation;

  if (!conversation) {
    heading.append(element("h3", "", "A little quiet here."));
    messageList.append(element("p", "empty-conversations", "Find a friend in the inbox to keep the conversation going."));
    return;
  }

  const title = element("div");
  const network = element("span", "chat-network");
  network.append(platformImage(conversation.network), document.createTextNode(conversation.networkName));
  title.append(element("h3", "", conversation.name), network);
  const star = element("span", "chat-star", "☆");
  star.setAttribute("aria-hidden", "true");
  heading.append(avatar(conversation), title, star);
  renderMessages(conversation);
}

function updateFilters() {
  const visible = filteredConversations();
  if (!visible.some((conversation) => conversation.id === state.selected)) {
    state.selected = visible.length ? visible[0].id : null;
  }
  for (const button of networkButtons) {
    const selected = button.dataset.network === state.network;
    button.classList.toggle("is-active", selected);
    button.setAttribute("aria-pressed", String(selected));
  }
  for (const button of scopeButtons) {
    const selected = button.dataset.scope === state.scope;
    button.classList.toggle("is-active", selected);
    button.setAttribute("aria-pressed", String(selected));
  }
  renderList();
  renderChat();
  announcement.textContent = `${visible.length} example conversation${visible.length === 1 ? "" : "s"} shown.`;
}

for (const button of networkButtons) {
  button.addEventListener("click", () => {
    state.network = button.dataset.network;
    state.scope = "all";
    state.query = "";
    search.value = "";
    updateFilters();
  });
}

for (const button of scopeButtons) {
  button.addEventListener("click", () => {
    state.scope = button.dataset.scope;
    updateFilters();
  });
}

search.addEventListener("input", () => {
  state.query = search.value;
  updateFilters();
});

composer.addEventListener("submit", (event) => {
  event.preventDefault();
  const text = messageInput.value.trim();
  if (!text) {
    messageInput.setCustomValidity("Say a little something first.");
    messageInput.reportValidity();
    return;
  }
  const conversation = conversations.find((item) => item.id === state.selected);
  conversation.messages.push({ side: "sent", text, demo: true });
  conversation.preview = `You: ${text}`;
  conversation.time = "now";
  renderList();
  renderMessages(conversation, true);
  messageInput.value = "";
  messageInput.focus({ preventScroll: true });
  announcement.textContent = "Demo reply added. Nothing was sent to a network.";
});

messageInput.addEventListener("input", () => messageInput.setCustomValidity(""));

for (const button of appearanceButtons) {
  button.addEventListener("click", () => {
    const appearance = button.dataset.appearance;
    document.querySelector(".app-window").dataset.appearance = appearance;
    document.querySelector("#appearance-name").textContent = appearance === "dark" ? "Dark" : "Light";
    for (const swatch of appearanceButtons) {
      const selected = swatch === button;
      swatch.classList.toggle("is-active", selected);
      swatch.setAttribute("aria-pressed", String(selected));
    }
    applyPalette(manualPalette ?? currentTheme);
  });
}

const themes = [
  { id: "classic", name: "Classic", background: "#181818", accent: "#eeeeee", logo: "#ffffff" },
  { id: "grapeSoda", name: "Grape Soda", background: "#4B2A6E", accent: "#8E5CE6", logo: "#F25CA2" },
  { id: "nightSwim", name: "Night Swim", background: "#102A43", accent: "#3A86FF", logo: "#00C2D1" },
  { id: "matcha", name: "Matcha", background: "#2E4A36", accent: "#4CA36B", logo: "#A7D49B" },
  { id: "sunset", name: "Sunset", background: "#5A1E33", accent: "#F26A3D", logo: "#FFB238" },
  { id: "toast", name: "Toast", background: "#3B2A20", accent: "#D9893B", logo: "#F4E3C1" },
  { id: "arcade", name: "Arcade", background: "#14111F", accent: "#00C27A", logo: "#FF3EA5" },
  { id: "bubblegum", name: "Bubblegum", background: "#F9D3E5", accent: "#E2559C", logo: "#5BC0EB" },
  { id: "lemonade", name: "Lemonade", background: "#FFF1A8", accent: "#E3A600", logo: "#2F9E44" },
  { id: "mintChip", name: "Mint Chip", background: "#D8F3E8", accent: "#0E9F6E", logo: "#3B2A20" },
];

const root = document.documentElement;
const hero = document.querySelector(".hero");
const product = document.querySelector(".product");
const privacy = document.querySelector(".privacy");
const closing = document.querySelector(".closing");
const appWindow = document.querySelector(".app-window");
let currentTheme = themes[0];
let manualPalette = null;
let sceneStops = [];
let sceneFrame = 0;
let colorProgress = 0;

function rgb(hex) {
  return [1, 3, 5].map((start) => parseInt(hex.slice(start, start + 2), 16));
}

function blend(a, b, fraction) {
  return a.map((channel, index) => Math.round(channel + (b[index] - channel) * fraction));
}

function cssColor(channels) {
  return `rgb(${channels.join(", ")})`;
}

function luminance(channels) {
  const linear = channels.map((channel) => {
    const value = channel / 255;
    return value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
  });
  return linear[0] * .2126 + linear[1] * .7152 + linear[2] * .0722;
}

function contrast(a, b) {
  const values = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (values[0] + .05) / (values[1] + .05);
}

function readableInk(...surfaces) {
  const light = [255, 255, 255];
  const dark = [0, 0, 0];
  return Math.min(...surfaces.map((surface) => contrast(light, surface))) >= Math.min(...surfaces.map((surface) => contrast(dark, surface))) ? light : dark;
}

function clamp(value) {
  return Math.min(1, Math.max(0, value));
}

function gradient(theme) {
  const top = rgb(theme.background);
  const bottom = theme.id === "classic" ? top : blend(top, rgb(luminance(top) > .4 ? theme.logo : theme.accent), .27);
  return { top, bottom, accent: rgb(theme.accent) };
}

function readableGradient(top, bottom) {
  let ink = readableInk(top, bottom);
  const center = blend(top, bottom, .5);
  if (Math.min(contrast(ink, top), contrast(ink, bottom)) < 4.5) {
    ink = readableInk(center);
    let low = 0;
    let high = 1;
    for (let step = 0; step < 10; step++) {
      const amount = (low + high) / 2;
      const score = Math.min(contrast(ink, blend(top, center, amount)), contrast(ink, blend(bottom, center, amount)));
      if (score >= 4.5) high = amount;
      else low = amount;
    }
    top = blend(top, center, high);
    bottom = blend(bottom, center, high);
  }
  return { top, bottom, ink };
}

function applyPalette(theme) {
  appWindow.dataset.palette = theme.id;
  const dark = appWindow.dataset.appearance === "dark";
  const base = dark ? [40, 40, 40] : [248, 248, 248];
  const classic = theme.id === "classic";
  const rail = classic ? (dark ? [36, 36, 36] : [237, 237, 237]) : rgb(theme.background);
  const accent = classic ? (dark ? [234, 234, 234] : [41, 41, 41]) : rgb(theme.accent);
  const logo = classic ? (dark ? [243, 243, 243] : [41, 41, 41]) : rgb(theme.logo);
  const variables = {
    "--app-rail": rail,
    "--app-rail-ink": readableInk(rail),
    "--app-accent": accent,
    "--app-on-accent": readableInk(accent),
    "--app-selection": blend(base, accent, dark ? .22 : .12),
    "--app-logo": logo,
    "--app-on-logo": readableInk(logo),
    "--app-pane": blend(base, rail, .07),
  };
  for (const [name, value] of Object.entries(variables)) appWindow.style.setProperty(name, cssColor(value));
  document.querySelector("#palette-name").textContent = theme.name;
  for (const button of document.querySelectorAll(".palette-swatch")) button.setAttribute("aria-pressed", String(button.dataset.palette === theme.id));
}

const featuredThemes = ["classic", "grapeSoda", "bubblegum", "mintChip", "sunset"];
for (const id of featuredThemes) {
  const theme = themes.find((item) => item.id === id);
  const swatch = element("button", "palette-swatch");
  swatch.type = "button";
  swatch.dataset.palette = id;
  swatch.setAttribute("aria-label", `${theme.name} theme`);
  swatch.setAttribute("aria-pressed", String(id === "classic"));
  swatch.style.setProperty("--palette-background", theme.background);
  swatch.style.setProperty("--palette-logo", theme.logo);
  swatch.append(element("span"));
  swatch.addEventListener("click", () => {
    manualPalette = theme;
    applyPalette(theme);
  });
  document.querySelector("#palette-options").append(swatch);
}

document.querySelector(".surprise-theme").addEventListener("click", (event) => {
  const selected = themes.findIndex((theme) => theme.id === appWindow.dataset.palette);
  manualPalette = themes[(selected + 1) % themes.length];
  applyPalette(manualPalette);
  const rect = event.currentTarget.getBoundingClientRect();
  scatterStars(rect.x + rect.width / 2, rect.y, 8);
});

function measureJourney() {
  const viewport = window.innerHeight;
  const maximum = Math.max(1, document.documentElement.scrollHeight - viewport);
  const stop = (position, id) => ({ position, theme: themes.find((theme) => theme.id === id) });
  sceneStops = [
    stop(0, "classic"),
    stop(hero.offsetHeight * .1, "classic"),
    stop(hero.offsetHeight * .78, "grapeSoda"),
    stop(product.offsetTop + Math.min(product.offsetHeight * .23, viewport * .38), "bubblegum"),
    stop(privacy.offsetTop - viewport * .2, "mintChip"),
    stop(Math.min(closing.offsetTop - viewport * .22, maximum), "sunset"),
  ];
  queueJourney();
}

function updateJourney() {
  const y = window.scrollY;
  const last = sceneStops[sceneStops.length - 1];
  let from = last;
  let to = last;
  for (let index = 1; index < sceneStops.length; index++) {
    if (y <= sceneStops[index].position) {
      from = sceneStops[index - 1];
      to = sceneStops[index];
      break;
    }
  }
  const progress = from === to ? 1 : clamp((y - from.position) / (to.position - from.position));
  const eased = progress * progress * (3 - 2 * progress);
  const start = gradient(from.theme);
  const end = gradient(to.theme);
  const { top, bottom, ink } = readableGradient(blend(start.top, end.top, eased), blend(start.bottom, end.bottom, eased));
  const accent = blend(start.accent, end.accent, eased);
  root.dataset.tone = ink[0] === 255 ? "dark" : "light";
  root.style.setProperty("--scene-top", cssColor(top));
  root.style.setProperty("--scene-bottom", cssColor(bottom));
  root.style.setProperty("--scene-accent", cssColor(accent));
  root.style.setProperty("--ink", cssColor(ink));
  root.style.setProperty("--cream", ink[0] === 255 ? "#181818" : "#f5f5f5");
  root.style.setProperty("--scene-muted", cssColor(blend(ink, blend(top, bottom, .5), .2)));
  root.style.setProperty("--scene-line", `rgba(${ink.join(", ")}, .17)`);
  root.style.setProperty("--scene-wash", `rgba(${ink.join(", ")}, .07)`);
  colorProgress = clamp(y / (hero.offsetHeight * .65));
  const minimumContrast = Math.min(contrast(ink, top), contrast(ink, bottom));
  root.style.setProperty("--scene-glow", (clamp((minimumContrast - 4.8) / 5) * colorProgress * .18).toFixed(3));
  root.style.setProperty("--color-progress", colorProgress.toFixed(3));
  root.style.setProperty("--hero-progress", clamp(y / hero.offsetHeight).toFixed(3));
  root.style.setProperty("--header-shade", clamp(y / 180).toFixed(3));
  if (!reducedMotion.matches) {
    root.style.setProperty("--dot-offset", `${-(y * .04 % 30)}px`);
    root.style.setProperty("--journey-turn", `${y * .045}deg`);
    const rect = appWindow.getBoundingClientRect();
    appWindow.style.setProperty("--preview-tilt", `${(1 - clamp((window.innerHeight - rect.top) / (window.innerHeight * .7))) * 9}deg`);
  }
  const theme = eased < .5 ? from.theme : to.theme;
  if (currentTheme !== theme) {
    currentTheme = theme;
    document.querySelector("#journey-theme").textContent = theme.name;
    if (!manualPalette) applyPalette(theme);
  }
}

function queueJourney() {
  if (sceneFrame) return;
  sceneFrame = requestAnimationFrame(() => {
    sceneFrame = 0;
    updateJourney();
  });
}

window.addEventListener("scroll", queueJourney, { passive: true });
window.addEventListener("resize", measureJourney, { passive: true });
new ResizeObserver(measureJourney).observe(document.querySelector("main"));
document.fonts.ready.then(measureJourney);

const particleLayer = document.querySelector(".joy-particles");
function scatterStars(x, y, count = 16) {
  if (reducedMotion.matches || particleLayer.children.length > 50) return;
  const colors = colorProgress > .05 ? [currentTheme.accent, currentTheme.logo, "#FFF1A8", "#D8F3E8"] : ["#ffffff", "#aaaaaa", "#dddddd"];
  for (let index = 0; index < count; index++) {
    const star = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    star.setAttribute("viewBox", "0 0 100 100");
    star.classList.add("joy-star");
    const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
    use.setAttribute("href", "#asterisk");
    star.append(use);
    star.style.color = colors[index % colors.length];
    particleLayer.append(star);
    const angle = index / count * Math.PI * 2;
    const distance = 65 + Math.random() * 100;
    const animation = star.animate([
      { transform: `translate(${x - 9}px, ${y - 9}px) scale(.25) rotate(0deg)`, opacity: 1 },
      { transform: `translate(${x + Math.cos(angle) * distance}px, ${y + Math.sin(angle) * distance + 35}px) scale(.8) rotate(180deg)`, opacity: .9, offset: .65 },
      { transform: `translate(${x + Math.cos(angle) * distance * 1.2}px, ${y + Math.sin(angle) * distance + 100}px) scale(.1) rotate(280deg)`, opacity: 0 },
    ], { duration: 900 + Math.random() * 350, easing: "cubic-bezier(.15,.65,.3,1)" });
    animation.finished.then(() => star.remove());
  }
}

let toastTimer;
function showJoy(message) {
  const toast = document.querySelector(".joy-toast");
  clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.add("is-visible");
  toastTimer = setTimeout(() => toast.classList.remove("is-visible"), 2800);
}

let logoTurns = 0;
const brandMark = document.querySelector(".brand-spin svg");
document.querySelector(".brand-spin").addEventListener("click", (event) => {
  logoTurns += 360;
  if (!reducedMotion.matches) brandMark.style.transform = `rotate(${logoTurns}deg)`;
  const rect = event.currentTarget.getBoundingClientRect();
  scatterStars(rect.x + rect.width / 2, rect.y + rect.height / 2);
  if (logoTurns >= 1080) showJoy("A little spin goes a long way. ✳");
});

document.querySelector(".hero-plus").addEventListener("click", (event) => {
  const rect = event.currentTarget.getBoundingClientRect();
  scatterStars(rect.x + rect.width / 2, rect.y + rect.height / 2, 24);
  showJoy("A little more joy. Just for you. ✳");
});

const macGreetings = ["oh, hello you.", "good to see you again.", "a little less screen time?", "just between us."];
let macGreeting = 0;
let winkTimer;
document.querySelector(".mac-hello").addEventListener("click", () => {
  const mac = document.querySelector(".mac-illustration");
  document.querySelector(".little-bubble").textContent = macGreetings[macGreeting++ % macGreetings.length];
  mac.classList.remove("is-winking");
  clearTimeout(winkTimer);
  requestAnimationFrame(() => mac.classList.add("is-winking"));
  winkTimer = setTimeout(() => mac.classList.remove("is-winking"), 850);
});

let secretWord = "";
document.addEventListener("keydown", (event) => {
  if (event.target.closest("input, textarea, [contenteditable]") || event.metaKey || event.ctrlKey || event.altKey || event.key.length !== 1) return;
  secretWord = (secretWord + event.key.toLowerCase()).slice(-5);
  if (secretWord === "hello") {
    scatterStars(window.innerWidth / 2, window.innerHeight * .35, 32);
    showJoy("You found the hello club. You’re in. ✳");
    secretWord = "";
  }
});

const logoCursor = document.querySelector(".logo-cursor");
const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)");
let cursorTurn = 0;
let previousPointer = null;
function hideCursor() {
  logoCursor.classList.remove("is-visible");
  document.body.classList.remove("has-logo-cursor");
}

document.addEventListener("pointermove", (event) => {
  if (event.pointerType !== "mouse" || !finePointer.matches) return;
  document.body.classList.add("has-logo-cursor");
  logoCursor.classList.add("is-visible");
  logoCursor.classList.toggle("is-text", Boolean(event.target.closest("input, textarea, [contenteditable]")));
  logoCursor.classList.toggle("is-hovering", Boolean(event.target.closest("a, button, summary")));
  logoCursor.style.transform = `translate3d(${event.clientX - 12}px, ${event.clientY - 12}px, 0)`;
  if (previousPointer && !reducedMotion.matches) cursorTurn += Math.hypot(event.clientX - previousPointer.x, event.clientY - previousPointer.y) * .15;
  logoCursor.style.setProperty("--cursor-turn", `${cursorTurn}deg`);
  previousPointer = { x: event.clientX, y: event.clientY };
}, { passive: true });
document.addEventListener("pointerout", (event) => { if (!event.relatedTarget) hideCursor(); });
window.addEventListener("blur", hideCursor);
finePointer.addEventListener("change", hideCursor);

const entrance = document.querySelector("#entrance");
let entranceTimer;
function finishEntrance() {
  clearTimeout(entranceTimer);
  entrance.hidden = true;
  document.body.classList.remove("intro-playing");
  document.body.classList.add("has-entered");
  document.querySelector("main").inert = false;
  document.querySelector(".site-header").inert = false;
  window.removeEventListener("pointerdown", finishEntrance);
  window.removeEventListener("wheel", finishEntrance);
  window.removeEventListener("keydown", finishEntrance);
}

function playEntrance() {
  if (reducedMotion.matches) {
    finishEntrance();
    return;
  }
  const target = brandMark.getBoundingClientRect();
  const markWidth = window.innerWidth <= 600 ? 90 : 120;
  entrance.style.setProperty("--entrance-x", `${target.x + target.width / 2 - window.innerWidth / 2}px`);
  entrance.style.setProperty("--entrance-y", `${target.y + target.height / 2 - window.innerHeight / 2}px`);
  entrance.style.setProperty("--entrance-scale", target.width / markWidth);
  entrance.hidden = false;
  document.body.classList.remove("has-entered");
  document.body.classList.add("intro-playing");
  document.querySelector("main").inert = true;
  document.querySelector(".site-header").inert = true;
  window.addEventListener("pointerdown", finishEntrance, { once: true });
  window.addEventListener("wheel", finishEntrance, { once: true, passive: true });
  window.addEventListener("keydown", finishEntrance, { once: true });
  entranceTimer = setTimeout(finishEntrance, 1650);
}

document.querySelector(".replay-intro").addEventListener("click", () => {
  window.scrollTo({ top: 0, behavior: "instant" });
  playEntrance();
});

const observer = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (entry.isIntersecting) {
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    }
  }
}, { threshold: .08 });

document.querySelectorAll(".reveal").forEach((node) => observer.observe(node));
document.body.classList.toggle("has-motion", !reducedMotion.matches);
reducedMotion.addEventListener("change", (event) => {
  document.body.classList.toggle("has-motion", !event.matches);
  if (event.matches) {
    finishEntrance();
    for (const animation of particleLayer.getAnimations({ subtree: true })) animation.finish();
  }
  queueJourney();
});

renderList();
renderChat();
applyPalette(currentTheme);
measureJourney();
if (!window.location.hash && window.scrollY < 40) playEntrance();
else finishEntrance();
