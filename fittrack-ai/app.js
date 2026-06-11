const navItems = [
  ["dashboard", "Dashboard", "D"],
  ["meal", "Log Meal", "+"],
  ["photo", "Photo", "P"],
  ["voice", "Voice", "V"],
  ["exercise", "Exercise", "E"],
  ["progress", "Progress", "G"],
  ["insights", "Insights", "I"],
  ["settings", "Settings", "S"],
  ["profile", "Profile", "U"],
];

const bottomItems = ["dashboard", "meal", "exercise", "progress", "insights"];
const storageKey = "fittrack-ai-state";

const foodLibrary = {
  egg: { name: "Boiled egg", quantity: "1 large", calories: 78, protein: 6, carbs: 1, fat: 5 },
  eggs: { name: "Boiled eggs", quantity: "2 large", calories: 156, protein: 12, carbs: 1, fat: 10 },
  toast: { name: "Whole grain toast", quantity: "1 slice", calories: 95, protein: 4, carbs: 17, fat: 1 },
  avocado: { name: "Avocado", quantity: "1/2 medium", calories: 120, protein: 2, carbs: 6, fat: 11 },
  coffee: { name: "Coffee with milk", quantity: "1 cup", calories: 35, protein: 2, carbs: 4, fat: 1 },
  chicken: { name: "Grilled chicken breast", quantity: "150 g", calories: 248, protein: 46, carbs: 0, fat: 5 },
  rice: { name: "Cooked rice", quantity: "1 cup", calories: 205, protein: 4, carbs: 45, fat: 0 },
  salad: { name: "Mixed salad", quantity: "1 bowl", calories: 90, protein: 3, carbs: 12, fat: 4 },
  dal: { name: "Dal", quantity: "1 cup", calories: 180, protein: 11, carbs: 28, fat: 4 },
  paneer: { name: "Paneer", quantity: "100 g", calories: 265, protein: 18, carbs: 4, fat: 20 },
  oats: { name: "Oats", quantity: "1 bowl", calories: 210, protein: 7, carbs: 35, fat: 5 },
  banana: { name: "Banana", quantity: "1 medium", calories: 105, protein: 1, carbs: 27, fat: 0 },
  yogurt: { name: "Greek yogurt", quantity: "170 g", calories: 120, protein: 17, carbs: 7, fat: 0 },
};

const exerciseDefaults = {
  walking: { base: 4 },
  running: { base: 10 },
  cycling: { base: 8 },
  "strength training": { base: 6 },
  yoga: { base: 3 },
  swimming: { base: 9 },
  sports: { base: 7 },
};

let state = loadState();
let activeView = state.user?.onboarded ? "dashboard" : "onboarding";
let pendingEstimate = null;
let authMode = "login";

const $ = (selector) => document.querySelector(selector);
const authScreen = $("#authScreen");
const appContent = $("#appContent");
const todayLabel = $("#todayLabel");
const pageTitle = $("#pageTitle");

function defaultState() {
  return blankState();
}

function blankState(email = "") {
  const user = {
    email,
    name: "",
    age: 30,
    gender: "female",
    heightCm: 165,
    currentWeightKg: 75,
    goalWeightKg: 68,
    activityLevel: "light",
    speed: "moderate",
    dietary: [],
    units: "metric",
    onboarded: false,
  };
  return {
    authed: false,
    demo: false,
    user,
    goals: calculateGoals(user),
    water: 0,
    meals: [],
    exercises: [],
    weights: [],
    photos: [],
    aiEstimates: [],
  };
}

function demoState() {
  const now = new Date();
  const user = {
    email: "maya@example.com",
    name: "Maya",
    age: 32,
    gender: "female",
    heightCm: 165,
    currentWeightKg: 78,
    goalWeightKg: 66,
    activityLevel: "light",
    speed: "moderate",
    dietary: ["high-protein", "non-vegetarian"],
    units: "metric",
    onboarded: true,
  };
  const goals = calculateGoals(user);
  return {
    authed: false,
    demo: true,
    user,
    goals,
    water: 7,
    meals: [
      meal("breakfast", "manual", [
        { ...foodLibrary.eggs },
        { ...foodLibrary.toast },
        { ...foodLibrary.avocado },
      ], hoursAgo(7)),
      meal("lunch", "manual", [
        { ...foodLibrary.chicken },
        { ...foodLibrary.rice },
        { ...foodLibrary.salad },
      ], hoursAgo(2)),
    ],
    exercises: [
      exercise("walking", 35, "moderate", 168, hoursAgo(5)),
      exercise("strength training", 40, "moderate", 240, new Date(now.getTime() - 86400000).toISOString()),
    ],
    weights: [
      weight(80.2, -35),
      weight(79.4, -28),
      weight(78.9, -21),
      weight(78.4, -14),
      weight(78.0, -7),
      weight(77.6, 0),
    ],
    photos: [
      { id: crypto.randomUUID(), caption: "Week 1", loggedAt: daysAgo(-21), color: "#dff6ed" },
      { id: crypto.randomUUID(), caption: "Week 4", loggedAt: daysAgo(0), color: "#e7f0ff" },
    ],
    aiEstimates: [],
  };
}

