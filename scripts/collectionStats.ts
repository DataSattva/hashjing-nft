// scripts/collectionStats.ts
//
// Quick local‐chain census for HashCanonNFT:
// 1) deploy local stack (SVGStorage → Renderer → NFT)
// 2) mint the entire Genesis supply with progress logs
// 3) print distributions for Evenness, Passages and Crown
//
// Run with:  npx hardhat run scripts/collectionStats.ts
// -------------------------------------------------------------------

import { ethers } from "hardhat";
import { HashCanonNFT } from "../typechain-types";

async function main() {
  const [owner] = await ethers.getSigners();

  // ─── deploy local test stack ───
  const Storage  = await ethers.getContractFactory("HashCanonSVGStorage");
  const storage  = await Storage.deploy();
  const Renderer = await ethers.getContractFactory("FullMandalaRenderer");
  const renderer = await Renderer.deploy(await storage.getAddress());
  const NFT      = await ethers.getContractFactory("HashCanonNFT");
  const nft      = (await NFT.deploy(await renderer.getAddress())) as HashCanonNFT;

  await nft.connect(owner).enableMinting();

  // ─── bulk-mint all 8 192 tokens with progress logging ───
  const PRICE   = ethers.parseEther("0.002");
  const GENESIS = Number(await nft.GENESIS_SUPPLY());

  console.time("mint-all");
  for (let i = 0; i < GENESIS; i++) {
    await nft.connect(owner).mint({ value: PRICE });

    // log progress every 1 000 mints
    if ((i + 1) % 1000 === 0) {
      console.log(`Minted ${i + 1} tokens...`);
    }
  }
  console.timeEnd("mint-all");

  // ─── analyse metadata ───
  const total        = Number(await nft.totalSupply());
  const evenBuckets: Record<string, number> = {};
  const passages:    Record<number, number> = {};
  const crowns:      Record<string, number> = {};

  for (let id = 1; id <= total; id++) {
    const uri  = await nft.tokenURI(id);
    const json = JSON.parse(Buffer.from(uri.split(",")[1], "base64").toString());
    const attr: Record<string, string> = Object.fromEntries(
      json.attributes.map((a: any) => [a.trait_type, a.value])
    );

    // Evenness
    const ev = attr.Evenness;
    evenBuckets[ev] = (evenBuckets[ev] || 0) + 1;

    // Passages
    const p = Number(attr.Passages);
    passages[p] = (passages[p] || 0) + 1;

    // Crown (rank:qty)
    const cr = attr.Crown;
    crowns[cr] = (crowns[cr] || 0) + 1;
  }

  // ─── output stats ───
  console.log(`\nTokens minted        : ${total}`);

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
