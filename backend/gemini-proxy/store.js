// Where community data lives: Firestore on Google Cloud, or memory for local runs.
//
// On Cloud Run the service account's credentials are picked up automatically. Set STORE=memory
// to run without Google Cloud (data is lost on restart).

const MAX_MEMORY_ROWS = 5000;

class MemoryStore {
  constructor() { this.rows = { prices: [], reports: [] }; }
  async add(kind, row) {
    const list = this.rows[kind];
    list.push({ ...row, createdAt: new Date() });
    if (list.length > MAX_MEMORY_ROWS) list.shift();
  }
  async find(kind, filters, limit) {
    const list = this.rows[kind].filter((row) => Object.entries(filters).every(([k, v]) => row[k] === v));
    return list.slice(-limit).reverse();
  }
}

class FirestoreStore {
  constructor(Firestore) {
    this.db = new Firestore({ ignoreUndefinedProperties: true });
  }
  async add(kind, row) {
    await this.db.collection(kind).add({ ...row, createdAt: new Date() });
  }
  async find(kind, filters, limit) {
    // Equality filters only, so no composite index is needed.
    let query = this.db.collection(kind);
    for (const [key, value] of Object.entries(filters)) query = query.where(key, "==", value);
    const snapshot = await query.limit(limit).get();
    return snapshot.docs.map((doc) => {
      const data = doc.data();
      return { ...data, createdAt: data.createdAt?.toDate ? data.createdAt.toDate() : data.createdAt };
    });
  }
}

export async function openStore() {
  if (process.env.STORE === "memory") return { store: new MemoryStore(), kind: "memory" };
  try {
    const { Firestore } = await import("@google-cloud/firestore");
    return { store: new FirestoreStore(Firestore), kind: "firestore" };
  } catch (error) {
    console.warn(`Firestore unavailable (${error.message}); using memory.`);
    return { store: new MemoryStore(), kind: "memory" };
  }
}
