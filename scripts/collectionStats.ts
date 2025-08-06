// scripts/collectionStats.ts
//
// Local-chain census for HashCanon:
// 1) deploy full on-chain stack (SVGStorage → Renderer → NFT)
// 2) mint the whole Genesis supply (8 192)
// 3) print distributions for Evenness, Passages, Crown
//
// Run:  NODE_OPTIONS="--max_old_space_size=6144" npx hardhat run scripts/collectionStats.ts
// ---------------------------------------------------------------------------

import { ethers } from "hardhat";
import { HashCanonNFT } from "../typechain-types";

async function main(): Promise<void> {
  const [owner] = await ethers.getSigners();

  /* ───────────────── deploy local stack ───────────────── */
  const Storage  = await ethers.getContractFactory("HashCanonSVGStorage");
  const storage  = await Storage.deploy();

  const Renderer = await ethers.getContractFactory("FullMandalaRenderer");
  const renderer = await Renderer.deploy(await storage.getAddress());

  const NFT      = await ethers.getContractFactory("HashCanonNFT");
  const nft      = (await NFT.deploy(await renderer.getAddress())) as HashCanonNFT;

  await nft.enableMinting();

  /* ───────────────── bulk-mint Genesis ───────────────── */
  const PRICE   = ethers.parseEther("0.002");        // mint price
  const GENESIS = Number(await nft.GENESIS_SUPPLY()); // 8 192
  const BATCH   = 500;                               // mine snapshot every 500 tx

  console.time("mint-all");
  for (let i = 0; i < GENESIS; i++) {
    await nft.mint({ value: PRICE });

    // progress log every 1 000 tokens
    if ((i + 1) % 1000 === 0) {
      console.log(`Minted ${(i + 1).toString().padStart(4, "0")} tokens…`);
    }
    if ((i + 1) % BATCH === 0) {
      await ethers.provider.send("evm_mine");        // reduce snapshot growth
    }
  }
  console.timeEnd("mint-all");

  /* ───────────────── analyse metadata ───────────────── */
  const total         = Number(await nft.totalSupply());
  const evenBuckets:  Record<string, number> = {};
  const passagesDist: Record<number,  number> = {};
  const crownsDist:   Record<string, number> = {};
  let perfectEven = 0;

  for (let id = 1; id <= total; id++) {
    const uri  = await nft.tokenURI(id);
    const json = JSON.parse(
      Buffer.from(uri.split(",")[1], "base64").toString()
    );

    const attr: Record<string, string> = Object.fromEntries(
      (json.attributes as any[]).map(a => [a.trait_type, a.value])
    );

    /* ─── Evenness ─── */
    const ev = attr.Evenness;                        // "0.00" … "1.00"
    if (ev === "1.0" || ev === "1.00") perfectEven++;
    evenBuckets[ev] = (evenBuckets[ev] || 0) + 1;

    /* ─── Passages ─── */
    const p = Number(attr.Passages);
    passagesDist[p] = (passagesDist[p] || 0) + 1;

    /* ─── Crown ─── */
    const cr = attr.Crown;                           // "rank:qty"
    crownsDist[cr] = (crownsDist[cr] || 0) + 1;

    // allow garbage-collector to free strings earlier
    delete json.attributes;
  }

  /* ───────────────── print report ───────────────── */
  console.log(`\nTokens minted : ${total}`);
  console.log(`Perfect 1.00  : ${perfectEven} (${((perfectEven / total) * 100).toFixed(2)} %)`);

  console.log("\nEvenness distribution:");
  Object.keys(evenBuckets)
    .sort((a, b) => parseFloat(a) - parseFloat(b))
    .forEach(k =>
      console.log(`  ${k.padEnd(4)} : ${evenBuckets[k]} (${((evenBuckets[k] / total) * 100).toFixed(2)} %)`)
    );

  console.log("\nPassages distribution:");
  Object.keys(passagesDist)
    .map(Number)
    .sort((a, b) => a - b)
    .forEach(k =>
      console.log(`  ${k.toString().padStart(2, "0")} : ${passagesDist[k]} (${((passagesDist[k] / total) * 100).toFixed(2)} %)`)
    );

  console.log("\nCrown distribution (rank:qty):");
  Object.keys(crownsDist)
    .sort((a, b) => {
      const [ra, qa] = a.split(":").map(Number);
      const [rb, qb] = b.split(":").map(Number);
      return ra === rb ? qa - qb : ra - rb;
    })
    .forEach(k =>
      console.log(`  ${k.padStart(5)} : ${crownsDist[k]} (${((crownsDist[k] / total) * 100).toFixed(2)} %)`)
    );
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
