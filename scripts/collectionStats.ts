// scripts/collectionStats.ts
//
// Quick local‐chain census:
// 1) deploy HashCanon stack (SVGStorage → Renderer → NFT)
// 2) mint the entire Genesis supply
// 3) print distributions for Evenness, Passages, Crown
//
// Run with:  npx hardhat run scripts/collectionStats.ts
// ────────────────────────────────────────────────────────────────────────────

import { ethers } from "hardhat";
import { HashCanonNFT } from "../typechain-types";

async function main() {
  const [owner] = await ethers.getSigners();

  /* ───────────── deploy local stack ───────────── */
  const Storage   = await ethers.getContractFactory("HashCanonSVGStorage");
  const storage   = await Storage.deploy();

  const Renderer  = await ethers.getContractFactory("FullMandalaRenderer");
  const renderer  = await Renderer.deploy(await storage.getAddress());

  const NFT       = await ethers.getContractFactory("HashCanonNFT");
  const nft       = (await NFT.deploy(await renderer.getAddress())) as HashCanonNFT;

  await nft.connect(owner).enableMinting();

  /* ───────────── bulk-mint Genesis ───────────── */
  const PRICE     = ethers.parseEther("0.002");
  const GENESIS   = Number(await nft.GENESIS_SUPPLY());
  const BATCH     = 500;                           // mine every 500 mints

  console.time("mint-all");
  for (let i = 0; i < GENESIS; i++) {
    await nft.connect(owner).mint({ value: PRICE });
    if ((i + 1) % BATCH === 0) await ethers.provider.send("evm_mine");
  }
  console.timeEnd("mint-all");

  /* ───────────── analyse metadata ───────────── */
  const total          = Number(await nft.totalSupply());
  const evenBuckets:   Record<string, number> = {};
  const passages:      Record<number, number> = {};
  const crowns:        Record<string, number> = {};

  for (let id = 1; id <= total; id++) {
    const uri  = await nft.tokenURI(id);
    const json = JSON.parse(Buffer.from(uri.split(",")[1], "base64").toString());

    const attr: Record<string, string> = Object.fromEntries(
      json.attributes.map((a: any) => [a.trait_type, a.value])
    );

    /* Evenness ("0.00" … "1.00") */
    const ev   = attr.Evenness;
    evenBuckets[ev] = (evenBuckets[ev] || 0) + 1;

    /* Passages (0-32) */
    const p    = Number(attr.Passages);
    passages[p] = (passages[p] || 0) + 1;

    /* Crown ("rank:qty" e.g. "4:1") */
    const cr   = attr.Crown;
    crowns[cr] = (crowns[cr] || 0) + 1;
  }

  /* ───────────── output stats ───────────── */
  console.log(`\nTokens minted : ${total}`);

  console.log("\nEvenness distribution:");
  Object.keys(evenBuckets)
    .sort((a, b) => parseFloat(a) - parseFloat(b))
    .forEach(k =>
      console.log(
        `  ${k.padEnd(4, " ")} : ${evenBuckets[k]} (${(
          (evenBuckets[k] / total) * 100
        ).toFixed(2)} %)`
      )
    );

  console.log("\nPassages distribution:");
  Object.keys(passages)
    .map(Number)
    .sort((a, b) => a - b)
    .forEach(k =>
      console.log(
        `  ${k.toString().padStart(2, "0")} : ${passages[k]} (${(
          (passages[k] / total) * 100
        ).toFixed(2)} %)`
      )
    );

  console.log("\nCrown distribution (rank:qty):");
  Object.keys(crowns)
    .sort((a, b) => {
      const [ra, qa] = a.split(":").map(Number);
      const [rb, qb] = b.split(":").map(Number);
      return ra === rb ? qa - qb : ra - rb;
    })
    .forEach(k =>
      console.log(
        `  ${k.padStart(5, " ")} : ${crowns[k]} (${(
          (crowns[k] / total) * 100
        ).toFixed(2)} %)`
      )
    );
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
