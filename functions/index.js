const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const bcrypt = require("bcryptjs");

admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();
const region = "southamerica-east1";

function assertAuth(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login obrigatorio.");
  return request.auth.uid;
}

async function userProfile(uid) {
  const doc = await db.collection("users").doc(uid).get();
  if (!doc.exists || doc.data().active !== true) {
    throw new HttpsError("permission-denied", "Usuario inativo ou inexistente.");
  }
  return { id: doc.id, ...doc.data() };
}

async function assertAdmin(request) {
  const uid = assertAuth(request);
  const profile = await userProfile(uid);
  if (profile.role !== "admin") {
    throw new HttpsError("permission-denied", "Apenas admin pode executar esta acao.");
  }
  return profile;
}

function haversineMeters(aLat, aLng, bLat, bLng) {
  const earth = 6371000;
  const toRad = (value) => (value * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const lat1 = toRad(aLat);
  const lat2 = toRad(bLat);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return earth * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

exports.createFirstAdmin = onCall({ region }, async (request) => {
  const setupDoc = db.collection("system").doc("setup");
  const setup = await setupDoc.get();
  if (setup.exists && setup.data().firstAdminCreated === true) {
    throw new HttpsError("failed-precondition", "Primeiro admin ja foi criado.");
  }
  const { name, email, password, pin } = request.data || {};
  if (!name || !email || !password || !pin) {
    throw new HttpsError("invalid-argument", "Nome, e-mail, senha e PIN sao obrigatorios.");
  }
  const user = await auth.createUser({ email, password, displayName: name });
  await auth.setCustomUserClaims(user.uid, { role: "admin" });
  await db.collection("users").doc(user.uid).set({
    name,
    email,
    role: "admin",
    active: true,
    hourlyRate: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await db.collection("pinCredentials").doc(user.uid).set({
    pinHash: await bcrypt.hash(String(pin), 12),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await setupDoc.set({
    firstAdminCreated: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { uid: user.uid };
});

exports.seedStore = onCall({ region }, async (request) => {
  await assertAdmin(request);
  await db.collection("stores").doc("le-racoes-sao-gabriel").set(
    {
      name: "Lê Rações",
      address: "R. Anapurus, 242 - Lj 03 - São Gabriel, Belo Horizonte - MG, 31980-140",
      latitude: -19.8587,
      longitude: -43.9248,
      radiusMeters: 40,
      coordinateNeedsReview: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return { ok: true };
});

exports.createEmployee = onCall({ region }, async (request) => {
  await assertAdmin(request);
  const { name, email, password, pin, role = "employee", hourlyRate = 0 } = request.data || {};
  if (!name || !email || !password || !pin) {
    throw new HttpsError("invalid-argument", "Nome, e-mail, senha e PIN sao obrigatorios.");
  }
  if (!["employee", "admin"].includes(role)) {
    throw new HttpsError("invalid-argument", "Tipo de conta invalido.");
  }
  const user = await auth.createUser({ email, password, displayName: name });
  await auth.setCustomUserClaims(user.uid, { role });
  await db.collection("users").doc(user.uid).set({
    name,
    email,
    role,
    active: true,
    hourlyRate: Number(hourlyRate) || 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await db.collection("pinCredentials").doc(user.uid).set({
    pinHash: await bcrypt.hash(String(pin), 12),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { uid: user.uid };
});

exports.loginWithPin = onCall({ region }, async (request) => {
  const { pin } = request.data || {};
  if (!pin || String(pin).length < 4) {
    throw new HttpsError("invalid-argument", "PIN invalido.");
  }
  const credentials = await db.collection("pinCredentials").get();
  for (const doc of credentials.docs) {
    const credential = doc.data();
    if (credential.pinHash && (await bcrypt.compare(String(pin), credential.pinHash))) {
      const user = await db.collection("users").doc(doc.id).get();
      if (!user.exists || user.data().active !== true) continue;
      const token = await auth.createCustomToken(doc.id, { role: user.data().role || "employee" });
      return { token };
    }
  }
  throw new HttpsError("permission-denied", "PIN nao encontrado.");
});

exports.registerPunch = onCall({ region }, async (request) => {
  const uid = assertAuth(request);
  const profile = await userProfile(uid);
  const { type, latitude, longitude, accuracy, justification, storeId } = request.data || {};
  const validTypes = ["entry", "lunchOut", "lunchIn", "exit"];
  if (!validTypes.includes(type)) throw new HttpsError("invalid-argument", "Tipo de ponto invalido.");
  if (typeof latitude !== "number" || typeof longitude !== "number") {
    throw new HttpsError("invalid-argument", "Localizacao obrigatoria.");
  }

  const storeRef = db.collection("stores").doc(storeId || "le-racoes-sao-gabriel");
  const store = await storeRef.get();
  if (!store.exists) throw new HttpsError("failed-precondition", "Loja nao cadastrada.");
  const storeData = store.data();
  const distanceMeters = haversineMeters(latitude, longitude, storeData.latitude, storeData.longitude);
  const outOfRadius = distanceMeters > Number(storeData.radiusMeters || 40);
  if (outOfRadius && !String(justification || "").trim()) {
    throw new HttpsError("failed-precondition", "Ponto fora do raio permitido. Informe justificativa.");
  }

  const punchRef = await db.collection("punches").add({
    employeeId: uid,
    employeeName: profile.name,
    type,
    storeId: store.id,
    latitude,
    longitude,
    accuracy: Number(accuracy) || null,
    storeLatitude: storeData.latitude,
    storeLongitude: storeData.longitude,
    distanceMeters,
    radiusMeters: storeData.radiusMeters,
    outOfRadius,
    justification: justification || null,
    serverTime: admin.firestore.FieldValue.serverTimestamp(),
    edited: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { id: punchRef.id, outOfRadius, distanceMeters };
});

exports.editPunch = onCall({ region }, async (request) => {
  const adminProfile = await assertAdmin(request);
  const { punchId, newTime, newType, justification } = request.data || {};
  if (!punchId || !newTime || !newType || !String(justification || "").trim()) {
    throw new HttpsError("invalid-argument", "Ponto, nova data, tipo e justificativa sao obrigatorios.");
  }
  const ref = db.collection("punches").doc(punchId);
  const before = await ref.get();
  if (!before.exists) throw new HttpsError("not-found", "Ponto nao encontrado.");

  const update = {
    serverTime: admin.firestore.Timestamp.fromDate(new Date(newTime)),
    type: newType,
    edited: true,
    editJustification: justification,
    editedBy: adminProfile.id,
    editedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  await ref.update(update);
  await db.collection("changeLogs").add({
    entity: "punch",
    entityId: punchId,
    action: "edit",
    before: before.data(),
    after: update,
    justification,
    adminId: adminProfile.id,
    adminName: adminProfile.name,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

exports.approveOvertime = onCall({ region }, async (request) => {
  const adminProfile = await assertAdmin(request);
  const { employeeId, weekStart, minutes, justification } = request.data || {};
  if (!employeeId || !weekStart || !minutes || !String(justification || "").trim()) {
    throw new HttpsError("invalid-argument", "Funcionario, semana, minutos e justificativa sao obrigatorios.");
  }
  const ref = await db.collection("overtimeApprovals").add({
    employeeId,
    weekStart: admin.firestore.Timestamp.fromDate(new Date(weekStart)),
    minutes: Number(minutes),
    justification,
    approvedBy: adminProfile.id,
    approvedByName: adminProfile.name,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { id: ref.id };
});