function isSeededDemo(currentState) {
  return currentState.demo || currentState.meals?.some((entry) =>
    entry.items?.some((item) => item.name === "Grilled chicken breast" || item.name === "Boiled eggs")
  );
}

function loadState() {
  try {
    const parsed = JSON.parse(localStorage.getItem(storageKey));
    if (parsed && isSeededDemo(parsed) && parsed.demo !== true) {
      return blankState(parsed.user?.email || "");
    }
    return parsed || defaultState();
  } catch {
    return defaultState();
  }
}

function saveState() {
  localStorage.setItem(storageKey, JSON.stringify(state));
}

function hoursAgo(hours) {
  return new Date(Date.now() - hours * 3600000).toISOString();
}

function daysAgo(days) {
  return new Date(Date.now() + days * 86400000).toISOString();
}

function meal(type, source, items, loggedAt = new Date().toISOString()) {
  const totals = sumItems(items);
  return { id: crypto.randomUUID(), type, source, items, loggedAt, ...totals };
}

function exercise(type, duration, intensity, calories, loggedAt = new Date().toISOString()) {
  return { id: crypto.randomUUID(), type, duration, intensity, calories, loggedAt };
}

function weight(value, dayOffset) {
  return { id: crypto.randomUUID(), value, loggedAt: daysAgo(dayOffset) };
}

function sumItems(items) {
  return items.reduce((acc, item) => ({
    calories: acc.calories + Number(item.calories || 0),
    protein: acc.protein + Number(item.protein || 0),
    carbs: acc.carbs + Number(item.carbs || 0),
    fat: acc.fat + Number(item.fat || 0),
  }), { calories: 0, protein: 0, carbs: 0, fat: 0 });
}

function calculateGoals(user) {
  const weight = Number(user.currentWeightKg);
  const height = Number(user.heightCm);
  const age = Number(user.age);
  const genderOffset = user.gender === "male" ? 5 : -161;
  const bmr = Math.round(10 * weight + 6.25 * height - 5 * age + genderOffset);
  const activity = { sedentary: 1.2, light: 1.375, moderate: 1.55, active: 1.725, athlete: 1.9 }[user.activityLevel] || 1.375;
  const maintenance = Math.round(bmr * activity);
  const deficitMap = { slow: 0.12, moderate: 0.18, aggressive: 0.24 };
  const deficit = Math.min(Math.round(maintenance * deficitMap[user.speed]), 750);
  const floor = user.gender === "male" ? 1500 : 1200;
  const target = Math.max(maintenance - deficit, floor);
  const weeklyLossKg = Number(((maintenance - target) * 7 / 7700).toFixed(2));
  const protein = Math.round(weight * 1.8);
  const fat = Math.round((target * 0.26) / 9);
  const carbs = Math.max(80, Math.round((target - protein * 4 - fat * 9) / 4));
  return { bmr, maintenance, target, protein, carbs, fat, weeklyLossKg };
}

function todayMeals() {
  return state.meals.filter((entry) => isToday(entry.loggedAt));
}

function todayExercises() {
  return state.exercises.filter((entry) => isToday(entry.loggedAt));
}

function isToday(iso) {
  const date = new Date(iso);
  const now = new Date();
  return date.toDateString() === now.toDateString();
}

function totalsForToday() {
  const meals = todayMeals();
  const food = sumItems(meals.flatMap((entry) => entry.items));
  const exerciseCalories = todayExercises().reduce((sum, entry) => sum + Number(entry.calories), 0);
  return { ...food, exerciseCalories };
}

function init() {
  todayLabel.textContent = new Date().toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });
  renderNav();
  bindAuth();
  if (state.authed) showApp();
  else showAuth();
}

function bindAuth() {
  document.querySelectorAll("[data-auth-tab]").forEach((button) => {
    button.addEventListener("click", () => {
      document.querySelectorAll("[data-auth-tab]").forEach((item) => item.classList.remove("active"));
      button.classList.add("active");
      authMode = button.dataset.authTab;
    });
  });
  $("#authForm").addEventListener("submit", (event) => {
    event.preventDefault();
    const email = $("#authEmail").value.trim();
    if (authMode === "signup") {
      state = blankState(email);
      activeView = "onboarding";
    } else if (email === "maya@example.com") {
      state = demoState();
      state.authed = true;
      activeView = "dashboard";
    } else if (state.user.email !== email || isSeededDemo(state)) {
      state = blankState(email);
      activeView = "onboarding";
    }
    state.authed = true;
    if (authMode === "login") state.user.email = email;
    saveState();
    showApp();
  });
  $("#profileButton").addEventListener("click", () => navigate("profile"));
}

