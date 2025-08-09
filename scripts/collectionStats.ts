// scripts/collectionStats.ts
import { ethers } from "hardhat";
import type { HashCanonNFT } from "../typechain-types";
import * as fs from "fs";
import * as path from "path";

/* ───────── ENV ───────── */
const LIMIT = Number(process.env.LIMIT ?? 8192); // how many tokens to analyse
const LOG_DIR = path.join(process.cwd(), "logs");
if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });

/* optional crown samples from env:
   SAMPLE_CROWNS="—,3:10,5:1"  SAMPLE_PER_BUCKET=2 */
const normalizeCrownKey = (k: string) => {
  const v = k.trim().toLowerCase();
  if (v === "none" || v === "-") return "—";
  return k.trim();
};
const SAMPLE_CROWNS: string[] = (process.env.SAMPLE_CROWNS ?? "")
  .split(",")
  .map(s => s.trim())
  .filter(Boolean)
  .map(normalizeCrownKey);
const SAMPLE_PER_BUCKET = Number(process.env.SAMPLE_PER_BUCKET ?? 1);

/* ───────── Run log tee (console → file) ───────── */
const RUN_LOG_PATH = path.join(LOG_DIR, `run-${Date.now()}-${process.pid}.log`);
const runStream = fs.createWriteStream(RUN_LOG_PATH, { flags: "a" });

const safeStringify = (v: any) => {
  try {
    if (typeof v === "string") return v;
    if (v instanceof Error) return v.stack ?? v.message;
    return JSON.stringify(v);
  } catch {
    return String(v);
  }
};
const formatArgs = (args: any[]) => args.map(safeStringify).join(" ");

const __log = console.log.bind(console);
const __err = console.error.bind(console);
console.log = (...args: any[]) => {
  const line = formatArgs(args);
  runStream.write(line + "\n");
  __log(...args);
};
console.error = (...args: any[]) => {
  const line = formatArgs(args);
  runStream.write(line + "\n");
  __err(...args);
};
process.on("exit", () => runStream.end());
process.on("uncaughtException", e => {
  console.error("[uncaughtException]", e);
  runStream.end();
});
process.on("unhandledRejection", e => {
  console.error("[unhandledRejection]", e as any);
});

/* crown samples store: bucket -> [{id, seed}] */
const crownSamples: Record<string, Array<{ id: number; seed: string }>> = {};

/* ───────── Helpers: bytes/bit ops ───────── */
const hexToBytes = (hex: string): Uint8Array => {
  const h = hex.startsWith("0x") ? hex.slice(2) : hex;
  return new Uint8Array(h.match(/.{1,2}/g)!.map(b => parseInt(b, 16)));
};

const popcountTable = (() => {
  const t = new Uint8Array(256);
  for (let i = 0; i < 256; i++) {
    let x = i, c = 0;
    while (x) { x &= x - 1; c++; }
    t[i] = c;
  }
  return t;
})();

/* ───────── Evenness (as in the contract) ───────── */
function evennessLabelFromSeed(seedHex: string): { score100: number; label: string } {
  const b = hexToBytes(seedHex);
  let ones = 0;
  for (let i = 0; i < b.length; i++) ones += popcountTable[b[i]];
  const zeros = 256 - ones;

  let s = 0;
  if (ones !== 0 && zeros !== 0) {
    const minv = Math.min(ones, zeros);
    const maxv = Math.max(ones, zeros);
    s = Math.floor((minv * 100) / maxv); // 0..100
  }
  const label = s === 100 ? "1.00" : s < 10 ? `0.0${s}` : `0.${s}`;
  return { score100: s, label };
}