function showAuth() {
  authScreen.classList.remove("hidden");
  appContent.classList.add("hidden");
  $("#bottomNav").classList.add("hidden");
}

function showApp() {
  authScreen.classList.add("hidden");
  appContent.classList.remove("hidden");
  $("#bottomNav").classList.remove("hidden");
  if (!state.user.onboarded) activeView = "onboarding";
  render();
}

function renderNav() {
  const desktop = $("#desktopNav");
  const bottom = $("#bottomNav");
  desktop.innerHTML = navItems.map(navButton).join("");
  bottom.innerHTML = navItems.filter(([id]) => bottomItems.includes(id)).map(navButton).join("");
  document.querySelectorAll(".nav-button").forEach((button) => {
    button.addEventListener("click", () => navigate(button.dataset.view));
  });
}

function navButton([id, label, icon]) {
  return `<button class="nav-button" data-view="${id}"><span class="nav-icon">${icon}</span><span class="nav-label">${label}</span></button>`;
}

function navigate(view) {
  if (view !== "onboarding" && !state.user.onboarded) return;
  activeView = view;
  render();
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function render() {
  document.querySelectorAll(".view").forEach((view) => view.classList.remove("active"));
  document.querySelectorAll(".nav-button").forEach((button) => {
    button.classList.toggle("active", button.dataset.view === activeView);
  });
  const target = $(`#${activeView}View`);
  if (target) target.classList.add("active");
  const label = navItems.find(([id]) => id === activeView)?.[1] || "Onboarding";
  pageTitle.textContent = label;
  renderOnboarding();
  renderDashboard();
  renderMeal();
  renderPhoto();
  renderVoice();
  renderExercise();
  renderProgress();
  renderInsights();
  renderSettings();
  renderProfile();
}

function renderOnboarding() {
  $("#onboardingView").innerHTML = `
    <div class="grid dashboard-grid">
      <form class="card form-grid" id="onboardingForm">
        ${input("Name", "name", state.user.name)}
        ${input("Age", "age", state.user.age, "number")}
        ${select("Gender", "gender", ["female", "male"], state.user.gender)}
        ${select("Units", "units", ["metric", "imperial"], state.user.units)}
        ${input("Height (cm)", "heightCm", state.user.heightCm, "number")}
        ${input("Current weight (kg)", "currentWeightKg", state.user.currentWeightKg, "number")}
        ${input("Goal weight (kg)", "goalWeightKg", state.user.goalWeightKg, "number")}
        ${select("Activity level", "activityLevel", ["sedentary", "light", "moderate", "active", "athlete"], state.user.activityLevel)}
        ${select("Fat-loss speed", "speed", ["slow", "moderate", "aggressive"], state.user.speed)}
        <label class="full">Dietary preferences
          <input name="dietary" value="${state.user.dietary.join(", ")}" placeholder="vegetarian, high-protein" />
        </label>
        <button class="primary-action full" type="submit">Calculate my target</button>
      </form>
      <div class="card" id="caloriePreview">${caloriePreview(state.goals)}</div>
    </div>
  `;
  $("#onboardingForm").addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    state.user = {
      ...state.user,
      name: data.get("name"),
      age: Number(data.get("age")),
      gender: data.get("gender"),
      units: data.get("units"),
      heightCm: Number(data.get("heightCm")),
      currentWeightKg: Number(data.get("currentWeightKg")),
      goalWeightKg: Number(data.get("goalWeightKg")),
      activityLevel: data.get("activityLevel"),
      speed: data.get("speed"),
      dietary: String(data.get("dietary")).split(",").map((item) => item.trim()).filter(Boolean),
      onboarded: true,
    };
    state.goals = calculateGoals(state.user);
    state.weights.push(weight(state.user.currentWeightKg, 0));
    saveState();
    navigate("dashboard");
  });
}

function input(label, name, value, type = "text") {
  return `<label>${label}<input name="${name}" type="${type}" value="${value}" required /></label>`;
}

function select(label, name, options, value) {
  return `<label>${label}<select name="${name}">${options.map((option) => `<option value="${option}" ${option === value ? "selected" : ""}>${title(option)}</option>`).join("")}</select></label>`;
}

function caloriePreview(goals) {
  return `
    <p class="eyebrow">Calorie plan</p>
    <h2>Safe fat-loss target</h2>
    <div class="metric-grid" style="margin-top:16px">
      <div class="metric"><span>BMR</span><strong>${goals.bmr}</strong></div>
      <div class="metric"><span>Maintenance</span><strong>${goals.maintenance}</strong></div>
      <div class="metric"><span>Target</span><strong>${goals.target}</strong></div>
    </div>
    <div class="macro-list" style="margin-top:18px">
      ${macroRow("Protein", goals.protein, "g", 72)}
      ${macroRow("Carbs", goals.carbs, "g", 58, "var(--blue)")}
      ${macroRow("Fat", goals.fat, "g", 44, "var(--amber)")}
    </div>
    <p class="muted" style="margin-top:16px">Estimated weekly weight-loss rate: ${goals.weeklyLossKg} kg/week.</p>
  `;
}

function renderDashboard() {
  const totals = totalsForToday();
  const remaining = Math.round(state.goals.target - totals.calories + totals.exerciseCalories);
  const adherence = adherenceScore(totals);
  $("#dashboardView").innerHTML = `
    <div class="grid dashboard-grid">
      <div class="card hero-card">
        <div class="calorie-ring" style="--ring:${Math.min(totals.calories / state.goals.target * 100, 100)}%">
          <div class="ring-content"><div><strong>${Math.round(totals.calories)}</strong><span class="muted">of ${state.goals.target} kcal</span></div></div>
        </div>
        <div>
          <p class="eyebrow">Today</p>
          <h2>${remaining >= 0 ? remaining : Math.abs(remaining)} calories ${remaining >= 0 ? "remaining" : "over target"}</h2>
          <p class="muted" style="margin-top:8px">Exercise adds ${totals.exerciseCalories} kcal back. Estimates are useful, but consistency matters most.</p>
          <div class="metric-grid" style="margin-top:18px">
            <div class="metric"><span>Water</span><strong>${state.water}/10</strong></div>
            <div class="metric"><span>Streak</span><strong>${streak()} days</strong></div>
            <div class="metric"><span>Adherence</span><strong>${adherence}%</strong></div>
          </div>
        </div>
      </div>
      <div class="card">
        <div class="section-heading"><h2>Quick log</h2><span class="chip">MVP</span></div>
        <div class="quick-actions">
          <button class="quick-action" data-jump="meal">Log Meal<span>Manual food entry</span></button>
          <button class="quick-action" data-jump="exercise">Log Exercise<span>Duration and burn</span></button>
          <button class="quick-action" data-jump="photo">Upload Photo<span>AI estimate placeholder</span></button>
          <button class="quick-action" data-jump="voice">Voice Meal<span>Speech or typed log</span></button>
        </div>
      </div>
      <div class="card">
        <div class="section-heading"><h2>Macros</h2><span class="muted">${Math.round(totals.protein)}g protein</span></div>
        <div class="macro-list">
          ${macroProgress("Protein", totals.protein, state.goals.protein, "var(--green)")}
          ${macroProgress("Carbs", totals.carbs, state.goals.carbs, "var(--blue)")}
          ${macroProgress("Fat", totals.fat, state.goals.fat, "var(--amber)")}
        </div>
      </div>
      <div class="card">
        <div class="section-heading"><h2>Weight progress</h2><span class="chip">${goalPercent()}%</span></div>
        ${weightLineChart()}
        <p class="muted">Current ${latestWeight()} kg / Goal ${state.user.goalWeightKg} kg / Weekly calorie average ${weeklyAverage()} kcal.</p>
      </div>
    </div>
  `;
  document.querySelectorAll("[data-jump]").forEach((button) => button.addEventListener("click", () => navigate(button.dataset.jump)));
}

function macroProgress(label, value, target, color) {
  return `
    <div class="macro-row">
      <span>${label}</span>
      <div class="progress-track"><div class="progress-fill" style="width:${Math.min(value / target * 100, 100)}%; background:${color}"></div></div>
      <strong>${Math.round(value)}/${target}g</strong>
    </div>`;
}

function macroRow(label, value, unit, percent, color = "var(--green)") {
  return `
    <div class="macro-row">
      <span>${label}</span>
      <div class="progress-track"><div class="progress-fill" style="width:${percent}%; background:${color}"></div></div>
      <strong>${value}${unit}</strong>
    </div>`;
}

function renderMeal() {
  $("#mealView").innerHTML = `
    <div class="grid dashboard-grid">
      <form class="card form-grid" id="mealForm">
        ${input("Food name", "name", "Greek yogurt")}
        ${input("Quantity", "quantity", "170 g")}
        ${input("Calories", "calories", 120, "number")}
        ${input("Protein (g)", "protein", 17, "number")}
        ${input("Carbs (g)", "carbs", 7, "number")}
        ${input("Fat (g)", "fat", 0, "number")}
        ${select("Meal type", "type", ["breakfast", "lunch", "dinner", "snack"], "snack")}
        <label>Time logged<input name="loggedAt" type="datetime-local" value="${localDateTime()}" /></label>
        <button class="primary-action full" type="submit">Save meal</button>
      </form>
      <div class="card">
        <div class="section-heading"><h2>Today's meals</h2><span class="chip">${todayMeals().length} logs</span></div>
        <div class="meal-list">${mealRows(todayMeals())}</div>
      </div>
    </div>
  `;
  $("#mealForm").addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const item = itemFromForm(data);
    state.meals.unshift(meal(data.get("type"), "manual", [item], new Date(data.get("loggedAt")).toISOString()));
    saveState();
    render();
  });
}