/* ───────── Grid 4×64 + Passages (as in the contract) ───────── */
function toBitGrid(seedHex: string): number[][] { // [4][64], values 0/1
  const by = hexToBytes(seedHex);
  const grid = Array.from({ length: 4 }, () => new Array<number>(64).fill(0));
  for (let i = 0; i < 32; i++) {
    const hi = by[i] >> 4;
    const lo = by[i] & 0x0f;
    for (let r = 0; r < 4; r++) {
      grid[r][i * 2]     = (hi >> (3 - r)) & 1;
      grid[r][i * 2 + 1] = (lo >> (3 - r)) & 1;
    }
  }
  return grid;
}

function countPassages(seedHex: string): number {
  const grid = toBitGrid(seedHex);
  const visited = Array.from({ length: 4 }, () => new Array<boolean>(64).fill(false));
  let passages = 0;

  for (let s = 0; s < 64; s++) {
    if (grid[0][s] !== 0 || visited[0][s]) continue;

    const local = Array.from({ length: 4 }, () => new Array<boolean>(64).fill(false));
    const qr = new Uint16Array(256);
    const qc = new Uint16Array(256);
    let head = 0, tail = 0;

    const maybeEnqueue = (nr: number, nc: number) => {
      if (nr >= 4 || nc >= 64) return;
      if (local[nr][nc] || visited[nr][nc] || grid[nr][nc] !== 0) return;
      qr[tail] = nr as any;
      qc[tail] = nc as any;
      tail++;
    };

    let reached = false;
    qr[tail] = 0 as any; qc[tail] = s as any; tail++;

    while (head < tail) {
      const r = qr[head] as number;
      const c = qc[head] as number;
      head++;

      if (local[r][c] || grid[r][c] !== 0) continue;
      local[r][c] = true;
      if (r === 3) reached = true;

      const nr = [r + 1, r === 0 ? 0 : r - 1, r, r];
      const nc = [c, c, (c + 1) % 64, (c + 63) % 64];
      for (let i = 0; i < 4; i++) maybeEnqueue(nr[i], nc[i]);
    }

    if (reached) {
      passages++;
      for (let r = 0; r < 4; r++) for (let c = 0; c < 64; c++) {
        if (local[r][c]) visited[r][c] = true;
      }
    }
  }
  return passages;
}

/* ───────── Crown (port of CrownLib) ───────── */
function crownFromSeed(seedHex: string): { rank: number; qty: number } {
  const g = (() => {
    const grid = toBitGrid(seedHex);
    return grid.map(row => row.map(v => v === 1)); // boolean[4][64]
  })();

  let maxLen = 0;
  let maxCount = 0;

  for (let s = 0; s < 64; s++) {
    for (let len = 2; len <= 64; len++) {
      if (len < maxLen) continue;
      const half = len >> 1;
      let okAll = true;

      for (let r = 0; r < 4 && okAll; r++) {
        for (let k = 0; k < half; k++) {
          const a = g[r][(s + k) % 64];
          const b = g[r][(s + len - 1 - k) % 64];
          if (a !== b) { okAll = false; break; }
        }
      }

      if (okAll) {
        if (len > maxLen) { maxLen = len; maxCount = 1; }
        else { maxCount += 1; }
      }
    }
  }
  return { rank: maxLen, qty: maxCount };
}