function itemFromForm(data) {
  return {
    name: data.get("name"),
    quantity: data.get("quantity"),
    calories: Number(data.get("calories")),
    protein: Number(data.get("protein")),
    carbs: Number(data.get("carbs")),
    fat: Number(data.get("fat")),
  };
}

function mealRows(meals) {
  if (!meals.length) return `<p class="muted">No meals logged yet today.</p>`;
  return meals.map((entry) => `
    <div class="log-row">
      <div>
        <h3>${title(entry.type)} / ${entry.items.map((item) => item.name).join(", ")}</h3>
        <p class="muted">${new Date(entry.loggedAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} / ${entry.source}</p>
      </div>
      <strong>${Math.round(entry.calories)} kcal</strong>
    </div>`).join("");
}

function renderPhoto() {
  $("#photoView").innerHTML = `
    <div class="grid dashboard-grid">
      <div class="card">
        <div class="section-heading"><div><p class="eyebrow">AI photo upload</p><h2>Estimate from a meal photo</h2></div></div>
        <label class="upload-zone" for="photoInput" id="uploadZone">
          <span><strong>Choose a meal photo</strong><br><span class="muted">This MVP generates a realistic editable estimate.</span></span>
          <input class="hidden" id="photoInput" type="file" accept="image/*" />
        </label>
        <button class="primary-action" id="analyzePhoto" type="button" style="margin-top:14px">Analyze photo</button>
      </div>
      <div id="photoEstimate"></div>
    </div>
  `;
  $("#photoInput").addEventListener("change", (event) => {
    const file = event.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      $("#uploadZone").innerHTML = `<img alt="Uploaded meal preview" src="${reader.result}" />`;
    };
    reader.readAsDataURL(file);
  });
  $("#analyzePhoto").addEventListener("click", () => {
    pendingEstimate = {
      source: "photo",
      confidence: 0.78,
      items: [
        { name: "Grilled chicken breast", quantity: "140 g", calories: 230, protein: 42, carbs: 0, fat: 5 },
        { name: "Rice", quantity: "3/4 cup", calories: 155, protein: 3, carbs: 34, fat: 0 },
        { name: "Vegetables", quantity: "1 cup", calories: 85, protein: 3, carbs: 14, fat: 2 },
      ],
    };
    $("#photoEstimate").innerHTML = confirmationHtml(pendingEstimate);
    bindEstimateSave("photoEstimate");
  });
}

function renderVoice() {
  $("#voiceView").innerHTML = `
    <div class="grid dashboard-grid">
      <div class="card voice-box">
        <div class="section-heading"><div><p class="eyebrow">Voice meal logging</p><h2>Say or type what you ate</h2></div></div>
        <textarea id="voiceText">I had two boiled eggs, one slice of toast, half an avocado, and coffee with milk.</textarea>
        <div class="quick-actions">
          <button class="secondary-action" id="startVoice" type="button">Start voice</button>
          <button class="primary-action" id="parseVoice" type="button">Parse meal</button>
        </div>
        <p class="muted">Speech recognition uses the browser when available. The estimate is always editable before saving.</p>
      </div>
      <div id="voiceEstimate"></div>
    </div>
  `;
  $("#startVoice").addEventListener("click", startSpeech);
  $("#parseVoice").addEventListener("click", () => {
    const text = $("#voiceText").value.toLowerCase();
    const items = parseVoiceMeal(text);
    pendingEstimate = { source: "voice", confidence: 0.82, rawInput: text, items };
    $("#voiceEstimate").innerHTML = confirmationHtml(pendingEstimate);
    bindEstimateSave("voiceEstimate");
  });
}

function parseVoiceMeal(text) {
  const found = Object.keys(foodLibrary)
    .filter((key) => text.includes(key))
    .map((key) => ({ ...foodLibrary[key] }));
  return found.length ? found : [{ name: "Mixed meal", quantity: "1 serving", calories: 420, protein: 24, carbs: 42, fat: 16 }];
}

function startSpeech() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    $("#voiceText").value = "Speech recognition is not available in this browser. Type the meal here instead.";
    return;
  }
  const recognition = new SpeechRecognition();
  recognition.lang = "en-US";
  recognition.onresult = (event) => {
    $("#voiceText").value = event.results[0][0].transcript;
  };
  recognition.start();
}

function confirmationHtml(estimate) {
  const totals = sumItems(estimate.items);
  return `
    <div class="confirmation-card">
      <div class="section-heading">
        <div><p class="eyebrow">Review estimate</p><h2>Confirm before saving</h2></div>
        <span class="confidence-pill">${Math.round(estimate.confidence * 100)}% confidence</span>
      </div>
      <p class="muted">AI calorie estimates are approximate. Adjust the detected foods and portions before adding this meal.</p>
      <div class="estimate-list" style="margin-top:14px">
        ${estimate.items.map((item, index) => estimateRow(item, index)).join("")}
      </div>
      <p class="muted" style="margin-top:12px">Estimated total: ${Math.round(totals.calories)} kcal / ${Math.round(totals.protein)}g protein / ${Math.round(totals.carbs)}g carbs / ${Math.round(totals.fat)}g fat</p>
      <button class="primary-action save-estimate" type="button" style="margin-top:14px">Save confirmed meal</button>
    </div>
  `;
}

function estimateRow(item, index) {
  return `
    <div class="estimate-row form-grid" data-estimate-row="${index}">
      ${input("Food", "name", item.name)}
      ${input("Quantity", "quantity", item.quantity)}
      ${input("Calories", "calories", item.calories, "number")}
      ${input("Protein", "protein", item.protein, "number")}
      ${input("Carbs", "carbs", item.carbs, "number")}
      ${input("Fat", "fat", item.fat, "number")}
    </div>`;
}

function bindEstimateSave(containerId) {
  $(`#${containerId} .save-estimate`).addEventListener("click", () => {
    const items = [...document.querySelectorAll(`#${containerId} [data-estimate-row]`)].map((row) => {
      const data = new FormData();
      row.querySelectorAll("input").forEach((inputEl) => data.set(inputEl.name, inputEl.value));
      return itemFromForm(data);
    });
    const savedMeal = meal("snack", pendingEstimate.source, items);
    state.meals.unshift(savedMeal);
    state.aiEstimates.unshift({
      id: crypto.randomUUID(),
      source: pendingEstimate.source,
      rawInput: pendingEstimate.rawInput || "",
      detectedFoods: items,
      confidence: pendingEstimate.confidence,
      reviewedByUser: true,
      mealId: savedMeal.id,
      createdAt: new Date().toISOString(),
    });
    saveState();
    navigate("dashboard");
  });
}

function renderExercise() {
  $("#exerciseView").innerHTML = `
    <div class="grid dashboard-grid">
      <form class="card form-grid" id="exerciseForm">
        ${select("Exercise type", "type", Object.keys(exerciseDefaults), "walking")}
        ${input("Duration (minutes)", "duration", 30, "number")}
        ${select("Intensity", "intensity", ["easy", "moderate", "hard"], "moderate")}
        ${input("Calories burned", "calories", 145, "number")}
        <label class="full">Date and time<input name="loggedAt" type="datetime-local" value="${localDateTime()}" /></label>
        <button class="secondary-action" id="estimateBurn" type="button">Estimate burn</button>
        <button class="primary-action" type="submit">Save exercise</button>
      </form>
      <div class="card">
        <div class="section-heading"><h2>Exercise log</h2><span class="chip">${todayExercises().reduce((sum, item) => sum + item.calories, 0)} kcal today</span></div>
        <div class="exercise-list">${exerciseRows(state.exercises.slice(0, 8))}</div>
      </div>
    </div>
  `;
  $("#estimateBurn").addEventListener("click", () => {
    const form = $("#exerciseForm");
    const type = form.type.value;
    const duration = Number(form.duration.value);
    const multiplier = { easy: 0.78, moderate: 1, hard: 1.28 }[form.intensity.value];
    form.calories.value = Math.round(exerciseDefaults[type].base * duration * multiplier);
  });
  $("#exerciseForm").addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    state.exercises.unshift(exercise(data.get("type"), Number(data.get("duration")), data.get("intensity"), Number(data.get("calories")), new Date(data.get("loggedAt")).toISOString()));
    saveState();
    render();
  });
}

function exerciseRows(entries) {
  if (!entries.length) return `<p class="muted">No exercise logged yet.</p>`;
  return entries.map((entry) => `
    <div class="log-row">
      <div><h3>${title(entry.type)}</h3><p class="muted">${entry.duration} min / ${title(entry.intensity)} / ${new Date(entry.loggedAt).toLocaleDateString()}</p></div>
      <strong>${entry.calories} kcal</strong>
    </div>`).join("");
}