/* ───────── main ───────── */
async function main() {
  console.log(`Run log → ${RUN_LOG_PATH}`);

  const [owner] = await ethers.getSigners();

  // 1) deploy local stack
  const Storage  = await ethers.getContractFactory("HashCanonSVGStorage");
  const storage  = await Storage.deploy();

  const Renderer = await ethers.getContractFactory("FullMandalaRenderer");
  const renderer = await Renderer.deploy(await storage.getAddress());

  const NFT      = await ethers.getContractFactory("HashCanonNFT");
  const nft      = (await NFT.deploy(await renderer.getAddress())) as unknown as HashCanonNFT;

  await nft.connect(owner).enableMinting();

  // 2) mint GENESIS
  const PRICE   = ethers.parseEther("0.002");
  const GENESIS = Number(await nft.GENESIS_SUPPLY());
  console.time("mint-all");
  const BATCH = 500;
  for (let i = 0; i < GENESIS; i++) {
    await nft.mint({ value: PRICE });
    if ((i + 1) % BATCH === 0) await ethers.provider.send("evm_mine");
  }
  console.timeEnd("mint-all");

  // 3) analyse
  const total = Number(await nft.totalSupply());
  const limit = Math.min(LIMIT, total);
  console.log(`DEBUG totalSupply = ${total}`);
  console.log(`ANALYSE START (limit=${limit})`);

  const evenBuckets:  Record<string, number> = {};
  const passBuckets:  Record<number, number> = {};
  const crownBuckets: Record<string, number> = {};

  for (let id = 1; id <= limit; id++) {
    const seed = (await (nft as any).seedOf(id)) as string;

    const { label: even } = evennessLabelFromSeed(seed);
    const passages = countPassages(seed);
    const { rank, qty } = crownFromSeed(seed);
    const crown = (rank === 0 || qty === 0) ? "—" : `${rank}:${qty}`;

    // buckets
    evenBuckets[even] = (evenBuckets[even] || 0) + 1;
    passBuckets[passages] = (passBuckets[passages] || 0) + 1;
    crownBuckets[crown] = (crownBuckets[crown] || 0) + 1;

    // optional sampling
    const wantThis = SAMPLE_CROWNS.length === 0 || SAMPLE_CROWNS.includes(crown);
    if (wantThis) {
      const arr = (crownSamples[crown] ||= []);
      if (arr.length < SAMPLE_PER_BUCKET) arr.push({ id, seed });
    }

    // yield
    if (id % 512 === 0) {
      console.log(`processed ${id}/${limit}`);
      await new Promise(r => setImmediate(r));
      (global as any).gc?.();
    }
  }

  console.log("ANALYSE END");

  // 4) console output
  console.log(`\nTokens analysed        : ${limit} (of ${total})`);

  console.log("\nEvenness distribution:");
  Object.keys(evenBuckets)
    .sort((a, b) => parseFloat(a) - parseFloat(b))
    .forEach(k =>
      console.log(
        `  ${k.padEnd(4)}: ${evenBuckets[k]} (${(
          (evenBuckets[k] / limit) * 100
        ).toFixed(2)} %)`
      )
    );

  console.log("\nPassages distribution:");
  Object.keys(passBuckets)
    .map(Number)
    .sort((a, b) => a - b)
    .forEach(k =>
      console.log(
        `  ${k.toString().padStart(2, "0")} : ${passBuckets[k]} (${(
          (passBuckets[k] / limit) * 100
        ).toFixed(2)} %)`
      )
    );

  console.log("\nCrown distribution:");
  Object.keys(crownBuckets)
    .sort((a, b) => {
      if (a === "—") return 1; if (b === "—") return -1;
      const [aw, ab] = a.split(":").map(Number);
      const [bw, bb] = b.split(":").map(Number);
      return aw === bw ? ab - bb : aw - bw;
    })
    .forEach(k =>
      console.log(
        `  ${k.padStart(3)} : ${crownBuckets[k]} (${(
          (crownBuckets[k] / limit) * 100
        ).toFixed(2)} %)`
      )
    );

  // 5) crown samples (console only)
  if (Object.keys(crownSamples).length) {
    console.log("\nCrown samples:");
    const keys = Object.keys(crownSamples).sort((a, b) => {
      if (a === "—") return 1;
      if (b === "—") return -1;
      const [aw, ab] = a.split(":").map(Number);
      const [bw, bb] = b.split(":").map(Number);
      return aw === bw ? ab - bb : aw - bw;
    });
    for (const k of keys) {
      for (const s of crownSamples[k]) {
        console.log(`  ${k.padStart(3)} → tokenId=${s.id} seed=${s.seed}`);
      }
    }
  }

  console.log(`\nRun log saved → ${RUN_LOG_PATH}`);
}

main().catch(err => { console.error("[main.catch]", err); process.exit(1); });