function renderProgress() {
  const caloriesByDay = lastSevenDays((date) => caloriesForDate(date));
  const proteinByDay = lastSevenDays((date) => proteinForDate(date));
  const exerciseByDay = lastSevenDays((date) => exerciseForDate(date));
  $("#progressView").innerHTML = `
    <div class="grid">
      <div class="grid dashboard-grid">
        <div class="card chart-card"><div class="section-heading"><h2>Weight trend</h2><span class="chip">${goalPercent()}% complete</span></div>${weightLineChart()}</div>
        <div class="card chart-card"><div class="section-heading"><h2>Calorie intake</h2><span class="muted">7 days</span></div>${barChart(caloriesByDay, state.goals.target)}</div>
        <div class="card chart-card"><div class="section-heading"><h2>Protein intake</h2><span class="muted">Goal ${state.goals.protein}g</span></div>${barChart(proteinByDay, state.goals.protein, "var(--green)")}</div>
        <div class="card chart-card"><div class="section-heading"><h2>Exercise</h2><span class="muted">Calories burned</span></div>${barChart(exerciseByDay, 300, "var(--amber)")}</div>
      </div>
      <div class="grid dashboard-grid">
        <div class="card">
          <div class="section-heading"><h2>Body measurements</h2><span class="chip">Sample</span></div>
          <div class="metric-grid">
            <div class="metric"><span>Waist</span><strong>84 cm</strong></div>
            <div class="metric"><span>Hips</span><strong>101 cm</strong></div>
            <div class="metric"><span>Chest</span><strong>94 cm</strong></div>
          </div>
        </div>
        <div class="card">
          <div class="section-heading"><h2>Progress photos</h2><span class="muted">Private</span></div>
          <div class="photo-grid">${state.photos.map((photo) => `<div class="photo-tile" style="background:${photo.color}"><strong>${photo.caption}</strong><p class="muted">${new Date(photo.loggedAt).toLocaleDateString()}</p></div>`).join("")}</div>
        </div>
      </div>
      <div class="card"><div class="section-heading"><h2>Weekly summary</h2><span class="chip">${weeklyAverage()} kcal avg</span></div><p class="muted">You logged ${state.meals.length} meals, ${state.exercises.length} workouts, and are ${goalPercent()}% of the way to your goal weight.</p></div>
    </div>
  `;
}

function renderInsights() {
  const totals = totalsForToday();
  const insights = [
    totals.protein < state.goals.protein * 0.8 ? "You are consistently under your protein goal. Add a high-protein snack or lean protein at breakfast." : "Your protein intake is close to target today.",
    Math.abs(weeklyAverage() - state.goals.target) < 120 ? "Your calorie average is close to your fat-loss target." : "Your weekly calorie average has room to tighten toward your target.",
    state.exercises.length >= 2 ? "Your exercise increased this week. Keep recovery days in the plan." : "A short walk after meals would lift your weekly activity without adding pressure.",
    latestWeight() <= state.user.currentWeightKg ? "Your weight trend is moving toward your goal." : "Your latest weight is above your starting point, so use the weekly trend rather than one weigh-in.",
  ];
  $("#insightsView").innerHTML = `
    <div class="grid dashboard-grid">
      <div class="card">
        <div class="section-heading"><div><p class="eyebrow">AI insights</p><h2>Friendly weekly feedback</h2></div><span class="chip">Generated</span></div>
        <div class="insight-list">${insights.map((text) => `<div class="insight-row"><strong>${text}</strong></div>`).join("")}</div>
      </div>
      <div class="card">
        <h2>Coaching focus</h2>
        <p class="muted" style="margin-top:10px">This week, aim for ${state.goals.protein}g protein, keep calories near ${state.goals.target}, and log meals before bedtime for a stronger adherence score.</p>
      </div>
    </div>
  `;
}

function renderSettings() {
  $("#settingsView").innerHTML = `
    <div class="grid dashboard-grid">
      <form class="card form-grid" id="settingsForm">
        ${input("Current weight (kg)", "currentWeightKg", latestWeight(), "number")}
        ${input("Goal weight (kg)", "goalWeightKg", state.user.goalWeightKg, "number")}
        ${input("Calorie target", "target", state.goals.target, "number")}
        ${input("Protein target", "protein", state.goals.protein, "number")}
        ${input("Carbs target", "carbs", state.goals.carbs, "number")}
        ${input("Fat target", "fat", state.goals.fat, "number")}
        ${select("Activity level", "activityLevel", ["sedentary", "light", "moderate", "active", "athlete"], state.user.activityLevel)}
        ${select("Units", "units", ["metric", "imperial"], state.user.units)}
        <label class="full">Dietary preferences<input name="dietary" value="${state.user.dietary.join(", ")}" /></label>
        <label class="full"><input name="notifications" type="checkbox" checked /> Notifications enabled</label>
        <button class="primary-action full" type="submit">Save settings</button>
      </form>
      <div class="schema-panel">
        <div class="section-heading"><h2>Data model</h2><span class="chip">SQL included</span></div>
        <pre>users
goals
meals
food_items
exercise_logs
weight_logs
progress_photos
daily_summaries
ai_meal_estimates</pre>
      </div>
    </div>
  `;
  $("#settingsForm").addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    state.user.currentWeightKg = Number(data.get("currentWeightKg"));
    state.user.goalWeightKg = Number(data.get("goalWeightKg"));
    state.user.activityLevel = data.get("activityLevel");
    state.user.units = data.get("units");
    state.user.dietary = String(data.get("dietary")).split(",").map((item) => item.trim()).filter(Boolean);
    state.goals = {
      ...state.goals,
      target: Number(data.get("target")),
      protein: Number(data.get("protein")),
      carbs: Number(data.get("carbs")),
      fat: Number(data.get("fat")),
    };
    state.weights.push(weight(state.user.currentWeightKg, 0));
    saveState();
    render();
  });
}

function renderProfile() {
  $("#profileView").innerHTML = `
    <div class="grid dashboard-grid">
      <div class="card">
        <div class="section-heading"><div><p class="eyebrow">${state.user.email}</p><h2>${state.user.name}</h2></div><span class="chip">${title(state.user.speed)}</span></div>
        <div class="metric-grid">
          <div class="metric"><span>Height</span><strong>${state.user.heightCm} cm</strong></div>
          <div class="metric"><span>Weight</span><strong>${latestWeight()} kg</strong></div>
          <div class="metric"><span>Goal</span><strong>${state.user.goalWeightKg} kg</strong></div>
        </div>
        <div class="chip-list" style="margin-top:16px">${state.user.dietary.map((item) => `<span class="chip">${title(item)}</span>`).join("")}</div>
      </div>
      <div class="card">
        <h2>Account</h2>
        <p class="muted" style="margin-top:10px">Secure login and signup are represented in this MVP with local account storage. A production build should connect these screens to hashed credentials, sessions, and server-side authorization.</p>
        <button class="secondary-action" id="logoutButton" type="button" style="margin-top:16px">Log out</button>
      </div>
    </div>
  `;
  $("#logoutButton").addEventListener("click", () => {
    state.authed = false;
    saveState();
    showAuth();
  });
}

function weightLineChart() {
  const values = state.weights.slice(-7).map((entry) => Number(entry.value));
  if (!values.length) {
    return `<div class="line-chart"><p class="muted">Add your first weigh-in to start the trend chart.</p></div>`;
  }
  const min = Math.min(...values) - 0.5;
  const max = Math.max(...values) + 0.5;
  const points = values.map((value, index) => {
    const x = values.length === 1 ? 10 : 10 + index * (280 / (values.length - 1));
    const y = 130 - ((value - min) / (max - min)) * 105;
    return `${x},${y}`;
  }).join(" ");
  return `<div class="line-chart"><svg viewBox="0 0 300 150" role="img" aria-label="Weight trend"><polyline points="${points}" fill="none" stroke="#49b983" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/><line x1="10" y1="132" x2="290" y2="132" stroke="#dfe8e5" stroke-width="2"/></svg></div>`;
}

function barChart(values, target, color = "var(--blue)") {
  return `<div class="bar-chart">${values.map((value) => `<div class="bar" style="height:${value ? Math.max(8, Math.min(value / target * 125, 140)) : 4}px; background:${color}" title="${Math.round(value)}"></div>`).join("")}</div>`;
}

function latestWeight() {
  return Number(state.weights[state.weights.length - 1]?.value || state.user.currentWeightKg).toFixed(1);
}

function goalPercent() {
  const start = Number(state.user.currentWeightKg);
  const goal = Number(state.user.goalWeightKg);
  const current = Number(latestWeight());
  if (start === goal) return 0;
  const progress = ((start - current) / (start - goal)) * 100;
  return Math.max(0, Math.min(100, Math.round(progress)));
}

function weeklyAverage() {
  const values = lastSevenDays((date) => caloriesForDate(date));
  return Math.round(values.reduce((sum, value) => sum + value, 0) / 7);
}

function adherenceScore(totals) {
  const calorieScore = Math.max(0, 100 - Math.abs(totals.calories - state.goals.target) / state.goals.target * 100);
  const proteinScore = Math.min(totals.protein / state.goals.protein * 100, 100);
  return Math.round(calorieScore * 0.65 + proteinScore * 0.35);
}

function streak() {
  const loggedDates = new Set([...state.meals, ...state.exercises].map((entry) => dayKey(new Date(entry.loggedAt))));
  let count = 0;
  for (let offset = 0; offset < 30; offset += 1) {
    const date = new Date();
    date.setDate(date.getDate() - offset);
    if (!loggedDates.has(dayKey(date))) break;
    count += 1;
  }
  return count;
}

function lastSevenDays(project) {
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date();
    date.setDate(date.getDate() - (6 - index));
    return project(date);
  });
}

function caloriesForDate(date) {
  return Math.round(sumItems(mealsForDate(date).flatMap((entry) => entry.items)).calories);
}

function proteinForDate(date) {
  return Math.round(sumItems(mealsForDate(date).flatMap((entry) => entry.items)).protein);
}

function exerciseForDate(date) {
  const key = dayKey(date);
  return state.exercises
    .filter((entry) => dayKey(new Date(entry.loggedAt)) === key)
    .reduce((sum, entry) => sum + Number(entry.calories), 0);
}

function mealsForDate(date) {
  const key = dayKey(date);
  return state.meals.filter((entry) => dayKey(new Date(entry.loggedAt)) === key);
}

function dayKey(date) {
  return date.toISOString().slice(0, 10);
}

function localDateTime() {
  const date = new Date();
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset());
  return date.toISOString().slice(0, 16);
}

function title(value) {
  return String(value).replaceAll("-", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

init();
